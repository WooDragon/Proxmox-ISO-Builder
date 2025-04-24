#!/bin/bash

set -e
set -o pipefail

DEBIAN_ISO="$1"
OUTPUT_ISO="$2"

if [[ -z "$DEBIAN_ISO" || -z "$OUTPUT_ISO" ]]; then
  echo "Usage: $0 <debian-iso> <output-iso>"
  exit 1
fi

WORKDIR=$(mktemp -d)
mkdir -p "$WORKDIR/iso" "$WORKDIR/temp" "$WORKDIR/pve"

# -----------------------------
# Step 1: Mount and extract the ISO
# -----------------------------
mount -o loop "$DEBIAN_ISO" "$WORKDIR/temp"
cp -a "$WORKDIR/temp/." "$WORKDIR/iso"
umount "$WORKDIR/temp"

# -----------------------------
# Step 2: Add Proxmox repo (temporary) and download packages
# -----------------------------
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
  > /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

# 安装 apt-rdepends 工具（如果尚未安装）
apt-get update
apt-get install -y apt-rdepends

# -----------------------------
# (A) 函数: resolve_virtual_pkg
#    用来把“虚拟包”映射成“真实包名”
# -----------------------------
resolve_virtual_pkg() {
  local pkg="$1"

  # apt-cache show 能否找到真实的 "Package: $pkg"
  if apt-cache show "$pkg" 2>/dev/null | grep -q "^Package: $pkg"; then
    # 说明它是一个真实存在的包，可直接返回
    echo "$pkg"
  else
    # 尝试解析 "Reverse Provides"
    # apt-cache showpkg $pkg 的格式中:
    #   Reverse Provides:
    #    perl  perlapi-5.36.0
    # 意味着 perl 提供 perlapi-5.36.0
    local providers
    # 使用 awk 拿到 Reverse Provides 部分并提取第1列包名
    providers=$(apt-cache showpkg "$pkg" 2>/dev/null \
      | awk '/Reverse Provides:/{flag=1; next} /^$/{flag=0} flag {print $1}' \
      | cut -d' ' -f1 \
      | sort -u)

    # 如果找到提供者，就输出，否则只能返回原包名(大概率下载会失败)
    if [[ -n "$providers" ]]; then
      echo "$providers"
    else
      echo "$pkg"
    fi
  fi
}

export -f resolve_virtual_pkg

# -----------------------------
# (2.1) 下载几个必需的包（不包含 proxmox-ve） 
#       包括 postfix, open-iscsi, chrony
# -----------------------------
echo "=== Downloading essential packages: postfix, open-iscsi, chrony ==="
apt-get install --download-only -y postfix open-iscsi chrony

# -----------------------------
# (2.2) 下载 “standard” 任务及附加包所需的 .deb
#       先获取 standard 任务下的所有包名:
# -----------------------------
echo "=== Installing tasksel and downloading standard task packages ==="
apt-get install --download-only -y tasksel

# 使用 tasksel 获取标准任务包
STANDARD_PACKAGES=$(tasksel --task-packages standard)

# -----------------------------
# (2.3) 针对 curl 做同样处理（先拿到依赖，再 reinstall）
# -----------------------------
echo "==== Listing dependencies for curl using apt-rdepends ===="
# 使用 apt-rdepends 递归列出所有依赖
CURL_DEPS=$(apt-rdepends curl \
  | grep -vE '^ ' \
  | grep -vE '^(Reading|Build-Depends|Suggests|Recommends|Conflicts|Breaks|PreDepends)' \
  | sort -u)
echo "curl deps: $CURL_DEPS"

if [[ -n "$CURL_DEPS" ]]; then
  apt-get install --download-only --reinstall -y $CURL_DEPS curl
else
  apt-get install --download-only --reinstall -y curl
fi

# -----------------------------
# (2.4) 用 apt-rdepends 处理 proxmox-default-kernel, proxmox-ve, openssh-server, gnupg, tasksel环节
#    并行化 resolve_virtual_pkg 以加速镜像生成
# -----------------------------
echo "=== Recursively listing proxmox-ve dependencies via apt-rdepends ==="
ALL_PVE_DEPS=$(apt-rdepends proxmox-default-kernel proxmox-ve openssh-server gnupg tasksel dmidecode qrencode btrfs-progs parted \
  | grep -v '^ ' \
  | grep -vE '^(Reading|Build-Depends|Suggests|Recommends|Conflicts|Breaks|PreDepends|Enhances|Replaces|Provides)' \
  | sort -u)

# 把这些包本身也加进去
ALL_PVE_DEPS+=" proxmox-default-kernel proxmox-ve openssh-server gnupg tasksel dmidecode qrencode btrfs-progs parted"

# 并行化解析虚拟包
echo "=== Resolving virtual packages in parallel ==="
RESOLVED_DEPS=$(printf "%s\n" $ALL_PVE_DEPS | xargs -n1 -P"$(nproc)" -I{} bash -c 'resolve_virtual_pkg "{}"' | tr '\n' ' ')

echo "Resolved dependencies: $RESOLVED_DEPS"

# -----------------------------
# (2.6) 下载所有依赖(含可能的虚拟包)
#    并行化下载过程
# -----------------------------
ORIGINAL_DIR=$(pwd)
CACHE_DIR="/var/cache/apt/archives"
chown -R _apt:root "$CACHE_DIR"
chmod -R 755 "$CACHE_DIR"
mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

echo "=== Downloading all dependencies in parallel (ignoring errors) ==="
echo "Resolved packages: $RESOLVED_DEPS"

# 使用 xargs 并行下载包
printf "%s\n" $RESOLVED_DEPS | xargs -n1 -P"$(nproc)" -I{} bash -c '
  if ! apt-get download "{}"; then
    echo "Failed to download {}" >&2
  fi
'

cd "$ORIGINAL_DIR"
echo "=== All dependencies downloaded to $CACHE_DIR ==="

# -----------------------------
# (2.7) 将下载好的 .deb 拷贝到离线仓库目录 $WORKDIR/pve
# -----------------------------
echo "==== Copying downloaded packages to $WORKDIR/pve ===="
cp /var/cache/apt/archives/*.deb "$WORKDIR/pve/" || true

# 生成离线仓库
cd "$WORKDIR/pve"
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd -

# -----------------------------
# Step 2.1: Download and add Proxmox GPG key
# -----------------------------
echo "==== Downloading Proxmox GPG key ===="
mkdir -p "$WORKDIR/iso/etc/apt/trusted.gpg.d"
wget http://mirrors.ustc.edu.cn/proxmox/debian/proxmox-release-bookworm.gpg -O "$WORKDIR/iso/etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg"

# -----------------------------
# Step 3: Copy preseed + local repo + scripts to ISO
# -----------------------------
cp preseed.cfg "$WORKDIR/iso/"
cp -r "$WORKDIR/pve" "$WORKDIR/iso/"

# 复制 post-install 脚本到 ISO 的 /scripts/ 目录
mkdir -p "$WORKDIR/iso/scripts"
cp post_install_scripts/*.sh "$WORKDIR/iso/scripts/"

# -----------------------------
# Step 4: Modify bootloader
# BIOS: isolinux/txt.cfg & UEFI: grub.cfg
# -----------------------------
# 4.1 BIOS isolinux
sed -i '/timeout/s/.*/timeout 100/' "$WORKDIR/iso/isolinux/isolinux.cfg"

echo "=== Adding Automated Installation entries to grub.cfg ==="
AUTOMATED_INSTALL_ENTRY='menuentry "Automated Installation" {
    set gfxpayload=keep
    linux /install.amd/vmlinuz auto=true priority=high locale=zh_CN.UTF-8 keymap=us file=/cdrom/preseed.cfg --
    initrd /install.amd/initrd.gz
}

menuentry "Automated Installation(console)" {
    set gfxpayload=keep
    linux /install.amd/vmlinuz auto=true priority=high locale=zh_CN.UTF-8 keymap=us file=/cdrom/preseed.cfg console=tty0 console=ttyS0,115200n8 --
    initrd /install.amd/initrd.gz
}'

# Insert the entry before the first "menuentry" line using awk
awk -v new_entry="$AUTOMATED_INSTALL_ENTRY" '!found && /menuentry/ {print new_entry; found=1} {print}' "$WORKDIR/iso/boot/grub/grub.cfg" > "$WORKDIR/iso/boot/grub/grub.cfg.tmp" && mv "$WORKDIR/iso/boot/grub/grub.cfg.tmp" "$WORKDIR/iso/boot/grub/grub.cfg"

# 4.2 UEFI grub.cfg
sed -i '/set timeout=/s/.*/set timeout=10/' "$WORKDIR/iso/boot/grub/grub.cfg"

echo "=== Adding Automated Installation entries to txt.cfg ==="
AUTOMATED_INSTALL_ENTRY='label auto
  menu label ^Automated Installation
  kernel /install.amd/vmlinuz
  append initrd=/install.amd/initrd.gz auto=true priority=high locale=zh_CN.UTF-8 keymap=us file=/cdrom/preseed.cfg --

label auto-console
  menu label ^Automated Installation(console)
  kernel /install.amd/vmlinuz
  append initrd=/install.amd/initrd.gz auto=true priority=high locale=zh_CN.UTF-8 keymap=us file=/cdrom/preseed.cfg console=tty0 console=ttyS0,115200n8 --'

# Insert the entry before the first "label" line using awk
awk -v new_entry="$AUTOMATED_INSTALL_ENTRY" '!found && /label/ {print new_entry; found=1} {print}' "$WORKDIR/iso/isolinux/txt.cfg" > "$WORKDIR/iso/isolinux/txt.cfg.tmp" && mv "$WORKDIR/iso/isolinux/txt.cfg.tmp" "$WORKDIR/iso/isolinux/txt.cfg"

# -----------------------------
# Step 5: Build custom ISO
# -----------------------------
xorriso \
  -outdev "$OUTPUT_ISO" \
  -volid "Proxmox_Custom" \
  -padding 0 \
  -compliance no_emul_toc \
  -map "$WORKDIR/iso" / \
  -chmod 0755 / -- \
  -boot_image isolinux dir=/isolinux \
  -boot_image any next \
  -boot_image any efi_path=boot/grub/efi.img \
  -boot_image isolinux partition_entry=gpt_basdat

isohybrid --uefi "$OUTPUT_ISO"

rm -rf "$WORKDIR"

echo "Custom ISO created: $OUTPUT_ISO"

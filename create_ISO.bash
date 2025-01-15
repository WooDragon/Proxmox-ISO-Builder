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

# (2.1) 下载几个必需的包（不包含 proxmox-ve） 
#       包括 postfix, open-iscsi, chrony
apt-get install --download-only -y postfix open-iscsi chrony

# (2.2) 下载 “standard” 任务及附加包所需的 .deb
#       先获取 standard 任务下的所有包名:
STANDARD_PACKAGES=$(tasksel --task-packages standard)

# (2.3) 下载 standard 任务以及部分附加包 (不含 curl)
#       注意这里先不包含 curl，让我们后面单独处理它。
apt-get install --download-only --reinstall -y \
  $STANDARD_PACKAGES \
  openssh-server \
  gnupg \
  tasksel 

# (2.3) 针对 curl 做同样处理（先拿到依赖，再 reinstall）
echo "==== Listing dependencies for curl using apt-rdepends ===="
# 使用 apt-rdepends 递归列出所有依赖
CURL_DEPS=$(apt-rdepends curl \
  | grep -vE '^ ' \
  | grep -vE '^(Reading|Build\-Depends|Suggests|Recommends|Conflicts|Breaks|PreDepends)' \
  | sort -u)
echo "curl deps: $CURL_DEPS"

if [[ -n "$CURL_DEPS" ]]; then
  apt-get install --download-only --reinstall -y $CURL_DEPS curl
else
  apt-get install --download-only --reinstall -y curl
fi

# (2.4) 使用 apt-rdepends 处理 proxmox-ve
echo "=== Recursively listing proxmox-ve dependencies via apt-rdepends ==="
ALL_PVE_DEPS=$(apt-rdepends proxmox-ve \
  | grep -v '^ ' \
  | grep -vE '^(Reading|Build-Depends|Suggests|Recommends|Conflicts|Breaks|PreDepends|Enhances|Replaces|Provides)' \
  | sort -u)

# 将 proxmox-ve 本身加入依赖列表
ALL_PVE_DEPS+=" proxmox-ve"

echo "=== Downloading all dependencies (ignoring errors) ==="
cd /var/cache/apt/archives/
sudo chmod -R o+rwx /var/cache/apt/archives
sudo chown -R _apt:root /var/cache/apt/archives
# 逐个下载依赖，忽略错误
for pkg in $ALL_PVE_DEPS; do
  echo "Downloading $pkg..."
  apt-get download "$pkg" || echo "Failed to download $pkg, skipping."
done

echo "=== All available dependencies have been downloaded ==="

# (2.5) 将下载好的 .deb 拷贝到离线仓库目录 $WORKDIR/pve
echo "==== Copying downloaded packages to $WORKDIR/pve ===="
cp /var/cache/apt/archives/*.deb "$WORKDIR/pve/" || true

# 生成离线仓库
cd "$WORKDIR/pve"
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd -

# -----------------------------
# Step 3: Copy preseed + local repo to ISO
# -----------------------------
cp preseed.cfg "$WORKDIR/iso/"
cp -r "$WORKDIR/pve" "$WORKDIR/iso/"

# -----------------------------
# Step 4: Modify bootloader
# BIOS: isolinux/txt.cfg & UEFI: grub.cfg
# -----------------------------
# 4.1 BIOS isolinux
sed -i '/timeout/s/.*/timeout 100/' "$WORKDIR/iso/isolinux/isolinux.cfg"
sed -i '/default/s/.*/default auto/' "$WORKDIR/iso/isolinux/txt.cfg"

cat <<EOF >> "$WORKDIR/iso/isolinux/txt.cfg"

label auto
  menu label ^Automated Installation
  kernel /install.amd/vmlinuz
  append initrd=/install.amd/initrd.gz auto=true priority=high locale=zh_CN.UTF-8 keymap=us file=/cdrom/preseed.cfg --
EOF

# 4.2 UEFI grub.cfg
sed -i '/set timeout=/s/.*/set timeout=10/' "$WORKDIR/iso/boot/grub/grub.cfg"

cat <<EOF >> "$WORKDIR/iso/boot/grub/grub.cfg"

menuentry "Automated Installation" {
    set gfxpayload=keep
    linux /install.amd/vmlinuz auto=true priority=high locale=zh_CN.UTF-8 keymap=us file=/cdrom/preseed.cfg --
    initrd /install.amd/initrd.gz
}
EOF

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

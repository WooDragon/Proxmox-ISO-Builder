#!/bin/bash

set -e

# 输入和输出 ISO 文件名
DEBIAN_ISO="$1"
OUTPUT_ISO="$2"

if [[ -z "$DEBIAN_ISO" || -z "$OUTPUT_ISO" ]]; then
  echo "Usage: $0 <debian-iso> <output-iso>"
  exit 1
fi

echo "[INFO] Debian ISO: $DEBIAN_ISO"
echo "[INFO] Output ISO: $OUTPUT_ISO"

# Step 1: 准备工作目录
echo "[INFO] Preparing working directories..."
mkdir -p temp iso pve

# Step 2: 挂载原始 Debian ISO 并复制内容
echo "[INFO] Mounting and extracting Debian ISO..."
mount -o loop "$DEBIAN_ISO" temp
cp -a temp/. iso
chmod -R 644 iso
umount temp

# Step 3: 配置 Proxmox 仓库并下载所有依赖包
echo "[INFO] Configuring Proxmox repository..."
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

# 更新 APT 索引
echo "[INFO] Updating APT cache..."
apt-get update

# 下载所有依赖包到默认缓存目录
echo "[INFO] Downloading Proxmox dependencies (install-only mode)..."
apt-get install --download-only -y proxmox-ve postfix open-iscsi chrony

# 将缓存目录中的所有 .deb 文件复制到 `pve/` 目录
echo "[INFO] Copying .deb files to pve directory..."
cp /var/cache/apt/archives/*.deb pve/

# 检查是否成功复制了 .deb 文件
if [ "$(ls -A ./pve/*.deb 2>/dev/null)" ]; then
  echo "[INFO] .deb files successfully copied to ./pve/"
else
  echo "[ERROR] No .deb files found in ./pve/! Check the download step."
  exit 1
fi

# Step 4: 生成 `Packages` 和 `Packages.gz` 文件
echo "[INFO] Generating local repository metadata..."
cd pve
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd ..

# Step 5: 将本地仓库和 preseed 文件复制到 ISO
echo "[INFO] Copying local repository and preseed file to ISO..."
cp preseed.cfg iso/  # 确保 preseed.cfg 存在并正确配置
cp -r pve iso/

# Step 6: 修改启动菜单，启用无人值守安装
echo "[INFO] Modifying bootloader configuration for automated install..."
sed -i "s+quiet+quiet auto=true locale=en_US.UTF-8 keymap=us file=/cdrom/preseed.cfg+g" \
  iso/isolinux/txt.cfg iso/boot/grub/grub.cfg

# Step 7: 使用 xorriso 制作新的 ISO
echo "[INFO] Building the custom ISO..."
xorriso \
  -outdev "$OUTPUT_ISO" \
  -volid "Proxmox_Custom" \
  -padding 0 \
  -compliance no_emul_toc \
  -map "./iso" / \
  -chmod 0755 / -- \
  -boot_image isolinux dir=/isolinux \
  -boot_image any next \
  -boot_image any efi_path=boot/grub/efi.img \
  -boot_image isolinux partition_entry=gpt_basdat

# Step 8: 将 ISO 转为混合模式 (BIOS & UEFI)
echo "[INFO] Converting ISO to hybrid mode..."
isohybrid --uefi "$OUTPUT_ISO"

# Step 9: 清理临时文件
echo "[INFO] Cleaning up temporary files..."
rm -rf temp iso pve

echo "[INFO] Custom ISO successfully created: $OUTPUT_ISO"

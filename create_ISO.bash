#!/bin/bash

set -e  # 出现错误立即退出
set -o pipefail  # 确保管道中的每一步都正确执行

DEBIAN_ISO="$1"
OUTPUT_ISO="$2"

if [[ -z "$DEBIAN_ISO" || -z "$OUTPUT_ISO" ]]; then
  echo "Usage: $0 <debian-iso> <output-iso>"
  exit 1
fi

echo "[INFO] Debian ISO: $DEBIAN_ISO"
echo "[INFO] Output ISO: $OUTPUT_ISO"

# Step 1: Prepare working directories
WORKDIR=$(mktemp -d)
mkdir -p "$WORKDIR/iso" "$WORKDIR/temp" "$WORKDIR/pve"

# Step 2: Mount and extract the Debian ISO
echo "[INFO] Mounting and extracting Debian ISO..."
mount -o loop "$DEBIAN_ISO" "$WORKDIR/temp"
cp -a "$WORKDIR/temp/." "$WORKDIR/iso"
chmod -R 644 "$WORKDIR/iso"
umount "$WORKDIR/temp"

# Step 3: Add Proxmox repository and download packages
echo "[INFO] Configuring Proxmox repository..."
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
  > /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

apt-get update

echo "[INFO] Downloading Proxmox packages and dependencies..."
apt-get install --download-only -y proxmox-ve postfix open-iscsi chrony

echo "[INFO] Copying downloaded .deb files to ./pve directory..."
cp /var/cache/apt/archives/*.deb "$WORKDIR/pve/"

# Ensure .deb files are downloaded
if [ "$(ls -A "$WORKDIR/pve/"*.deb 2>/dev/null)" ]; then
  echo "[INFO] .deb files successfully copied to ./pve/"
else
  echo "[ERROR] No .deb files found in ./pve/! Check the download step."
  exit 1
fi

# Step 4: Generate Packages and Packages.gz for local repository
echo "[INFO] Generating local repository metadata..."
cd "$WORKDIR/pve"
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd "$WORKDIR"

# Step 5: Copy local repository & preseed file into ISO
echo "[INFO] Copying PVE repository and preseed configuration to ISO..."
cp preseed.cfg "$WORKDIR/iso/"
cp -r "$WORKDIR/pve" "$WORKDIR/iso/"

# Step 6: Modify bootloader for automated install
echo "[INFO] Modifying bootloader for automated installation..."
sed -i "s+quiet+quiet priority=high locale=en_US.UTF-8 keymap=us file=/cdrom/preseed.cfg+g" \
  "$WORKDIR/iso/isolinux/txt.cfg" "$WORKDIR/iso/boot/grub/grub.cfg"

# Step 7: Build the custom ISO with xorriso
echo "[INFO] Building the custom ISO..."
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

# Step 8: Make ISO hybrid (BIOS + UEFI)
echo "[INFO] Converting ISO to hybrid (BIOS + UEFI)..."
isohybrid --uefi "$OUTPUT_ISO"

# Cleanup
echo "[INFO] Cleaning up temporary files..."
rm -rf "$WORKDIR"

echo "[INFO] Custom ISO created successfully: $OUTPUT_ISO"

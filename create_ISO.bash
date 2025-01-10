#!/bin/bash

set -e

# Parameters
DEBIAN_ISO="$1"
OUTPUT_ISO="$2"

if [[ -z "$DEBIAN_ISO" || -z "$OUTPUT_ISO" ]]; then
  echo "Usage: $0 <debian-iso> <output-iso>"
  exit 1
fi

echo "[INFO] Debian ISO: $DEBIAN_ISO"
echo "[INFO] Output ISO: $OUTPUT_ISO"

# Step 1: Prepare directories
rm -rf iso pve dependencies.txt
mkdir -p iso pve

# Step 2: Extract the Debian ISO using bsdtar
echo "[INFO] Extracting Debian ISO..."
bsdtar -C iso -xf "$DEBIAN_ISO"

# Step 3: Configure Proxmox VE repo & download packages
echo "[INFO] Setting up Proxmox repository..."
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg > /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
apt-get update

# Step 4: Collect proxmox-ve dependency list
echo "[INFO] Collecting proxmox-ve dependencies..."
apt-rdepends proxmox-ve | grep -v "^ " | sort -u > dependencies.txt

# Step 5: Download .deb packages into local pve/ folder
echo "[INFO] Downloading packages..."
while read -r pkg; do
  echo "  -> $pkg"
  apt-get download "$pkg" || echo "[WARN] Failed to download $pkg, skipping."
done < dependencies.txt

# Step 6: Create local repository (dpkg-scanpackages)
cd pve
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd ..

# Step 7: Copy local repository and preseed into ISO
echo "[INFO] Copying local repo and preseed..."
cp preseed.cfg iso/
cp -r pve iso/

# Step 8: Modify bootloader to use preseed automatically
#   例如在 isolinux/txt.cfg 与 grub.cfg 中追加: file=/cdrom/preseed.cfg
echo "[INFO] Modifying bootloader config..."
sed -i "s+quiet+quiet priority=high locale=en_US.UTF-8 keymap=us file=/cdrom/preseed.cfg+g" \
  iso/isolinux/txt.cfg iso/boot/grub/grub.cfg

# Step 9: Build the custom ISO using xorriso
echo "[INFO] Building custom ISO with xorriso..."
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

# Step 10: Make it hybrid for BIOS/UEFI
echo "[INFO] Making ISO hybrid..."
isohybrid --uefi "$OUTPUT_ISO"

# Cleanup
echo "[INFO] Cleanup..."
rm -rf iso pve dependencies.txt

echo "[SUCCESS] Custom ISO created: $OUTPUT_ISO"

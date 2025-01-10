#!/bin/bash

set -e

DEBIAN_ISO="$1"
OUTPUT_ISO="$2"

if [[ -z "$DEBIAN_ISO" || -z "$OUTPUT_ISO" ]]; then
  echo "Usage: $0 <debian-iso> <output-iso>"
  exit 1
fi

echo "[INFO] Debian ISO: $DEBIAN_ISO"
echo "[INFO] Output ISO: $OUTPUT_ISO"

# Step 1: Prepare working directories
mkdir -p temp iso pve

# Step 2: Mount the Debian ISO to extract its contents
echo "[INFO] Mounting Debian ISO..."
mount -o loop "$DEBIAN_ISO" temp
cp -a temp/. iso
chmod -R 644 iso
umount temp

# Step 3: Download Proxmox VE packages
echo "[INFO] Adding Proxmox repo & downloading packages..."
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
  > /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

apt-get update

# Step 4: Gather Proxmox dependencies with apt-rdepends
echo "[INFO] Gathering Proxmox dependencies with apt-rdepends..."
apt-rdepends proxmox-ve | grep -v "^ " | sort -u > dependencies.txt

# Step 5: Download all packages to pve/ folder
while read -r pkg; do
  echo "[INFO] Downloading $pkg ..."
  apt-get download "$pkg" || echo "[WARN] Failed to download $pkg, skip."
done < dependencies.txt

# Generate Packages index
echo "[INFO] Generating local Packages index..."
cd pve || exit 1
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd ..

# Step 6: Copy local repository & preseed file into ISO
echo "[INFO] Copying pve repo & preseed..."
cp preseed.cfg iso/
cp -r pve iso/

# Step 7: Modify bootloader for automated install
echo "[INFO] Patching bootloader for automated install..."
sed -i "s+quiet+quiet priority=high locale=en_US.UTF-8 keymap=us file=/cdrom/preseed.cfg+g" \
  iso/isolinux/txt.cfg iso/boot/grub/grub.cfg

# Step 8: Build the custom ISO with xorriso
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

# Step 9: Make it hybrid (BIOS & UEFI)
echo "[INFO] Converting to hybrid ISO..."
isohybrid --uefi "$OUTPUT_ISO"

# Cleanup
echo "[INFO] Cleanup working directories..."
rm -rf temp iso pve dependencies.txt

echo "[INFO] Custom ISO created successfully: $OUTPUT_ISO"

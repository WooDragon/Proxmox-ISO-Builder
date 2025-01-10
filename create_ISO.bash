#!/bin/bash

set -e

# Parameters
DEBIAN_ISO="$1"
OUTPUT_ISO="$2"

if [[ -z "$DEBIAN_ISO" || -z "$OUTPUT_ISO" ]]; then
  echo "Usage: $0 <debian-iso> <output-iso>"
  exit 1
fi

# Step 1: Prepare environment
echo "Preparing directories..."
mkdir -p temp iso pve

# Step 2: Mount and extract the Debian ISO
echo "Extracting Debian ISO..."
sudo mount -o loop "$DEBIAN_ISO" temp
cp -a temp/. iso
sudo chmod -R 644 iso
sudo umount temp

# Step 3: Download Proxmox VE packages
echo "Downloading Proxmox VE packages..."
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" | sudo tee /etc/apt/sources.list.d/pve-install-repo.list
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg | sudo tee /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg > /dev/null
sudo apt-get update

# Use apt-get to download all dependencies
mkdir -p ./pve
sudo apt-get install --download-only --reinstall -y proxmox-ve postfix open-iscsi -o Dir::Cache="./pve"

# Move all downloaded .deb files to pve directory
mv ./pve/archives/*.deb ./pve/
rm -rf ./pve/archives

# Step 4: Generate Packages and Packages.gz for local repository
echo "Generating local repository metadata..."
cd pve
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd ..

# Step 5: Add local repository and preseed configuration to ISO
echo "Adding repository and preseed to ISO..."
cp preseed.cfg ./iso
cp -r pve ./iso

# Step 6: Modify bootloader for automated installation
echo "Modifying bootloader configuration..."
sed -i "s+quiet+quiet priority=high locale=en_US.UTF-8 keymap=us file=/cdrom/preseed.cfg+g" iso/isolinux/txt.cfg iso/boot/grub/grub.cfg

# Step 7: Build the custom ISO
echo "Building the custom ISO..."
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

# Step 8: Make the ISO hybrid for BIOS and UEFI
echo "Making ISO hybrid..."
isohybrid --uefi "$OUTPUT_ISO"

# Cleanup
echo "Cleaning up temporary files..."
rm -rf temp iso pve

echo "Custom ISO created: $OUTPUT_ISO"

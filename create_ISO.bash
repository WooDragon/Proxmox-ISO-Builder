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

# Step 3: Add Proxmox repo and download packages
echo "[INFO] Adding Proxmox repo and downloading packages..."
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
  > /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

apt-get update

# Step 4: Gather Proxmox dependencies with apt-rdepends
echo "[INFO] Gathering Proxmox dependencies with apt-rdepends..."
apt-rdepends proxmox-ve | grep -v "^ " | sort -u > dependencies.txt

echo "[INFO] Downloading packages to ./pve ..."
while read -r pkg; do
  echo "[INFO] Downloading $pkg ..."
  apt-get download "$pkg" -o=dir::cache="./pve/" || echo "[WARN] Failed to download $pkg, skipping."
done < dependencies.txt

# Ensure .deb files are downloaded
if [ "$(ls -A ./pve/*.deb 2>/dev/null)" ]; then
  echo "[INFO] .deb files found in ./pve/"
else
  echo "[ERROR] No .deb files found in ./pve/! Check the download step."
  exit 1
fi

# Step 5: Generate Packages and Packages.gz for local repository
echo "[INFO] Generating local repository metadata..."
cd pve || exit 1
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd ..

# Step 6: Copy local repository & preseed file into ISO
echo "[INFO] Copying pve repo & preseed to ISO..."
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
echo "[INFO] Cleaning up temporary files..."
rm -rf temp iso dependencies.txt
# Note: Do not delete pve/ directory

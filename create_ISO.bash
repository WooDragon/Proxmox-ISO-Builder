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

# Step 1: Mount and extract the ISO
mount -o loop "$DEBIAN_ISO" "$WORKDIR/temp"
cp -a "$WORKDIR/temp/." "$WORKDIR/iso"
umount "$WORKDIR/temp"

# Step 2: Add Proxmox repo and download packages
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
  > /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

apt-get update
apt-get install --download-only -y proxmox-ve postfix open-iscsi chrony
cp /var/cache/apt/archives/*.deb "$WORKDIR/pve/"
cd "$WORKDIR/pve"
dpkg-scanpackages . > Packages
gzip -9c Packages > Packages.gz
cd -

# Step 3: Copy local repo and preseed to ISO
cp preseed.cfg "$WORKDIR/iso/"
cp -r "$WORKDIR/pve" "$WORKDIR/iso/"

# Step 4: Modify bootloader
# BIOS: isolinux/txt.cfg
sed -i '/timeout/s/.*/timeout 100/' "$WORKDIR/iso/isolinux/isolinux.cfg"
sed -i '/default/s/.*/default auto/' "$WORKDIR/iso/isolinux/txt.cfg"
cat <<EOF >> "$WORKDIR/iso/isolinux/txt.cfg"

label auto
  menu label ^Automated Installation
  kernel /install.amd/vmlinuz
  append initrd=/install.amd/initrd.gz auto=true priority=medium locale=en_US.UTF-8 keymap=us file=/cdrom/preseed.cfg --
EOF

# UEFI: grub.cfg
sed -i '/set timeout=/s/.*/set timeout=10/' "$WORKDIR/iso/boot/grub/grub.cfg"
cat <<EOF >> "$WORKDIR/iso/boot/grub/grub.cfg"

menuentry "Automated Installation" {
    set gfxpayload=keep
    linux /install.amd/vmlinuz auto=true priority=medium locale=en_US.UTF-8 keymap=us file=/cdrom/preseed.cfg --
    initrd /install.amd/initrd.gz
}
EOF

# Step 5: Build custom ISO
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

#!/bin/bash

# 1) 准备工作目录
mkdir -p temp
mount debian-*.iso temp
cp -a temp/. iso
chmod -R 644 iso
umount temp

# 2) 把预置文件和离线仓库复制到 iso 根目录
cp preseed.cfg ./iso

# 假设 GitHub Actions 的"pve"目录和脚本在同级目录下
cp -r pve iso/

# 3) 修改 isolinux/grub 的启动选项，让安装器加载 preseed.cfg
sed -i "s+quiet+quiet priority=high locale=en_US.UTF-8 keymap=de file=/cdrom/preseed.cfg+g" \
  iso/isolinux/txt.cfg iso/boot/grub/grub.cfg

# 4) 生成自定义 ISO
OUTPUT="proxmox_custom.iso"
xorriso \
   -outdev "$OUTPUT" \
   -volid "Proxmox_Custom" \
   -padding 0 \
   -compliance no_emul_toc \
   -map "./iso" / \
   -chmod 0755 / -- \
   -boot_image isolinux dir=/isolinux \
   -boot_image any next \
   -boot_image any efi_path=boot/grub/efi.img \
   -boot_image isolinux partition_entry=gpt_basdat \
   -stdio_sync off

isohybrid --uefi "$OUTPUT"

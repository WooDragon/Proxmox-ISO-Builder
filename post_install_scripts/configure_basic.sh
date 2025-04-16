#!/bin/bash
# 配置 /etc/fstab
sed -i 's/\(.*\) \{1,\}[0-9]\+$/\10/' /etc/fstab
# 创建 systemd override 文件以设置 TimeoutStartSec
#mkdir -p /etc/systemd/system/networking.service.d
#echo -e '[Service]\nTimeoutStartSec=90s' > /etc/systemd/system/networking.service.d/override.conf
# 配置 APT 源列表
echo 'deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware' > /etc/apt/sources.list
echo 'deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware' >> /etc/apt/sources.list
echo 'deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware' >> /etc/apt/sources.list
echo 'deb https://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware' >> /etc/apt/sources.list
# 移除 Proxmox Enterprise 源列表文件
rm -f /etc/apt/sources.list.d/pve-enterprise.list || true
# 添加 Proxmox no-subscription 源
echo 'deb http://mirrors.ustc.edu.cn/proxmox/debian/pve bookworm pve-no-subscription' > /etc/apt/sources.list.d/pve-install-repo.list
# 修改 CT 源
cp /usr/share/perl5/PVE/APLInfo.pm /usr/share/perl5/PVE/APLInfo.pm_back
sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' /usr/share/perl5/PVE/APLInfo.pm
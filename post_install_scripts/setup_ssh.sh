#!/bin/bash
systemctl enable ssh
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
mkdir -p /root/.ssh
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBwECtUHN6VDe8QFmlgNm4meZ32VP9JiIEH0+wo3eh+Gs2dibZGJKzPBsQM3XphfailDgYiZbTHfKzNCpAk+SnvcwIPXy8wZ1AwWjN9Jf6qULeI8VI84Ik0cDa9byI5S99894gAh9Um7Jo34ns2REdCLrdABa37E/ZgiJJVtWblxHSlMAfr9vbmFjTETe1rD7L3FbytBLbExo3wylb2+eLwPRtaDdShFDLJJFd5PRTIVYKACXfaywdODAX0WCa09yIm29b0lGuaAukPk0rzSpyN5dG/muevQ3LpNt/r5jPkEwcPerHHSoDRgxvhLe8QO01izhbUugWJ3LFvr15M9Qd w@w' >> /root/.ssh/authorized_keys
systemctl restart ssh

#!/bin/bash
mkdir -p /etc/chrony/sources.d

cat <<'EOF' > /etc/chrony/sources.d/custom.conf
# Custom NTP servers
server time1.aliyun.com minpoll 4 maxpoll 10 iburst
server time2.aliyun.com minpoll 4 maxpoll 10 iburst
server time3.aliyun.com minpoll 4 maxpoll 10 iburst
server time4.aliyun.com minpoll 4 maxpoll 10 iburst
server time5.aliyun.com minpoll 4 maxpoll 10 iburst
server time6.aliyun.com minpoll 4 maxpoll 10 iburst
server time7.aliyun.com minpoll 4 maxpoll 10 iburst
server time1.apple.com minpoll 4 maxpoll 10 iburst
server time2.apple.com minpoll 4 maxpoll 10 iburst
server time3.apple.com minpoll 4 maxpoll 10 iburst
server time4.apple.com minpoll 4 maxpoll 10 iburst
server time5.apple.com minpoll 4 maxpoll 10 iburst
server time6.apple.com minpoll 4 maxpoll 10 iburst
server time7.apple.com minpoll 4 maxpoll 10 iburst
server cn.ntp.org.cn minpoll 4 maxpoll 10 iburst
server time1.google.com minpoll 4 maxpoll 10 iburst
server time2.google.com minpoll 4 maxpoll 10 iburst
server time3.google.com minpoll 4 maxpoll 10 iburst
server time4.google.com minpoll 4 maxpoll 10 iburst
EOF


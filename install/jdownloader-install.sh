#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://jdownloader.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

JAVA_VERSION="21" setup_java

msg_info "Downloading JDownloader"
mkdir -p /opt/jdownloader
$STD wget -O /opt/jdownloader/JDownloader.jar https://installer.jdownloader.org/JDownloader.jar
msg_ok "Downloaded JDownloader"

msg_info "Installing JDownloader (Patience)"
cd /opt/jdownloader
$STD java -Djava.awt.headless=true -jar /opt/jdownloader/JDownloader.jar -norestart
msg_ok "Installed JDownloader"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/jdownloader.service
[Unit]
Description=JDownloader Download Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/jdownloader
ExecStart=/usr/bin/java -Djava.awt.headless=true -jar /opt/jdownloader/JDownloader.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now jdownloader
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: JasonGreenC
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/thecfu/scraparr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  python3 \
  python3-pip

msg_ok "Installed Dependencies"

msg_info "Installing Scraparr"
fetch_and_deploy_gh_release "scrappar" "thecfu/scraparr"
pip -q install -r /opt/scraparr/src/scraparr/requirements.txt --root-user-action=ignore
chmod -R 755 /opt/scraparr
mkdir /scraparr && mkdir /scraparr/config
mv /opt/scraparr/config.yaml /scraparr/config/config.yaml
chmod -R 755 /scraparr
msg_ok "Installed Scraparr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/scraparr.service
[Unit]
Description=Scraparr
Wants=network-online.target
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m scraparr.scraparr
WorkingDirectory=/opt/scraparr/src
User=root
Restart=always

[Install]
WantedBy=multi-user.target

EOF

systemctl daemon-reload
systemctl enable -q --now scraparr

msg_ok "Configured Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f "$temp_file"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

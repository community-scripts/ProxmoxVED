#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/naiba/bonds | Github: https://github.com/naiba/bonds

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y openssl
msg_ok "Installed Dependencies"

msg_info "Downloading and Deploying Bonds"
fetch_and_deploy_gh_release "bonds" "naiba/bonds" "singlefile" "latest" "/opt/bonds" "bonds-server"
chmod +x /opt/bonds/bonds-server
msg_ok "Downloaded and Deployed Bonds"

msg_info "Creating Service"
JWT_SECRET=$(openssl rand -hex 32)

cat <<EOF >/etc/systemd/system/bonds.service
[Unit]
Description=Bonds Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bonds
Environment="JWT_SECRET=${JWT_SECRET}"
ExecStart=/opt/bonds/bonds-server
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now bonds
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/streetwriters/notesnook

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  make \
  git \
  caddy
msg_ok "Installed Dependencies"

LOCAL_IP=$(hostname -I | awk '{print $1}')
NODE_MODULE="yarn" setup_nodejs
fetch_and_deploy_gh_release "notesnook" "streetwriters/notesnook" "tarball"

msg_info "Configuring Notesnook (Patience)"
cd /opt/notesnook
export NODE_OPTIONS="--max-old-space-size=2560"
mkdir -p certs
$STD npm install
$STD npm run build:web
msg_ok "Configured Notesnook"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/notesnook.service
[Unit]
Description=Notesnook Service
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/notesnook
ExecStart=/usr/bin/npx serve -l tcp://0.0.0.0:3000 apps/web/build
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/caddy reverse-proxy --from https://$LOCAL_IP --to localhost:3000|" /lib/systemd/system/caddy.service
sed -i "/^ExecReload=/d" /lib/systemd/system/caddy.service
systemctl daemon-reload
systemctl restart caddy
systemctl enable -q --now notesnook
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

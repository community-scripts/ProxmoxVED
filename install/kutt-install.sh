#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: tomfrenzel
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/thedevs-network/kutt

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

read -r -p "${TAB3}Enter the hostname of your Kutt instance (eg kutt.domain.tld): " kutt_host
if [[ "$kutt_host" ]]; then
  KUTT_HOST="$kutt_host"
fi

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "kutt" "thedevs-network/kutt" "tarball"

msg_info "Configuring Kutt"
cd /opt/kutt
cp .example.env ".env"
sed -i "s|DEFAULT_DOMAIN=localhost:3000|DEFAULT_DOMAIN=${KUTT_HOST}|g" ".env"
sed -i "s|JWT_SECRET=|JWT_SECRET=$(openssl rand -base64 32)|g" ".env"
npm install
npm run migrate

cat <<EOF >/etc/systemd/system/kutt.service
[Unit]
Description=Kutt server
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/kutt
ExecStart=/usr/bin/node server/server.js  --production
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now kutt
msg_ok "Configured Kutt"

motd_ssh
customize
cleanup_lxc

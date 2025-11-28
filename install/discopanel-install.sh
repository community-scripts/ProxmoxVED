#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: DragoQC
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://discopanel.app/

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  npm \
  golang
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -fsSL https://get.docker.com)
msg_ok "Installed Docker"


msg_info "Installing DiscoPanel"
fetch_and_deploy_gh_release "discopanel" "nickheyer/discopanel" "tarball" "latest" "/opt/discopanel"
msg_ok "Installed DiscoPanel"

msg_info "Building DiscoPanel frontend"
cd /opt/discopanel/web/discopanel
npm install
npm run build
msg_ok "Built DiscoPanel frontend"

msg_info "Building DiscoPanel backend"
cd /opt/discopanel
go build -o discopanel cmd/discopanel/main.go
msg_ok "Built DiscoPanel backend"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/discopanel.service
[Unit]
Description=DiscoPanel Service
After=network.target

[Service]
WorkingDirectory=/opt/discopanel
ExecStart=/opt/discopanel/discopanel
Restart=always
User=root
Environment=PORT=8080

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now "discopanel"
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

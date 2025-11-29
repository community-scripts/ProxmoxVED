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
$STD apt install -y build-essential gcc
msg_ok "Installed Dependencies"


msg_info "Installing Docker"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -fsSL https://get.docker.com)
msg_ok "Installed Docker"

fetch_and_deploy_gh_release "discopanel" "nickheyer/discopanel" "tarball" "latest" "/opt/discopanel"

setup_nodejs
setup_go

msg_info "Building DiscoPanel frontend"
cd /opt/discopanel/web/discopanel
$STD npm install
$STD npm run build
msg_ok "Built DiscoPanel frontend"

msg_info "Building DiscoPanel backend"
cd /opt/discopanel
$STD go build -o discopanel cmd/discopanel/main.go
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


[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now "discopanel"
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/yusing/godoxy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "godoxy" "yusing/godoxy" "singlefile" "latest" "/usr/local/bin" "godoxy-agent-linux-amd64"

msg_info "Configuring GoDoxy Agent"
mkdir -p /var/lib/godoxy-agent
cat <<EOF >/etc/godoxy-agent.env
AGENT_NAME=$(hostname)
AGENT_PORT=8890
AGENT_CA_CERT=
AGENT_SSL_CERT=
DOCKER_SOCKET=/var/run/docker.sock
RUNTIME=docker
EOF
chmod 600 /etc/godoxy-agent.env
msg_ok "Configured GoDoxy Agent"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/godoxy-agent.service
[Unit]
Description=GoDoxy Agent
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/godoxy
EnvironmentFile=/etc/godoxy-agent.env
WorkingDirectory=/var/lib/godoxy-agent
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now godoxy-agent
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

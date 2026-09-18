#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nicolas Pastorello (opastorello)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://victoriametrics.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "victoriametrics" "VictoriaMetrics/VictoriaMetrics" "prebuild" "latest" "/opt/victoriametrics" "victoria-metrics-linux-$(arch_resolve amd64 arm64)-v*[0-9].tar.gz"

msg_info "Setting up Data Directory"
mkdir -p /opt/victoriametrics_data
msg_ok "Set up Data Directory"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/victoriametrics.service
[Unit]
Description=VictoriaMetrics Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/victoriametrics
ExecStart=/opt/victoriametrics/victoria-metrics-prod -storageDataPath=/opt/victoriametrics_data -httpListenAddr=:8428
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now victoriametrics
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

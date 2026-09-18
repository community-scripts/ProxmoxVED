#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nicolas Pastorello (opastorello)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://victoriametrics.com/products/victoriatraces/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "victoriatraces" "VictoriaMetrics/VictoriaTraces" "prebuild" "latest" "/opt/victoriatraces" "victoria-traces-linux-$(arch_resolve amd64 arm64)-v*[0-9].tar.gz"

msg_info "Setting up Data Directory"
mkdir -p /opt/victoriatraces_data
msg_ok "Set up Data Directory"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/victoriatraces.service
[Unit]
Description=VictoriaTraces Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/victoriatraces
ExecStart=/opt/victoriatraces/victoria-traces-prod -storageDataPath=/opt/victoriatraces_data -httpListenAddr=:10428
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now victoriatraces
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

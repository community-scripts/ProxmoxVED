#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/lovelaze/nebula-sync

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "nebula-sync" "lovelaze/nebula-sync" "prebuild" "latest" "/opt/nebula-sync" "nebula-sync_*_linux_$(arch_resolve).tar.gz"
chmod +x /opt/nebula-sync/nebula-sync

msg_info "Configuring nebula-sync"
cat <<EOF >/opt/nebula-sync.env
PRIMARY=http://pihole1.example.com|CHANGE_ME
REPLICAS=http://pihole2.example.com|CHANGE_ME
FULL_SYNC=true
RUN_GRAVITY=true
CRON=0 * * * *
EOF
chmod 600 /opt/nebula-sync.env
msg_ok "Configured nebula-sync"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/nebula-sync.service
[Unit]
Description=nebula-sync Pi-hole Configuration Sync
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/nebula-sync
EnvironmentFile=/opt/nebula-sync.env
ExecStart=/opt/nebula-sync/nebula-sync run
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nebula-sync
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Sportarr/Sportarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "sportarr" "Sportarr/Sportarr" "prebuild" "latest" "/opt/sportarr" "Sportarr-linux-x64-*.tar.gz"

msg_info "Setting up Sportarr"
cat <<EOF >/opt/sportarr/.env
Sportarr__DataPath="/opt/sportarr/config"
ASPNETCORE_URLS="http://*:1867"
ASPNETCORE_ENVIRONMENT="Production"
DOTNET_CLI_TELEMETRY_OPTOUT=1
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
EOF
msg_ok "Setup Sportarr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/sportarr.service
[Unit]
Description=Sportarr Service
After=network.target

[Service]
EnvironmentFile=/opt/sportarr/.env
WorkingDirectory=/opt/sportarr
ExecStart=/opt/sportarr/Sportarr
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now sportarr
msg_info "Created Service"

motd_ssh
customize
cleanup_lxc

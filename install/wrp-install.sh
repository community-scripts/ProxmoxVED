#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: N0t4R0b0t
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/tenox7/wrp

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y chromium fonts-liberation
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "wrp" "tenox7/wrp" "singlefile" "latest" "/opt/wrp" "$(arch_resolve "wrp-amd64-linux" "wrp-arm64-linux")"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/wrp.service
[Unit]
Description=WRP - Web Rendering Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/wrp/wrp -l :8080 -b $(command -v chromium || command -v chromium-browser)
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now wrp
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

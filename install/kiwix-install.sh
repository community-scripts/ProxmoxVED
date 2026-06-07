#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tewalds
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y software-properties-common
msg_ok "Installed Dependencies"

msg_info "Adding Kiwix PPA"
add-apt-repository -y ppa:kiwixteam/release >>"$(get_active_logfile)" 2>&1
$STD apt update
msg_ok "Added Kiwix PPA"

msg_info "Installing Kiwix-Tools"
$STD apt install -y kiwix-tools
RELEASE=$(dpkg -s kiwix-tools 2>/dev/null | awk '/^Version:/{print $2}')
echo "${RELEASE}" >/root/.kiwix
msg_ok "Installed Kiwix-Tools ${RELEASE}"

mkdir -p /data

msg_info "Creating Service"
cat <<'EOF' >/etc/systemd/system/kiwix-serve.service
[Unit]
Description=Kiwix ZIM Server
After=network.target

[Service]
Type=simple
ExecStart=/bin/sh -c 'exec /usr/bin/kiwix-serve --port 8080 /data/*.zim'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q kiwix-serve
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

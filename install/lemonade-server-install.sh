#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jamie (jamiej)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/lemonade-sdk/lemonade

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Enabling Debian Backports"
cat <<'EOF' >/etc/apt/sources.list.d/backports.list
deb http://deb.debian.org/debian trixie-backports main
EOF
$STD apt update
msg_ok "Enabled Debian Backports"

msg_info "Installing Lemonade Server dependencies"
$STD apt install -y \
  fonts-katex \
  libcpp-httplib0.41 \
  libmbedcrypto16 \
  libwebsockets19t64
msg_ok "Installed Lemonade Server dependencies"

setup_hwaccel

fetch_and_deploy_gh_release "lemonade-server" "lemonade-sdk/lemonade" "binary" "latest" "/tmp" "lemonade-server_*-debian13_amd64.deb"

msg_info "Configuring Remote Access"
systemctl enable -q --now lemond
sleep 3
$STD lemonade config set host=0.0.0.0
msg_ok "Configured Remote Access"

motd_ssh
customize
cleanup_lxc

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

setup_deb822_repo \
  "backports" \
  "https://ftp-master.debian.org/keys/archive-key-13.asc" \
  "http://deb.debian.org/debian" \
  "trixie-backports" \
  "main"

msg_info "Installing Lemonade Server dependencies"
$STD apt install -y \
  fonts-katex \
  libcpp-httplib0.41 \
  libmbedcrypto16 \
  libwebsockets19t64
msg_ok "Installed Lemonade Server dependencies"

setup_hwaccel

fetch_and_deploy_gh_release "lemonade-server" "lemonade-sdk/lemonade" "binary" "latest" "/tmp" "lemonade-server_*-debian13_$(arch_resolve).deb"

msg_info "Configuring Remote Access"
systemctl enable -q --now lemond
sleep 3
$STD lemonade config set host=0.0.0.0
msg_ok "Configured Remote Access"

motd_ssh
customize
cleanup_lxc

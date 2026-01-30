#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/john30/ebusd

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb822_repo \
  "ebusd" \
  "https://raw.githubusercontent.com/john30/ebusd-debian/master/ebusd.gpg" \
  "https://repo.ebusd.eu/apt/default/bookworm/" \
  "bookworm" \
  "main"

msg_info "Installing ebusd"
$STD apt install -y ebusd
systemctl enable -q --now ebusd
msg_ok "Installed ebusd"

motd_ssh
customize
cleanup_lxc

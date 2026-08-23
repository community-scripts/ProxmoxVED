#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nick Berardi (nberardi)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://nextdns.io | https://github.com/nextdns/nextdns

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb822_repo \
  "nextdns" \
  "https://repo.nextdns.io/nextdns.gpg" \
  "https://repo.nextdns.io/deb" \
  "stable" \
  "main"

msg_info "Installing NextDNS"
$STD apt install -y nextdns
msg_ok "Installed NextDNS"

motd_ssh
customize
cleanup_lxc

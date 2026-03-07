#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://lemonade-server.ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
APP="Lemonade"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "lemonade" "lemonade-sdk/lemonade" "binary"

msg_info "Enabling Service"
systemctl enable -q --now lemonade-server
msg_ok "Enabled Service"

motd_ssh
customize
cleanup_lxc
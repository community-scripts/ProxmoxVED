#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/clawdbot/clawdbot

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  git
msg_ok "Installed Dependencies"


NODE_VERSION="24" NODE_MODULE="pnpm@latest" setup_nodejs

curl -fsSL https://clawd.bot/install.sh | bash


motd_ssh
customize
cleanup_lxc


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
$STD apt-get install -y \
  build-essential \
  git
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "clawdbot" "clawdbot/clawdbot"

pnpm_version=$(grep -oP '"packageManager":\s*"pnpm@\K[^"]+' /opt/clawdbot/package.json 2>/dev/null || echo "latest")
NODE_VERSION="24" NODE_MODULE="pnpm@${pnpm_version}" setup_nodejs

msg_info "Installing Clawdbot Dependencies"
cd /opt/clawdbot
$STD pnpm install --frozen-lockfile
msg_ok "Installed Dependencies"

msg_info "Building Clawdbot UI"
$STD pnpm ui:build
msg_ok "Built Clawdbot UI"

motd_ssh
customize
cleanup_lxc


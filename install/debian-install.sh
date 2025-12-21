#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE
# Source:

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_hwaccel

msg_info "Installing Base Dependencies"
$STD apt-get install -y curl wget ca-certificates
msg_ok "Installed Base Dependencies"

# msg_info "Downloading and executing tools.func test suite"
# bash <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/test-tools-func.sh)
# msg_ok "Test suite completed"

motd_ssh
customize
cleanup_lxc

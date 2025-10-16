#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Test Suite for tools.func
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Purpose: Run comprehensive test suite for all setup_* functions from tools.func

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Base Dependencies"
$STD apt-get install -y curl wget ca-certificates
msg_ok "Installed Base Dependencies"

msg_info "Downloading and executing tools.func test suite"
bash <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/test-tools-func.sh)
msg_ok "Test suite completed"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
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
$STD apt install -y curl wget ca-certificates
msg_ok "Installed Base Dependencies"

RUST_PROFILE="minimal" RUST_TOOLCHAIN="stable" setup_rust

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
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


msg_info "Installing Dependencies"
$STD apt-get install -y \
    build-essential \
    make \
    git
msg_ok "Installed Dependencies"

## WIP - only protoype with git call

install_go

msg_info "Setup ocis"
cd /opt
git clone https://github.com/owncloud/ocis
cd /opt/ocis
make generate
make -C ocis build
./ocis/bin/ocis init
IDM_CREATE_DEMO_USERS=true ./ocis/bin/ocis server
msg_ok "Setup ocis"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

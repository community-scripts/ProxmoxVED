#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Don Locke (DonLocke)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/AllStarLink

APP="AllStarLink"

header_info

if [[ ! -d /etc/asterisk ]]; then
msg_error "No ${APP} Installation Found!"
exit
fi
msg_info "Updating $APP VM"
$STD apt-get update
$STD DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
msg_ok "Updated $APP VM"
exit

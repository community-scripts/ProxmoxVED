#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: michelroegl-brunner
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os
install_core_deps

msg_info "Installing Dependencies"
$STD apt-get install -y \
    sudo \
    mc \
    curl \
    apt-transport-https \
    ca-certificates \
    gpg
msg_ok "Installed Dependencies"

msg_info "Adding Repository"
wget -qO- https://dl.packager.io/srv/opf/openproject/key | gpg --dearmor >/etc/apt/trusted.gpg.d/packager-io.gpg
wget -O /etc/apt/sources.list.d/openproject.list https://dl.packager.io/srv/opf/openproject/stable/15/installer/debian/12.repo
msg_ok "Added Repository"

msg_info "Installing OpenProject"
$STD apt-get update
$STD apt-get install -y openproject
msg_ok "Installed OpenProject"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz) | Co-Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://vikunja.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
# $STD apt install -y make
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "vikunja" "go-vikunja/vikunja" "binary" "latest" 

msg_info "Setup Vikunja"
sed -i 's|^  timezone: .*|  timezone: UTC|' /etc/vikunja/config.yml
sed -i 's|"./vikunja.db"|"/etc/vikunja/vikunja.db"|' /etc/vikunja/config.yml
sed -i 's|./files|/etc/vikunja/files|' /etc/vikunja/config.yml
systemctl enable -q --now vikunja
msg_ok "Setting up Vikunja"

motd_ssh
customize
cleanup_lxc

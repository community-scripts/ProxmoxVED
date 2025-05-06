#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add newt
$STD apk add curl
$STD apk add openssh
$STD apk add nano
$STD apk add mc
msg_ok "Installed Dependencies"

msg_info "Enabling edge repository for traefik"
echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/community" >>/etc/apk/repositories
$STD apk update
msg_ok "Enabled edge repository"

msg_info "Installing Traefik"
$STD apk add traefik@edge
msg_ok "Installed Traefik"

sed -i '/@edge/d' /etc/apk/repositories
$STD apk update

motd_ssh
customize

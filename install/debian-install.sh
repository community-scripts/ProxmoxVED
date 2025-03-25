#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y lsb-release
msg_ok "Installed Dependencies"

msg_info "Setup DISTRO env"
DISTRO="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"
echo $DISTRO
msg_ok "Setup DISTRO"

msg_info "Setting up PostgreSQL Repository"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb https://apt.postgresql.org/pub/repos/apt ${DISTRO}-pgdg main" >/etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql
msg_ok "Set up PostgreSQL Repository"

msg_info "Setting up Matrix Server"
curl -fsSL https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg -o /usr/share/keyrings/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian ${VERSION} main" >/etc/apt/sources.list.d/matrix-org.list
apt-get update
apt-get install -y matrix-synapse-py3
msg_info "Set up Matrix Server"

msg_info "Setup EVCC"
curl -fsSL https://dl.evcc.io/public/evcc/stable/gpg.EAD5D0E07B0EC0FD.key | gpg --dearmor -o /etc/apt/keyrings/evcc-stable.gpg
echo "deb [signed-by=/etc/apt/keyrings/evcc-stable.gpg] https://dl.evcc.io/public/evcc/stable/deb/debian ${VERSION} main" >/etc/apt/sources.list.d/evcc-stable.list
apt-get update
apt-get install -y evcc
msg_ok "Setup EVCC"

msg_info "Setup PHP"
curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/deb.sury.org-php.gpg
echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${VERSION} main" >/etc/apt/sources.list.d/php.list
apt-get update
apt-get install -y php
msg_ok "Setup PHP"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

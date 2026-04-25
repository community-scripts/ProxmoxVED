#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot (GPT-5.3-Codex)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/NagiosEnterprises/nagioscore

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  apache2-utils \
  nagios4 \
  nagios-plugins-contrib
msg_ok "Installed Dependencies"

msg_info "Configuring Web Authentication"
htpasswd -bc /etc/nagios4/htpasswd.users nagiosadmin nagiosadmin
chown root:www-data /etc/nagios4/htpasswd.users
chmod 640 /etc/nagios4/htpasswd.users
msg_ok "Configured Web Authentication"

msg_info "Starting Services"
systemctl enable -q --now nagios4
systemctl enable -q --now apache2
msg_ok "Started Services"

motd_ssh
customize
cleanup_lxc

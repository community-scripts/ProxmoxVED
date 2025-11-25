#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://valkey.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  apt-transport-https \
  lsb-release
msg_ok "Installed Dependencies"

DEB_VER="$(cat /etc/debian_version)"

if [[ "$DEB_VER" =~ ^([0-9]+) ]]; then
  MAJOR="${BASH_REMATCH[1]}"
  if (( MAJOR < 13 )); then
    msg_error "Unsupported Debian version."
    exit 1
  fi
else
  msg_error "Unable to determine Debian version."
  exit 1
fi

msg_info "Installing Valkey"
$STD apt update
$STD apt install -y valkey
sed -i 's/^bind .*/bind 0.0.0.0/' /etc/valkey/valkey.conf
systemctl enable -q --now valkey-server
msg_ok "Installed Valkey"

motd_ssh
customize
cleanup_lxc

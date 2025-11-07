#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.tp-link.com/us/support/download/omada-software-controller/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y jsvc
msg_ok "Installed Dependencies"

if lscpu | grep -q 'avx'; then
  MONGO_VERSION="8.0" setup_mongodb
else
  MONGO_VERSION="4.4" setup_mongodb
fi

JAVA_VERSION="21" setup_java

# if ! dpkg -l | grep -q 'libssl1.1'; then
#   msg_info "Installing libssl (if needed)"
#   curl -fsSL "https://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.1_1.1.1w-0+deb11u4_amd64.deb" -o "/tmp/libssl.deb"
#   $STD dpkg -i /tmp/libssl.deb
#   rm -f /tmp/libssl.deb
#   msg_ok "Installed libssl1.1"
# fi

msg_info "Installing Omada Controller"
OMADA_URL=$(curl -fsSL "https://support.omadanetworks.com/en/download/software/omada-controller/" |
  grep -o 'https://static\.tp-link\.com/upload/software/[^"]*linux_x64[^"]*\.deb' |
  head -n1)
OMADA_PKG=$(basename "$OMADA_URL")
curl -fsSL "$OMADA_URL" -o "$OMADA_PKG"
$STD dpkg -i "$OMADA_PKG"
msg_ok "Installed Omada Controller"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf "$OMADA_PKG"
$STD apt -y autoremove
$STD apt -y autoclean
$STD apt -y clean
msg_ok "Cleaned"

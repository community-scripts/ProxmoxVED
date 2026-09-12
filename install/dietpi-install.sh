#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: mews-se
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://dietpi.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

motd_ssh

msg_info "Converting Debian to DietPi"
curl -fsSL https://raw.githubusercontent.com/MichaIng/DietPi/master/.build/images/dietpi-installer -o /tmp/dietpi-installer
$STD env GITBRANCH=master HW_MODEL=75 DISTRO_TARGET=8 GUEST_NETWORK_REQUIRED=1 WIFI_REQUIRED=0 IMAGE_CREATOR=community-scripts PREIMAGE_INFO='Proxmox Debian LXC template' bash /tmp/dietpi-installer
rm -f /tmp/dietpi-installer
msg_ok "Converted Debian to DietPi"

msg_info "Configuring DietPi"
sed -i -e 's/^AUTO_SETUP_NET_ETHERNET_ENABLED=.*/AUTO_SETUP_NET_ETHERNET_ENABLED=0/' \
  -e "s/^AUTO_SETUP_NET_HOSTNAME=.*/AUTO_SETUP_NET_HOSTNAME=$(hostname)/" /boot/dietpi.txt
rm -f /etc/apt/sources.list.d/debian.sources
msg_ok "Configured DietPi"

customize
cleanup_lxc

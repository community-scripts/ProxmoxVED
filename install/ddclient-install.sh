#!/usr/bin/env bash

# Copyright (c) 2026 mitchscobell
# Author: mitchscobell
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://ddclient.net/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing ddclient"
DEBIAN_FRONTEND=noninteractive $STD apt -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y ddclient
msg_ok "Installed ddclient"

if [[ ! -f /etc/ddclient.conf ]]; then
  msg_info "Creating sample ddclient configuration"
  cat << 'EOF' >/etc/ddclient.conf
protocol=namecheap
use=web, web=dynamicdns.park-your-domain.com/getip
protocol=namecheap
use=web, web=dynamicdns.park-your-domain.com/getip
server=dynamicdns.park-your-domain.com
login=yourdomain.com
password='your-ddns-password'
@,www
EOF
  chmod 600 /etc/ddclient.conf
  msg_ok "Sample /etc/ddclient.conf created"
fi

msg_info "Enabling ddclient service"
systemctl enable -q --now ddclient
msg_ok "ddclient service enabled and started"

motd_ssh
echo -e "echo -e \"  🔧 \\\\033[1;33m Configuration: \\\\033[1;32m/etc/ddclient.conf\\\\033[0m\"" >>/etc/profile.d/00_lxc-details.sh
echo "echo \"\"" >>/etc/profile.d/00_lxc-details.sh
customize
cleanup_lxc

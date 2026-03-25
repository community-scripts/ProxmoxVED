#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://jitsi.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

source /etc/os-release
setup_deb822_repo "jitsi" "https://download.jitsi.org/jitsi-key.gpg.key" "https://download.jitsi.org" "stable/" ""

msg_info "Installing Jitsi Meet"
echo "jitsi-videobridge2 jitsi-videobridge/jvb-hostname string ${LOCAL_IP}" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive $STD apt install -y jitsi-meet
msg_ok "Installed Jitsi Meet"

msg_info "Configuring Network"
cat <<EOF >/etc/sysctl.d/99-jitsi.conf
net.core.rmem_max=10485760
net.core.netdev_max_backlog=100000
EOF
$STD sysctl -p /etc/sysctl.d/99-jitsi.conf
msg_ok "Configured Network"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/jitsi/jitsi-meet

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  apt-transport-https \
  lsb-release \
  debconf-utils
msg_ok "Installed Dependencies"

msg_info "Setting up repositories"
curl -fsSL https://prosody.im/files/prosody-debian-packages.key -o /etc/apt/keyrings/prosody-debian-packages.key
echo "deb [signed-by=/etc/apt/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main" >/etc/apt/sources.list.d/prosody-debian-packages.list
curl -fsSL https://download.jitsi.org/jitsi-key.gpg.key | gpg --dearmor -o /usr/share/keyrings/jitsi-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/" >/etc/apt/sources.list.d/jitsi-stable.list
$STD apt-get update
msg_ok "Done setting up repositories"

msg_info "Installing jitsi-meet"
IP=$(hostname -I | awk '{print $1}')
PASS="$(openssl rand -base64 18 | cut -c1-13)"
SECRET="$(openssl rand -base64 18 | cut -c1-13)"
JVBSECRET="$(openssl rand -base64 18 | cut -c1-13)"
echo "jicofo jicofo/jicofo-authpassword password $PASS" | debconf-set-selections
echo "jitsi-meet-prosody jicofo/jicofo-authpassword password $PASS" | debconf-set-selections
echo "jitsi-meet-prosody jitsi-meet-prosody/jvb-hostname string $IP" | debconf-set-selections
echo "jitsi-meet-prosody jitsi-meet-prosody/turn-secret string $SECRET" | debconf-set-selections
echo "jitsi-meet-turnserver jitsi-meet-turnserver/jvb-hostname string $IP" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/cert-path-crt string '/var/lib/prosody/auth.$IP.crt'" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/cert-path-key string '/var/lib/prosody/$IP.key'" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/email string ''" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/jaas-choice boolean false" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/jvb-hostname string $IP" | debconf-set-selections
echo "jicofo jitsi-videobridge/jvb-hostname string $IP" | debconf-set-selections
echo "jitsi-meet-prosody jitsi-videobridge/jvb-hostname string $IP" | debconf-set-selections
echo "jitsi-meet-turnserver jitsi-videobridge/jvb-hostname string $IP" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-videobridge/jvb-hostname string $IP" | debconf-set-selections
echo "jitsi-videobridge2 jitsi-videobridge/jvb-hostname string $IP" | debconf-set-selections
echo "jitsi-meet-prosody jitsi-videobridge/jvbsecret password $JVBSECRET" | debconf-set-selections
echo "jitsi-videobridge2 jitsi-videobridge/jvbsecret password $JVBSECRET" | debconf-set-selections
$STD apt-get install -y \
  lua5.2 \
  jitsi-meet
msg_ok "Installed jitsi-meet"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: SunFlowerOwl
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/haugene/docker-transmission-openvpn

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    dnsutils \
    iputils-ping \
    ufw \
    iproute2
msg_ok "Installed Dependencies"

msg_info "Disabling systemd autostart"
mkdir -p /etc/systemd/system-preset
echo "disable *" > /etc/systemd/system-preset/99-no-autostart.preset
msg_ok "Disabled systemd autostart"

msg_info "Installing Transmission"
$STD apt-get install -y transmission-daemon
msg_ok "Installed Transmission"

msg_info "Installing Privoxy"
$STD apt-get install -y privoxy
msg_ok "Installed Privoxy"

msg_info "Enabling systemd autostart"
rm -f /etc/systemd/system-preset/99-no-autostart.preset
systemctl preset-all
msg_ok "Enabled systemd autostart"

msg_info "Disabling and masking Transmission and Privoxy services"
systemctl disable --now transmission-daemon
systemctl mask transmission-daemon
systemctl disable --now privoxy
systemctl mask privoxy
msg_ok "Transmission and Privoxy services disabled and masked"

msg_info "Installing Openvpn"
$STD apt-get install -y openvpn
msg_ok "Installed Openvpn"

msg_info "Installing ${APPLICATION}"
useradd -u 911 -U -d /config -s /usr/sbin/nologin abc
fetch_and_deploy_gh_release "docker-transmission-openvpn" "haugene/docker-transmission-openvpn" "tarball" "latest" "/opt/docker-transmission-openvpn"
mkdir -p /etc/openvpn /etc/transmission /etc/scripts /opt/privoxy
cp -r /opt/docker-transmission-openvpn/openvpn/* /etc/openvpn/
cp -r /opt/docker-transmission-openvpn/transmission/* /etc/transmission/
cp -r /opt/docker-transmission-openvpn/scripts/* /etc/scripts/
cp -r /opt/docker-transmission-openvpn/privoxy/scripts/* /opt/privoxy/
chmod +x /etc/openvpn/*.sh
chmod +x /etc/scripts/*.sh
chmod +x /opt/privoxy/*.sh
ln -s /usr/bin/transmission-daemon /usr/local/bin/transmission-daemon
msg_ok "Installed ${APPLICATION}"

msg_info "Support legacy IPTables commands"
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
msg_ok "Support legacy IPTables commands"

msg_info "Analyzing Network Interfaces"
LOCAL_SUBNETS=$(
  ip -o -4 addr show \
  | awk '!/127.0.0.1/ {
      split($4, a, "/"); ip=a[1]; mask=a[2];
      split(ip, o, ".");
      if (mask < 8) {
        print "*.*.*.*";
      } else if (mask < 16) {
        print o[1]".*.*.*";
      } else if (mask < 24) {
        print o[1]"."o[2]".*.*";
      } else {
        print o[1]"."o[2]"."o[3]".*";
      }
    }' \
  | sort -u | paste -sd, -
)
TRANSMISSION_RPC_WHITELIST="127.0.0.*,${LOCAL_SUBNETS}"
msg_ok "Analyzed Network Interfaces"

msg_info "Creating Service"
mkdir -p /opt/transmission-openvpn
cat <<EOF > "/opt/transmission-openvpn/.env"
OPENVPN_USERNAME="username"
OPENVPN_PASSWORD="password"
OPENVPN_PROVIDER="PIA"
OPENVPN_CONFIG=france
OPENVPN_OPTS="--inactive 3600 --ping 10 --ping-exit 60 --mute-replay-warnings"
CUSTOM_OPENVPN_CONFIG_DIR="/opt/transmission-openvpn"
GLOBAL_APPLY_PERMISSIONS="true"
TRANSMISSION_HOME="/config/transmission-home"
TRANSMISSION_RPC_PORT="9091"
TRANSMISSION_RPC_USERNAME=""
TRANSMISSION_RPC_PASSWORD=""
TRANSMISSION_DOWNLOAD_DIR="/data/complete"
TRANSMISSION_INCOMPLETE_DIR="/data/incomplete"
TRANSMISSION_WATCH_DIR="/data/watch"
TRANSMISSION_WEB_UI=""
TRANSMISSION_UMASK="2"
TRANSMISSION_RATIO_LIMIT_ENABLED="true"
TRANSMISSION_RATIO_LIMIT="0"
TRANSMISSION_RPC_WHITELIST_ENABLED="false"
TRANSMISSION_RPC_WHITELIST="${TRANSMISSION_RPC_WHITELIST}"
CREATE_TUN_DEVICE="false"
ENABLE_UFW="false"
UFW_ALLOW_GW_NET="false"
UFW_EXTRA_PORTS=""
UFW_DISABLE_IPTABLES_REJECT="false"
PUID="911"
PGID=""
PEER_DNS="true"
PEER_DNS_PIN_ROUTES="true"
DROP_DEFAULT_ROUTE=""
WEBPROXY_ENABLED="true"
WEBPROXY_PORT="8118"
WEBPROXY_BIND_ADDRESS=""
WEBPROXY_USERNAME=""
WEBPROXY_PASSWORD=""
LOG_TO_STDOUT="false"
HEALTH_CHECK_HOST="google.com"
SELFHEAL="false"
EOF
cat <<EOF > /etc/systemd/system/openvpn-custom.service 
[Unit]
Description=Custom OpenVPN start service
After=network.target

[Service]
Type=simple
ExecStart=/etc/openvpn/start.sh
Restart=on-failure
RestartSec=5
EnvironmentFile=/opt/transmission-openvpn/.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now -q openvpn-custom.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
rm -rf /opt/docker-transmission-openvpn
msg_ok "Cleaned"

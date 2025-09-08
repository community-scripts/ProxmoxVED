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
    dumb-init \
    tzdata \
    dnsutils \
    iputils-ping \
    ufw \
    iproute2 \
    openssh-client \
    git \
    jq \
    curl \
    wget \
    unrar-free \
    unzip \
    bc \
    systemd 
msg_ok "Installed Dependencies"

msg_info "Installing Transmission"
mkdir -p /etc/systemd/system-preset
echo "disable *" > /etc/systemd/system-preset/99-no-autostart.preset
export DEBIAN_FRONTEND=noninteractive
$STD apt install -y transmission-daemon
rm -f /etc/systemd/system-preset/99-no-autostart.preset
systemctl preset-all
systemctl disable --now transmission-daemon
systemctl mask transmission-daemon
msg_ok "Installed Transmission"

msg_info "Installing Openvpn"
$STD apt-get install -y openvpn
msg_ok "Installed Openvpn"

msg_info "Installing Privoxy"
$STD apt-get install -y privoxy
msg_ok "Installed Privoxy"

msg_info "Installing ${APPLICATION}"
useradd -u 911 -U -d /config -s /usr/sbin/nologin abc
fetch_and_deploy_gh_release "docker-transmission-openvpn" "haugene/docker-transmission-openvpn" "tarball" "latest" "/opt/docker-transmission-openvpn"
mkdir -p /etc/openvpn /etc/transmission /etc/scripts /opt/privoxy
cp -r /opt/docker-transmission-openvpn/openvpn/* /etc/openvpn/
cp -r /opt/docker-transmission-openvpn/transmission/* /etc/transmission/
cp -r /opt/docker-transmission-openvpn/scripts/* /etc/scripts/
cp -r /opt/docker-transmission-openvpn/privoxy/scripts/* /opt/privoxy/
chmod +x /etc/openvpn/*.sh || true
chmod +x /etc/scripts/*.sh || true
chmod +x /opt/privoxy/*.sh || true
msg_ok "Installed ${APPLICATION}"

msg_info "Support legacy IPTables commands"
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
msg_ok "Support legacy IPTables commands"

msg_info "Installing WebUI"
mkdir -p /opt/transmission-ui
curl -fsSL -o "Shift-master.tar.gz" "https://github.com/killemov/Shift/archive/master.tar.gz"
tar xzf Shift-master.tar.gz
mv Shift-master /opt/transmission-ui/shift
curl -fsSL -o "kettu-master.tar.gz" "https://github.com/endor/kettu/archive/master.tar.gz"
tar xzf kettu-master.tar.gz
mv kettu-master /opt/transmission-ui/kettu
curl -fsSL -o "combustion-release.tar.gz" "https://github.com/Secretmapper/combustion/archive/release.tar.gz"
tar xzf combustion-release.tar.gz
mv combustion-release /opt/transmission-ui/combustion-release
fetch_and_deploy_gh_release "transmissionic" "6c65726f79/Transmissionic" "prebuild" "latest" "/opt/transmission-ui/transmissionic" "Transmissionic-webui-v1.8.0.zip"
fetch_and_deploy_gh_release "flood-for-transmission" "johman10/flood-for-transmission" "prebuild" "latest" "/opt/transmission-ui/flood-for-transmission" "flood-for-transmission.tar.gz"
msg_ok "Installed WebUI"

msg_info "Creating Service"
mkdir -p /opt/transmission-openvpn
cat > "/opt/transmission-openvpn/.env" <<EOF
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
TRANSMISSION_RPC_WHITELIST="127.0.0.1,192.168.*.*"
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

cat > /etc/systemd/system/openvpn-custom.service <<EOF
[Unit]
Description=Custom OpenVPN start service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dumb-init /etc/openvpn/start.sh
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
rm -f Shift-master.tar.gz
rm -f kettu-master.tar.gz
rm -f combustion-release.tar.gz
msg_ok "Cleaned"

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
msg_ok "Installed ${APPLICATION}"

msg_info "Support legacy IPTables commands"
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
msg_ok "Support legacy IPTables commands"

msg_info "Installing WebUI"
mkdir -p /opt/transmission-ui
wget -qO- https://github.com/killemov/Shift/archive/master.tar.gz | tar xz
mv Shift-master /opt/transmission-ui/shift
wget -qO- https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.tar.gz | tar xz
mv flood-for-transmission /opt/transmission-ui/flood
wget -qO- https://github.com/Secretmapper/combustion/archive/release.tar.gz | tar xz
mv combustion-release /opt/transmission-ui/combustion
wget -qO- https://github.com/endor/kettu/archive/master.tar.gz | tar xz
mv kettu-master /opt/transmission-ui/kettu
wget -q https://github.com/6c65726f79/Transmissionic/releases/download/v1.8.0/Transmissionic-webui-v1.8.0.zip
unzip -q Transmissionic-webui-v1.8.0.zip
mv web /opt/transmission-ui/transmissionic
msg_ok "Installed WebUI"

msg_info "Creating Service"
OPENVPN_USERNAME=${OPENVPN_USERNAME:-}
OPENVPN_PASSWORD=${OPENVPN_PASSWORD:-}
OPENVPN_PROVIDER=${OPENVPN_PROVIDER:-}
OPENVPN_OPTS=${OPENVPN_OPTS:-}
CUSTOM_OPENVPN_CONFIG_DIR=${CUSTOM_OPENVPN_CONFIG_DIR:-}
GLOBAL_APPLY_PERMISSIONS=${GLOBAL_APPLY_PERMISSIONS:-true}
TRANSMISSION_HOME=${TRANSMISSION_HOME:-/config/transmission-home}
TRANSMISSION_RPC_PORT=${TRANSMISSION_RPC_PORT:-9091}
TRANSMISSION_RPC_USERNAME=${TRANSMISSION_RPC_USERNAME:-}
TRANSMISSION_RPC_PASSWORD=${TRANSMISSION_RPC_PASSWORD:-}
TRANSMISSION_DOWNLOAD_DIR=${TRANSMISSION_DOWNLOAD_DIR:-/data/completed}
TRANSMISSION_INCOMPLETE_DIR=${TRANSMISSION_INCOMPLETE_DIR:-/data/incomplete}
TRANSMISSION_WATCH_DIR=${TRANSMISSION_WATCH_DIR:-/data/watch}
TRANSMISSION_WEB_UI=${TRANSMISSION_WEB_UI:-}
TRANSMISSION_UMASK=${TRANSMISSION_UMASK:-}
TRANSMISSION_RATIO_LIMIT_ENABLED=${TRANSMISSION_RATIO_LIMIT_ENABLED:-false}
TRANSMISSION_RATIO_LIMIT=${TRANSMISSION_RATIO_LIMIT:-}
TRANSMISSION_RPC_WHITELIST_ENABLED=${TRANSMISSION_RPC_WHITELIST_ENABLED:-true}
TRANSMISSION_RPC_WHITELIST=${TRANSMISSION_RPC_WHITELIST:-}
TRANSMISSION_RPC_HOST_WHITELIST_ENABLED=${TRANSMISSION_RPC_HOST_WHITELIST_ENABLED:-true}
TRANSMISSION_RPC_HOST_WHITELIST=${TRANSMISSION_RPC_HOST_WHITELIST:-}
CREATE_TUN_DEVICE=${CREATE_TUN_DEVICE:-false}
ENABLE_UFW=${ENABLE_UFW:-false}
UFW_ALLOW_GW_NET=${UFW_ALLOW_GW_NET:-false}
UFW_EXTRA_PORTS=${UFW_EXTRA_PORTS:-}
UFW_DISABLE_IPTABLES_REJECT=${UFW_DISABLE_IPTABLES_REJECT:-false}
PUID=${PUID:-911}
PGID=${PGID:-}
PEER_DNS=${PEER_DNS:-true}
PEER_DNS_PIN_ROUTES=${PEER_DNS_PIN_ROUTES:-true}
DROP_DEFAULT_ROUTE=${DROP_DEFAULT_ROUTE:-}
WEBPROXY_ENABLED=${WEBPROXY_ENABLED:-false}
WEBPROXY_PORT=${WEBPROXY_PORT:-8118}
WEBPROXY_BIND_ADDRESS=${WEBPROXY_BIND_ADDRESS:-}
WEBPROXY_USERNAME=${WEBPROXY_USERNAME:-}
WEBPROXY_PASSWORD=${WEBPROXY_PASSWORD:-}
LOG_TO_STDOUT=${LOG_TO_STDOUT:-false}
HEALTH_CHECK_HOST=${HEALTH_CHECK_HOST:-google.com}
SELFHEAL=${SELFHEAL:-false}
LOCAL_NETWORK=${LOCAL_NETWORK:-}

cat > "/opt/transmission-openvpn/.env" <<EOF
OPENVPN_USERNAME="${OPENVPN_USERNAME}"
OPENVPN_PASSWORD="${OPENVPN_PASSWORD}"
OPENVPN_PROVIDER="${OPENVPN_PROVIDER}"
OPENVPN_OPTS="${OPENVPN_OPTS}"
CUSTOM_OPENVPN_CONFIG_DIR="${CUSTOM_OPENVPN_CONFIG_DIR}"
GLOBAL_APPLY_PERMISSIONS="${GLOBAL_APPLY_PERMISSIONS}"
TRANSMISSION_HOME="${TRANSMISSION_HOME}"
TRANSMISSION_RPC_PORT="${TRANSMISSION_RPC_PORT}"
TRANSMISSION_RPC_USERNAME="${TRANSMISSION_RPC_USERNAME}"
TRANSMISSION_RPC_PASSWORD="${TRANSMISSION_RPC_PASSWORD}"
TRANSMISSION_DOWNLOAD_DIR="${TRANSMISSION_DOWNLOAD_DIR:-/data/completed}"
TRANSMISSION_INCOMPLETE_DIR="${TRANSMISSION_INCOMPLETE_DIR:-/data/incomplete}"
TRANSMISSION_WATCH_DIR="${TRANSMISSION_WATCH_DIR:-/data/watch}"
TRANSMISSION_WEB_UI="${TRANSMISSION_WEB_UI}"
TRANSMISSION_UMASK="${TRANSMISSION_UMASK}"
TRANSMISSION_RATIO_LIMIT_ENABLED="${TRANSMISSION_RATIO_LIMIT_ENABLED}"
TRANSMISSION_RATIO_LIMIT="${TRANSMISSION_RATIO_LIMIT}"
TRANSMISSION_RPC_WHITELIST_ENABLED="${TRANSMISSION_RPC_WHITELIST_ENABLED}"
TRANSMISSION_RPC_WHITELIST="${TRANSMISSION_RPC_WHITELIST}"
TRANSMISSION_RPC_HOST_WHITELIST_ENABLED="${TRANSMISSION_RPC_HOST_WHITELIST_ENABLED}"
TRANSMISSION_RPC_HOST_WHITELIST="${TRANSMISSION_RPC_HOST_WHITELIST}"
CREATE_TUN_DEVICE="${CREATE_TUN_DEVICE}"
ENABLE_UFW="${ENABLE_UFW}"
UFW_ALLOW_GW_NET="${UFW_ALLOW_GW_NET}"
UFW_EXTRA_PORTS="${UFW_EXTRA_PORTS}"
UFW_DISABLE_IPTABLES_REJECT="${UFW_DISABLE_IPTABLES_REJECT}"
PUID="${PUID}"
PGID="${PGID}"
PEER_DNS="${PEER_DNS}"
PEER_DNS_PIN_ROUTES="${PEER_DNS_PIN_ROUTES}"
DROP_DEFAULT_ROUTE="${DROP_DEFAULT_ROUTE}"
WEBPROXY_ENABLED="${WEBPROXY_ENABLED}"
WEBPROXY_PORT="${WEBPROXY_PORT}"
WEBPROXY_BIND_ADDRESS="${WEBPROXY_BIND_ADDRESS}"
WEBPROXY_USERNAME="${WEBPROXY_USERNAME}"
WEBPROXY_PASSWORD="${WEBPROXY_PASSWORD}"
LOG_TO_STDOUT="${LOG_TO_STDOUT}"
HEALTH_CHECK_HOST="${HEALTH_CHECK_HOST}"
SELFHEAL="${SELFHEAL}"
LOCAL_NETWORK="${LOCAL_NETWORK}"
EOF

cat > /etc/systemd/system/openvpn-custom.service <<EOF
[Unit]
Description=Custom OpenVPN start service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dumb-init /opt/docker-transmission-openvpn/openvpn/start.sh
Restart=on-failure
RestartSec=5
EnvironmentFile=/opt/transmission-openvpn/.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now -q openvpn-custom.service
msg_ok "Created Service"

msg_info "Creating Healthcheck"
HEALTHCHECK_SCRIPT="/opt/docker-transmission-openvpn/scripts/healthcheck.sh"
chmod +x "$HEALTHCHECK_SCRIPT"
(crontab -l 2>/dev/null | grep -v "$HEALTHCHECK_SCRIPT"; echo "* * * * * $HEALTHCHECK_SCRIPT") | crontab -
msg_ok "Created Healthcheck"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
rm -f Transmissionic-webui-v1.8.0.zip
msg_ok "Cleaned"

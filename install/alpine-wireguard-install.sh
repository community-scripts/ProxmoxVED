#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.wireguard.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add \
    newt \
    curl \
    openssh \
    nano \
    mc \
    gpg \
    iptables \
    supervisor \
    openrc
msg_ok "Installed Dependencies"

msg_info "Installing WireGuard"
$STD apk add --no-cache wireguard-tools
if [[ ! -L /etc/init.d/wg-quick.wg0 ]]; then
    ln -s /etc/init.d/wg-quick /etc/init.d/wg-quick.wg0
fi
rc-update add wg-quick.wg0 default
msg_ok "Installed WireGuard"

read -rp "Do you want to install WGDashboard? (y/N): " INSTALL_WGD
if [[ "$INSTALL_WGD" =~ ^[Yy]$ ]]; then
    msg_info "Installing additional dependencies for WGDashboard"
    $STD apk add --no-cache \
        python3 \
        py3-pip \
        git \
        sudo \
        musl-dev \
        linux-headers \
        gcc \
        python3-dev
    msg_ok "Installed additional dependencies for WGDashboard"
    msg_info "Installing WGDashboard"
    git clone -q https://github.com/donaldzou/WGDashboard.git /etc/wgdashboard
    cd /etc/wgdashboard/src || exit
    chmod u+x wgd.sh
    $STD ./wgd.sh install
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p /etc/sysctl.conf
    msg_ok "Installed WGDashboard"

    msg_info "Create Example Config for WGDashboard"
    private_key=$(wg genkey)
    cat <<EOF >/etc/wireguard/wg0.conf
[Interface]
PrivateKey = ${private_key}
Address = 10.0.0.1/24
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE;
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE;
ListenPort = 51820
EOF
    msg_ok "Created Example Config for WGDashboard"

    msg_info "Creating Supervisor Service for WGDashboard"
    mkdir -p /etc/supervisord.d/

    cat <<EOF > /etc/supervisord.d/wg-dashboard.ini
[program:wg-dashboard]
command=/etc/wgdashboard/src/wgd.sh start
autostart=true
autorestart=true
stderr_logfile=/var/log/wg-dashboard.err.log
stdout_logfile=/var/log/wg-dashboard.out.log
EOF

    if [[ ! -f /etc/supervisord.conf ]]; then
        cat <<EOF > /etc/supervisord.conf
[supervisord]
nodaemon=true

[include]
files = /etc/supervisord.d/*.ini
EOF
    fi

    msg_info "Starting Supervisor Daemon"
    nohup supervisord -c /etc/supervisord.conf &>/dev/null &
    msg_ok "Started Supervisor Daemon"

fi

motd_ssh
customize

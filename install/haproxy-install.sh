#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/Hermandev07/ProxmoxVED/raw/main/LICENSE
# Source: https://www.haproxy.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing HAProxy"
$STD apt install -y haproxy
msg_ok "Installed HAProxy"

msg_info "Configuring HAProxy"
cat <<EOF >/etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    pidfile /run/haproxy.pid
    maxconn 256
    user haproxy
    group haproxy

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    option  redispatch
    retries 3
    timeout connect 5s
    timeout client  50s
    timeout server  50s

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 30s
    stats auth admin:admin
EOF
msg_ok "Configured HAProxy"

msg_info "Validating HAProxy configuration"
$STD haproxy -c -f /etc/haproxy/haproxy.cfg
msg_ok "Validated HAProxy configuration"

msg_info "Starting HAProxy"
systemctl enable -q --now haproxy
msg_ok "Started HAProxy"

motd_ssh
customize
cleanup_lxc

msg_info "Restarting HAProxy"
systemctl restart haproxy.service
msg_ok "HAProxy restarted"

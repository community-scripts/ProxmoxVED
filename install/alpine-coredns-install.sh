#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CopilotAssistant (community-scripts)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/coredns/coredns

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ARCH=$(uname -m)
[[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
[[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
fetch_and_deploy_gh_release "coredns" "coredns/coredns" "prebuild" "latest" "/usr/local/bin" \
  "coredns_.*_linux_${ARCH}\.tgz"
chmod +x /usr/local/bin/coredns

msg_info "Configuring CoreDNS"
mkdir -p /etc/coredns
cat <<EOF >/etc/coredns/Corefile
. {
    forward . 1.1.1.1 1.0.0.1
    cache 30
    log
    errors
    health :8080
    ready :8181
}
EOF
msg_ok "Configured CoreDNS"

msg_info "Creating Service"
cat <<EOF >/etc/init.d/coredns
#!/sbin/openrc-run

name="CoreDNS"
description="CoreDNS DNS Server"
command="/usr/local/bin/coredns"
command_args="-conf /etc/coredns/Corefile"
command_background=true
pidfile="/run/coredns.pid"

depend() {
  need net
}
EOF
chmod +x /etc/init.d/coredns
$STD rc-update add coredns default
$STD rc-service coredns start
msg_ok "Created Service"

motd_ssh
customize

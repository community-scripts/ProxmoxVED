#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/bitmagnet-io/bitmagnet

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apk add --no-cache \
  gcc \
  musl-dev \
  git \
  iproute2-ss
$STD apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community go
msg_ok "Installed dependencies"

msg_info "Installing PostgreSQL"
$STD apk add --no-cache \
  postgresql15 \
  postgresql15-contrib \
  postgresql15-openrc
msg_ok "Installed PostreSQL"

RELEASE=$(curl -s https://api.github.com/repos/bitmagnet-io/bitmagnet/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

msg_info "Installing bitmagnet v${RELEASE}"
fetch_and_deploy_gh_release "bitmagnet-io/bitmagnet"
cd /opt/bitmagnet
$STD go build -ldflags "-s -w -X github.com/bitmagnet-io/bitmagnet/internal/version.GitTag=$(git describe --tags --always --dirty)"
echo "${RELEASE}" >/opt/bitmagnet_version.txt
msg_ok "Installed bitmagnet v${RELEASE}"

msg_info "Enabling bitmagnet Service"
cat <<EOF >/etc/init.d/bitmagnet
#!/sbin/openrc-run
description="bitmagnet Service"
directory="/opt/bitmagnet"
command="/opt/bitmagnet/bitmagnet"
command_args="worker run --all"
command_background="true"
command_user="root"
pidfile="/var/run/bitmagnet.pid"

depend() {
    use net
}
EOF
chmod +x /etc/init.d/bitmagnet
$STD rc-update add bitmagnet default
msg_ok "Enabled bitmagnet Service"

msg_info "Starting bitmagnet"
$STD service bitmagnet start
msg_ok "Started bitmagnet"

motd_ssh
customize

msg_info "Cleaning up"
$STD apk cache clean
msg_ok "Cleaned"

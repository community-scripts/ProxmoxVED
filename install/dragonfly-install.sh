#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/dragonflydb/dragonfly

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y redis-tools
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "dragonfly" "dragonflydb/dragonfly" "binary"

msg_info "Configuring Dragonfly"
cat <<EOF >>/etc/dragonfly/dragonfly.conf
--bind=0.0.0.0
--port=6379
--requirepass=$(random_password)
--dbfilename=dump
--snapshot_cron=*/30 * * * *
EOF
msg_ok "Configured Dragonfly"

msg_info "Starting Dragonfly"
systemctl enable -q --now dragonfly
msg_ok "Started Dragonfly"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Simon Bach Jessen (bachjessen)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.sprout-track.com/ | Github: https://github.com/Oak-and-Sprout/sprout-track

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  openssl
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release \
  "sprout-track" \
  "Oak-and-Sprout/sprout-track" \
  "tarball"

msg_info "Setting up Sprout Track"
cd /opt/sprout-track || exit
export NODE_OPTIONS="--max-old-space-size=1536"
chmod +x scripts/*.sh ./*.sh 2>/dev/null || true
$STD ./scripts/setup.sh
msg_ok "Set up Sprout Track"

msg_info "Creating Service"
cat <<'EOF_SERVICE' >/etc/systemd/system/sprout-track.service
[Unit]
Description=Sprout Track Service
Documentation=https://github.com/Oak-and-Sprout/sprout-track
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/sprout-track
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl enable -q --now sprout-track
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

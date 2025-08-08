#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.deluge-torrent.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  python3-libtorrent \
  python3 \
  python3-dev \
  build-essential
msg_ok "Installed Dependencies"

setup_uv

msg_info "Installing Deluge"
$STD uv pip install deluge[all] --system
msg_ok "Installed Deluge"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/deluged.service
[Unit]
Description=Deluge Bittorrent Client Daemon
Documentation=man:deluged
After=network-online.target

[Service]
Type=simple
UMask=007
ExecStart=/usr/local/bin/deluged -d
Restart=on-failure
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/deluge-web.service
[Unit]
Description=Deluge Bittorrent Client Web Interface
Documentation=man:deluge-web
After=deluged.service
Wants=deluged.service

[Service]
Type=simple
UMask=027
ExecStart=/usr/local/bin/deluge-web -d
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now deluged
systemctl enable -q --now deluge-web
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

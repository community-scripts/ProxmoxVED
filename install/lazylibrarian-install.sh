#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck
# Co-Author: MountyMapleSyrup (MountyMapleSyrup)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://gitlab.com/LazyLibrarian/LazyLibrarian

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  libpng-dev \
  libjpeg-dev \
  libtiff-dev \
  imagemagick \
  python3-irc
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv

msg_info "Setup LazyLibrarian"
$STD pip install jaraco.stream
$STD pip install python-Levenshtein
$STD pip install soupsieve
$STD pip install pypdf

$STD git clone https://gitlab.com/LazyLibrarian/LazyLibrarian /opt/LazyLibrarian
cd /opt/LazyLibrarian
$STD uv pip install .
msg_ok "Installed LazyLibrarian"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/lazylibrarian.service
[Unit]
Description=LazyLibrarian Daemon
After=syslog.target network.target
[Service]
UMask=0002
Type=simple
ExecStart=/usr/bin/python3 /opt/LazyLibrarian/LazyLibrarian.py
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now lazylibrarian
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

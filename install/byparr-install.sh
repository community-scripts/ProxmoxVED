#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: luismco
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ThePhaseless/Byparr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

<<<<<<< HEAD
=======
msg_info "Installing Dependencies"
$STD apt -y install \
    xauth \
    xvfb \
    scrot \
    curl \
    chromium \
    chromium-driver \
    ca-certificates
msg_ok "Installed Dependencies"

>>>>>>> 705b0b3ed245a44466c93f68bc8f966962c11eee
fetch_and_deploy_gh_release "Byparr" "ThePhaseless/Byparr"

setup_uv

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/byparr.service
[Unit]
Description=Byparr
After=network.target
<<<<<<< HEAD
=======

>>>>>>> 705b0b3ed245a44466c93f68bc8f966962c11eee
[Service]
Type=simple
WorkingDirectory=/opt/Byparr
ExecStart=/usr/local/bin/uv run python3 main.py
Restart=on-failure
RestartSec=10
<<<<<<< HEAD
[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now byparr
=======

[Install]
WantedBy=multi-user.target
EOF
>>>>>>> 705b0b3ed245a44466c93f68bc8f966962c11eee
msg_ok "Created Service"

motd_ssh
customize
<<<<<<< HEAD
=======
cleanup_lxc

systemctl enable -q --now byparr
>>>>>>> 705b0b3ed245a44466c93f68bc8f966962c11eee

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: luismco
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/mmastrac/stylus

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y \
  build-essential \
  openssl \
  libssl-dev \
  pkg-config
msg_ok "Installed dependencies"

msg_info "Installing Rust"
$STD su -c "curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh -s -- -y"
$STD . "$HOME/.cargo/env"
$STD cargo install cargo-update
msg_ok "Installed Rust"

msg_info "Installing Stylus"
$STD cargo install stylus
$STD stylus init /opt/stylus/
$STD su -c "cargo install --list | grep 'stylus' | cut -d' ' -f2 | sed 's/^v//;s/:$//' > /opt/stylus/stylus_version.txt"
msg_ok "Installed Stylus"

msg_info "Creating service"

cat >/etc/systemd/system/stylus.service <<EOF
[Unit]
Description=Stylus
After=network.target

[Service]
Type=simple
ExecStart=$HOME/.cargo/bin/stylus run /opt/stylus
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now stylus
msg_ok "Created service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt-get -y clean
msg_ok "Cleaned up"

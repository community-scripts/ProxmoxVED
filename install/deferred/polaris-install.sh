#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/agersant/polaris

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  make \
  git \
  build-essential \
  binutils \
  pkg-config \
  libsqlite3-dev \
  libssl-dev
msg_ok "Installed Dependencies"

msg_info "Installing Rust"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
echo 'export PATH=~/.cargo/bin:$PATH' >>~/.bashrc
export PATH=~/.cargo/bin:$PATH
msg_ok "Installed Rust"

msg_info "Downloading and Installing Polaris"
cd /opt
RELEASE=$(curl -s https://api.github.com/repos/agersant/polaris/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q "https://github.com/agersant/polaris/archive/refs/tags/${RELEASE}.tar.gz"
tar -xzf ${RELEASE}.tar.gz
mv polaris-${RELEASE} /opt/polaris
cd /opt/polaris
$STD cargo build --release
msg_ok "Installed Polaris"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/polaris.service
[Unit]
Description=Polaris Music Server
After=network.target

[Service]
Type=simple
Environment=PATH=$PATH
WorkingDirectory=/opt/polaris
ExecStart=/opt/polaris/target/release/polaris
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now polaris
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/${RELEASE}.tar.gz
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: dkuku
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/livebook-dev/livebook

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (matching Livebook Dockerfile)"
$STD apt-get install -y \
    build-essential \
    ca-certificates \
    cmake \
    git \
    libncurses5-dev
msg_ok "Installed Dependencies"

msg_info "Installing Erlang and Elixir
ELIXIR_VERSION=1.18.4-otp-27
ERLANG_VERSION=27.3.4
mkdir -p /opt /data
export HOME=/opt
touch $HOME/.env
cd /opt || exit 1
curl -fsSO https://elixir-lang.org/install.sh
$STD sh install.sh elixir@$ELXIR_VERSION otp@$ERLANG_VERSION
echo 'export HOME=/opt' >> $HOME/.env
echo 'export PATH="/opt/.elixir-install/installs/otp/${ERLANG_VERSION}/bin:/opt/.elixir-install/installs/elixir/${ELIXIR_VERSION}/bin:$PATH"' >> $HOME/.env
msg_ok "Installed Erlang and Elixir"

msg_info "Installing Livebook"
RELEASE=$(curl -fsSL https://api.github.com/repos/livebook-dev/livebook/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')

source /opt/.env
cd /opt || exit 1
$STD mix local.hex --force
$STD mix local.rebar --force
$STD mix escript.install hex livebook --force
echo 'export PATH="$HOME/.mix/escripts:$PATH"' >> ~/.env
msg_ok "Installed Livebook"

msg_info "Creating Livebook Service"
cat <<EOF >/etc/systemd/system/livebook.service
[Unit]
Description=Livebook
After=network.target

[Service]
Type=exec
User=root
Group=root
WorkingDirectory=/data
Environment=MIX_ENV=prod
Environment=HOME=/opt
Environment=PATH=/opt/.mix/escripts:/opt/.elixir-install/installs/otp/27.3.4/bin:/opt/.elixir-install/installs/elixir/1.18.4-otp-27/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=LIVEBOOK_PORT=8080
Environment=LIVEBOOK_IP="::"
Environment=LIVEBOOK_HOME=/data
Environment=LIVEBOOK_TOKEN_ENABLED=false
ExecStart=/bin/bash -c 'cd /opt && livebook server'
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now livebook
msg_ok "Created Livebook Service"

motd_ssh
customize

msg_info "Cleaning Up"
rm -f /opt/install.sh
$STD apt-get autoremove -y
$STD apt-get autoclean
msg_ok "Cleaned Up"

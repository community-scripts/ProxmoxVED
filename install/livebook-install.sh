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
$STD apt-get install --no-install-recommends -y \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    libncurses5-dev
msg_ok "Installed Dependencies"


msg_info "Installing Erlang and Elixir"
mkdir -p /opt /data
export HOME=/opt
touch $HOME/.env
cd /opt || exit 1
curl -fsSO https://elixir-lang.org/install.sh
sh install.sh elixir@1.18.4 otp@27.3.4 >/dev/null 2>&1
echo 'export HOME=/opt' >> $HOME/.env
echo 'export PATH="/opt/.elixir-install/installs/otp/27.3.4/bin:/opt/.elixir-install/installs/elixir/1.18.4-otp-27/bin:$PATH"' >> $HOME/.env
msg_ok "Installed Erlang 27.3.4 and Elixir 1.18.4"

msg_info "Installing Livebook"
RELEASE=$(curl -fsSL https://api.github.com/repos/livebook-dev/livebook/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')
echo "${RELEASE}" >/opt/Livebook_version.txt

source /opt/.env
cd /opt || exit 1
mix local.hex --force >/dev/null 2>&1
mix local.rebar --force >/dev/null 2>&1
mix escript.install hex livebook --force >/dev/null 2>&1
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

$STD systemctl enable livebook.service
$STD systemctl start livebook.service
msg_ok "Created Livebook Service"

msg_info "Cleaning Up"
rm -f /opt/install.sh
$STD apt-get autoremove -y
$STD apt-get autoclean
msg_ok "Cleaned Up"

motd_ssh
customize

echo -e "\n${CREATING}${GN}Livebook Installation Complete!${CL}\n"

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
    libncurses5-dev \
    curl
msg_ok "Installed Dependencies"

msg_info "Creating livebook user"
adduser --system --group --home /opt --shell /bin/bash livebook
msg_ok "Created livebook user"

msg_info "Installing Erlang and Elixir"

mkdir -p /opt /data
export HOME=/opt
cd /opt || exit 1

curl -fsSO https://elixir-lang.org/install.sh
$STD sh install.sh elixir@latest otp@latest
RELEASE=$(curl -fsSL https://api.github.com/repos/livebook-dev/livebook/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')

ERLANG_VERSION=$(ls /opt/.elixir-install/installs/otp/ | head -n1)
ELIXIR_VERSION=$(ls /opt/.elixir-install/installs/elixir/ | head -n1)

export ERLANG_BIN="/opt/.elixir-install/installs/otp/$ERLANG_VERSION/bin"
export ELIXIR_BIN="/opt/.elixir-install/installs/elixir/$ELIXIR_VERSION/bin"
export PATH="$ERLANG_BIN:$ELIXIR_BIN:$PATH"

$STD mix local.hex --force
$STD mix local.rebar --force
$STD mix escript.install hex livebook --force

LIVEBOOK_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)

cat <<EOF > /opt/livebook.creds
Livebook-Credentials
Livebook Password: $LIVEBOOK_PASSWORD
EOF

cat <<EOF > /opt/.env
export HOME=/opt
export LIVEBOOK_VERSION=$RELEASE
export ERLANG_VERSION=$ERLANG_VERSION
export ELIXIR_VERSION=$ELIXIR_VERSION
export LIVEBOOK_PORT=8080
export LIVEBOOK_IP="::"
export LIVEBOOK_HOME=/data
export LIVEBOOK_PASSWORD="$LIVEBOOK_PASSWORD"
export ESCRIPTS_BIN=/opt/.mix/escripts
export ERLANG_BIN="/opt/.elixir-install/installs/otp/\${ERLANG_VERSION}/bin"
export ELIXIR_BIN="/opt/.elixir-install/installs/elixir/\${ELIXIR_VERSION}/bin"
export PATH="\$ESCRIPTS_BIN:\$ERLANG_BIN:\$ELIXIR_BIN:\$PATH"
EOF

msg_ok "Installed Erlang $ERLANG_VERSION and Elixir $ELIXIR_VERSION"

msg_info "Installing Livebook"
cat <<EOF >/etc/systemd/system/livebook.service
[Unit]
Description=Livebook
After=network.target

[Service]
Type=exec
User=livebook
Group=livebook
WorkingDirectory=/data
EnvironmentFile=-/opt/.env
ExecStart=/bin/bash -c 'source /opt/.env && cd /opt && livebook server'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

msg_info "Setting ownership and permissions"
chown -R livebook:livebook /opt /data
msg_ok "Set ownership and permissions"

systemctl enable -q --now livebook
msg_ok "Installed Livebook"

motd_ssh
customize

msg_info "Cleaning Up"
rm -f /opt/install.sh
$STD apt-get autoremove -y
$STD apt-get autoclean
msg_ok "Cleaned Up"

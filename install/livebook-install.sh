#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: dkuku
# License: MIT |

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
    libncurses5-dev \
    git \
    wget \
    cmake \
    elixir
msg_ok "Installed Dependencies"

msg_info "Creating Livebook User and Directories"
useradd -r -s /bin/bash -d /home/livebook livebook
mkdir -p /home/livebook /data
chown livebook:livebook /home/livebook /data
# Make sure user has permissions to home dir (for Mix.install/2 cache)
chmod 777 /home/livebook
msg_ok "Created Livebook User and Directories"

msg_info "Installing Livebook"
sudo -u livebook bash << 'EOF'
export HOME=/home/livebook
cd /home/livebook
# Install hex and rebar for Mix.install/2 and Mix runtime (matching Dockerfile)
mix local.hex --force
mix local.rebar --force
# Following official Livebook escript installation instructions
mix escript.install hex livebook
echo 'export PATH="$HOME/.mix/escripts:$PATH"' >> ~/.bashrc
source ~/.bashrc
EOF
msg_ok "Installed Livebook"

msg_info "Creating Livebook Service"
cat <<EOF >/etc/systemd/system/livebook.service
[Unit]
Description=Livebook
After=network.target

[Service]
Type=exec
User=livebook
Group=livebook
WorkingDirectory=/data
Environment=HOME=/home/livebook
Environment=PATH=/home/livebook/.mix/escripts:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=LIVEBOOK_PORT=8080
Environment=LIVEBOOK_IP="::"
Environment=LIVEBOOK_HOME=/data
ExecStart=/home/livebook/.mix/escripts/livebook server
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable livebook.service
msg_ok "Created Livebook Service"

msg_info "Setting up Authentication"
# Generate a secure token for authentication
TOKEN=$(openssl rand -hex 32)
sudo -u livebook bash << EOF
cd /home/livebook
export HOME=/home/livebook
export PATH="\$HOME/.mix/escripts:\$PATH"
# Create environment file with authentication settings
cat > /data/.env << 'ENVEOF'
# Livebook Authentication Configuration
# Uncomment one of the following options:

# Option 1: Password authentication (recommended for production)
# LIVEBOOK_PASSWORD=$TOKEN

# Option 2: Token authentication (default - token will be shown in logs)
# LIVEBOOK_TOKEN_ENABLED=true

# Option 3: Disable authentication (NOT recommended for production)
# LIVEBOOK_TOKEN_ENABLED=false

# Current setting: Token authentication (default)
LIVEBOOK_TOKEN_ENABLED=true
ENVEOF

# Save the token for easy access
echo "$TOKEN" > /data/token.txt
chmod 600 /data/token.txt
chown livebook:livebook /data/.env /data/token.txt
EOF
msg_ok "Set up Authentication"

msg_info "Starting Livebook Service"
systemctl start livebook.service
msg_ok "Started Livebook Service"

msg_info "Cleaning Up"
rm -f /tmp/erlang-solutions_2.0_all.deb
$STD apt-get autoremove -y
$STD apt-get autoclean
msg_ok "Cleaned Up"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

echo -e "\n${CREATING}${GN}Livebook Installation Complete!${CL}\n"
echo -e "${INFO}${YW}Authentication Information:${CL}"
echo -e "${TAB}${RD}• Default: Token authentication (auto-generated)${CL}"
echo -e "${TAB}${RD}• Token will be displayed in Livebook logs on startup${CL}"
echo -e "${TAB}${RD}• Generated token saved to: /data/token.txt${CL}"
echo -e "${TAB}${RD}• Configuration file: /data/.env${CL}\n"

echo -e "${INFO}${YW}To configure authentication:${CL}"
echo -e "${TAB}${RD}1. Password auth: Edit /data/.env and uncomment LIVEBOOK_PASSWORD${CL}"
echo -e "${TAB}${RD}2. No auth: Edit /data/.env and set LIVEBOOK_TOKEN_ENABLED=false${CL}"
echo -e "${TAB}${RD}3. Restart service: systemctl restart livebook.service${CL}\n"

echo -e "${INFO}${YW}Generated Token (for reference):${CL}"
echo -e "${TAB}${GN}$(cat /data/token.txt)${CL}\n"

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

msg_info "Creating Livebook User and Directories"
useradd -r -s /bin/bash -d /opt livebook
mkdir -p /opt /data
chown livebook:livebook /opt /data

chmod 777 /opt
msg_ok "Created Livebook User and Directories"

msg_info "Installing Erlang and Elixir"
# Create a temporary script
cat > /tmp/setup_elixir.sh << 'EOF'
#!/bin/bash
export HOME=/opt
cd /opt
curl -fsSO https://elixir-lang.org/install.sh
sh install.sh elixir@1.18.4 otp@27.3.4 >/dev/null 2>&1

# Create .env if it doesn't exist and set permissions
touch $HOME/.env
chmod 644 $HOME/.env

# Add exports to .env
echo 'export HOME=/opt' >> $HOME/.env
echo 'export PATH="$HOME/.elixir-install/installs/otp/27.3.4/bin:$HOME/.elixir-install/installs/elixir/1.18.4-otp-27/bin:$PATH"' >> $HOME/.env
EOF

# Make it executable and run as livebook user
chmod +x /tmp/setup_elixir.sh
$STD sudo -u livebook -H /tmp/setup_elixir.sh
rm /tmp/setup_elixir.sh
msg_ok "Installed Erlang 27.3.4 and Elixir 1.18.4"

msg_info "Installing Livebook"

cat > /tmp/install_livebook.sh << 'EOF'
#!/bin/bash
RELEASE=$(curl -fsSL https://api.github.com/repos/livebook-dev/livebook/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')
echo "${RELEASE}" >/opt/Livebook_version.txt

set -e  # Exit on any error
source /opt/.env
cd $HOME

# Install hex and rebar for Mix.install/2 and Mix runtime (matching Dockerfile)
echo "Installing hex..."
mix local.hex --force
echo "Installing rebar..."
mix local.rebar --force

# Following official Livebook escript installation instructions
echo "Installing Livebook escript..."
MIX_ENV=prod mix escript.install hex livebook --force

# Add escripts to PATH
echo 'export PATH="$HOME/.mix/escripts:$PATH"' >> ~/.env

# Verify livebook was installed and make executable
if [ -f ~/.mix/escripts/livebook ]; then
    chmod +x ~/.mix/escripts/livebook
    echo "Livebook escript installed successfully"
    ls -la ~/.mix/escripts/livebook
else
    echo "ERROR: Livebook escript not found after installation"
    ls -la ~/.mix/escripts/ || echo "No escripts directory found"
    # Try to show what went wrong
    echo "Mix environment:"
    mix --version
    echo "Available packages:"
    mix hex.info livebook || echo "Could not get livebook info"
    exit 1
fi
EOF

chmod +x /tmp/install_livebook.sh
$STD sudo -u livebook -H /tmp/install_livebook.sh
rm /tmp/install_livebook.sh

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
msg_ok "Created Livebook Service"

msg_info "Cleaning Up"
rm -f /opt/install.sh
$STD apt-get autoremove -y
$STD apt-get autoclean
msg_ok "Cleaned Up"

msg_info "Starting Livebook Service"
$STD systemctl start livebook.service
msg_ok "Started Livebook Service"


motd_ssh
customize

echo -e "\n${CREATING}${GN}Livebook Installation Complete!${CL}\n"

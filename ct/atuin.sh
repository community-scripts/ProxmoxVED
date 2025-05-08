#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: j4v3l (https://github.com/j4v3l)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://docs.atuin.sh/self-hosting/server-setup/

APP="Atuin"
var_tags="${var_tags:-shell history,sync}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/atuin.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apt-get update
  $STD apt-get -y upgrade

  # Check for Atuin updates
  LATEST_VERSION=$(curl -s https://api.github.com/repos/atuinsh/atuin/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
  CURRENT_VERSION=$(atuin --version | awk '{print $2}')

  if [[ "$LATEST_VERSION" != "$CURRENT_VERSION" ]]; then
    msg_info "Updating Atuin from $CURRENT_VERSION to $LATEST_VERSION"
    $STD curl -fsSL https://get.atuin.sh | bash
    systemctl restart atuin
    msg_ok "Updated Atuin to $LATEST_VERSION"
  else
    msg_ok "Atuin is already at the latest version: $CURRENT_VERSION"
  fi

  msg_ok "Updated $APP LXC"
  exit
}

start
build_container
description

msg_info "Setting up PostgreSQL Repository"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" >/etc/apt/sources.list.d/pgdg.list
$STD apt-get update
$STD apt-get install -y postgresql-14 postgresql-contrib-14
msg_ok "Set up PostgreSQL Repository"

msg_info "Configuring PostgreSQL for Atuin"
# Create user and database
PG_USER="atuin"
PG_PASSWORD=$(openssl rand -base64 24)
PG_DB="atuin"

# Create PostgreSQL user and database
$STD su postgres <<EOF
createuser $PG_USER
createdb -O $PG_USER $PG_DB
psql -c "ALTER USER $PG_USER WITH PASSWORD '$PG_PASSWORD';"
EOF

# Save credentials to a file
mkdir -p /root/.config/
echo "Atuin Database Credentials" >/root/atuin.creds
echo "----------------------------" >>/root/atuin.creds
echo "Database Host: localhost" >>/root/atuin.creds
echo "Database User: $PG_USER" >>/root/atuin.creds
echo "Database Password: $PG_PASSWORD" >>/root/atuin.creds
echo "Database Name: $PG_DB" >>/root/atuin.creds
echo "----------------------------" >>/root/atuin.creds
msg_ok "Configured PostgreSQL for Atuin"

msg_info "Installing Atuin"
$STD apt-get install -y curl
$STD curl -fsSL https://get.atuin.sh | bash
msg_ok "Installed Atuin"

msg_info "Configuring Atuin Server"
# Create server config directory
mkdir -p /root/.config/atuin/
cat >/root/.config/atuin/server.toml <<EOF
host = "0.0.0.0"
port = 8888
open_registration = true
db_uri = "postgres://$PG_USER:$PG_PASSWORD@localhost/$PG_DB"

# Uncomment and modify for TLS support
# [tls]
# enable = true
# cert_path = "/path/to/cert.pem"
# pkey_path = "/path/to/key.pem"
EOF
msg_ok "Configured Atuin Server"

msg_info "Creating Atuin Service"
cat >/etc/systemd/system/atuin.service <<EOF
[Unit]
Description=Atuin Server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/atuin server start
Restart=on-failure
RestartSec=5s
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl daemon-reload
$STD systemctl enable atuin
$STD systemctl start atuin
msg_ok "Created Atuin Service"

# Get the IP address for display
IP=$(hostname -I | awk '{print $1}')

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} server has been successfully installed!${CL}"
echo -e "${INFO}${YW}The server is running on:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8888${CL}"
echo -e "${INFO}${YW}Credentials are saved to:${CL}"
echo -e "${TAB}${BGN}/root/atuin.creds${CL}"
echo -e "${INFO}${YW}To connect clients, add to your shell config (~/.bashrc, ~/.zshrc, etc.):${CL}"
echo -e "${TAB}${BGN}export ATUIN_HOST=\"http://${IP}:8888\"${CL}"
echo -e "${INFO}${YW}Then run on client:${CL}"
echo -e "${TAB}${BGN}atuin register <username>${CL}"
echo -e "${TAB}${BGN}atuin sync${CL}"

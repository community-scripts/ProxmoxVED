#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/CyferShepard/Jellystat

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)

# ==============================================================================
# CONFIGURATION
# ==============================================================================
APP="Jellystat"
APP_TYPE="addon"
INSTALL_PATH="/opt/jellystat"
CONFIG_PATH="/opt/jellystat/.env"
DEFAULT_PORT=3000

# ==============================================================================
# HEADER
# ==============================================================================
function header_info {
  clear
  cat <<"EOF"
       __     ____           __        __
      / /__  / / /_  _______/ /_____ _/ /_
 __  / / _ \/ / / / / / ___/ __/ __ `/ __/
/ /_/ /  __/ / / /_/ (__  ) /_/ /_/ / /_
\____/\___/_/_/\__, /____/\__/\__,_/\__/
              /____/
EOF
}

# ==============================================================================
# COLORS & FORMATTING
# ==============================================================================
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"
TAB="  "

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }
function msg_warn() { echo -e "⚠️  ${YW}${1}${CL}"; }

function get_ip() {
  local iface ip
  iface=$(ip -4 route | awk '/default/ {print $5; exit}')
  ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
  [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$ip" ]] && ip="127.0.0.1"
  echo "$ip"
}

# ==============================================================================
# OS DETECTION
# ==============================================================================
if [[ -f "/etc/alpine-release" ]]; then
  msg_error "Alpine is not supported for ${APP}. Use Debian/Ubuntu."
  exit 1
elif [[ -f "/etc/debian_version" ]]; then
  OS="Debian"
  SERVICE_PATH="/etc/systemd/system/jellystat.service"
else
  echo -e "${CROSS} Unsupported OS detected. Exiting."
  exit 1
fi

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall() {
  msg_info "Uninstalling ${APP}"
  systemctl disable --now jellystat.service &>/dev/null || true
  rm -f "$SERVICE_PATH"
  rm -rf "$INSTALL_PATH"
  rm -f "/usr/local/bin/update_jellystat"
  msg_ok "${APP} has been uninstalled"
  msg_warn "PostgreSQL database was NOT removed. Remove manually if needed."
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update() {
  if check_for_gh_release "jellystat" "CyferShepard/Jellystat"; then
    msg_info "Stopping service"
    systemctl stop jellystat.service &>/dev/null || true
    msg_ok "Stopped service"

    msg_info "Backing up configuration"
    cp "$CONFIG_PATH" /tmp/jellystat.env.bak 2>/dev/null || true
    msg_ok "Backed up configuration"

    fetch_and_deploy_gh_release "jellystat" "CyferShepard/Jellystat" "tarball" "latest" "$INSTALL_PATH"

    msg_info "Restoring configuration"
    cp /tmp/jellystat.env.bak "$CONFIG_PATH" 2>/dev/null || true
    rm -f /tmp/jellystat.env.bak
    msg_ok "Restored configuration"

    msg_info "Installing dependencies"
    cd "$INSTALL_PATH"
    npm install &>/dev/null
    msg_ok "Installed dependencies"

    msg_info "Building ${APP}"
    npm run build &>/dev/null
    msg_ok "Built ${APP}"

    msg_info "Starting service"
    systemctl start jellystat.service &>/dev/null
    msg_ok "Started service"

    msg_ok "Updated ${APP} successfully"
  else
    msg_ok "${APP} is already up-to-date"
  fi
}

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  local ip
  ip=$(get_ip)

  # Setup Node.js (only installs if not present or different version)
  if command -v node &>/dev/null; then
    msg_ok "Node.js already installed ($(node -v))"
  else
    NODE_VERSION="22" setup_nodejs
  fi

  # Setup PostgreSQL (only installs if not present)
  if command -v psql &>/dev/null; then
    msg_ok "PostgreSQL already installed"
  else
    PG_VERSION="17" setup_postgresql
  fi

  # Create database and user (skip if already exists)
  local DB_NAME="jellystat"
  local DB_USER="jellystat"
  local DB_PASS

  msg_info "Setting up PostgreSQL database"

  # Check if database already exists
  if sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    msg_warn "Database '${DB_NAME}' already exists - skipping creation"
    echo -n "${TAB}Enter existing database password for '${DB_USER}': "
    read -rs DB_PASS
    echo ""
  else
    # Generate new password
    DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)

    # Check if user exists, create if not
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" 2>/dev/null | grep -q 1; then
      msg_info "User '${DB_USER}' exists, updating password"
      sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" &>/dev/null
    else
      sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" &>/dev/null
    fi

    # Create database
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} WITH OWNER ${DB_USER} ENCODING 'UTF8';" &>/dev/null
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" &>/dev/null
    msg_ok "Created PostgreSQL database '${DB_NAME}'"
  fi

  # Generate JWT Secret
  local JWT_SECRET
  JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c32)

  msg_info "Downloading ${APP}"
  fetch_and_deploy_gh_release "jellystat" "CyferShepard/Jellystat" "tarball" "latest" "$INSTALL_PATH"
  msg_ok "Downloaded ${APP}"

  msg_info "Installing dependencies"
  cd "$INSTALL_PATH"
  npm install &>/dev/null
  msg_ok "Installed dependencies"

  msg_info "Building ${APP}"
  npm run build &>/dev/null
  msg_ok "Built ${APP}"

  msg_info "Creating configuration"
  cat <<EOF >"$CONFIG_PATH"
# Jellystat Configuration
# Database
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${DB_PASS}
POSTGRES_IP=localhost
POSTGRES_PORT=5432
POSTGRES_DB=${DB_NAME}

# Security
JWT_SECRET=${JWT_SECRET}

# Server
JS_LISTEN_IP=0.0.0.0
JS_BASE_URL=/
TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")

# Optional: GeoLite for IP Geolocation
# JS_GEOLITE_ACCOUNT_ID=
# JS_GEOLITE_LICENSE_KEY=

# Optional: Master Override (if you forget your password)
# JS_USER=admin
# JS_PASSWORD=admin

# Optional: Minimum playback duration to record (seconds)
# MINIMUM_SECONDS_TO_INCLUDE_PLAYBACK=1

# Optional: Self-signed certificates
REJECT_SELF_SIGNED_CERTIFICATES=true
EOF
  chmod 600 "$CONFIG_PATH"
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=Jellystat - Statistics for Jellyfin
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_PATH}
EnvironmentFile=${CONFIG_PATH}
ExecStart=/usr/bin/node ${INSTALL_PATH}/backend/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now jellystat &>/dev/null
  msg_ok "Created and started service"

  # Create update script
  msg_info "Creating update script"
  cat <<'UPDATEEOF' >/usr/local/bin/update_jellystat
#!/usr/bin/env bash
# Jellystat Update Script
# Auto-generated by community-scripts addon installer

set -e

APP="Jellystat"
INSTALL_PATH="/opt/jellystat"
CONFIG_PATH="/opt/jellystat/.env"

# Colors
YW='\033[33m'
GN='\033[1;92m'
RD='\033[01;31m'
BL='\033[36m'
CL='\033[m'
CM="${GN}✔️${CL}"
INFO="${BL}ℹ️${CL}"

msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }

echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${GN}       Jellystat Update Script${CL}"
echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo ""

# Source tools.func for check_for_gh_release and fetch_and_deploy_gh_release
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func) 2>/dev/null || {
  echo -e "${RD}Failed to load tools.func${CL}"
  exit 1
}

if check_for_gh_release "jellystat" "CyferShepard/Jellystat"; then
  msg_info "Stopping service"
  systemctl stop jellystat.service &>/dev/null || true
  msg_ok "Stopped service"

  msg_info "Backing up configuration"
  cp "$CONFIG_PATH" /tmp/jellystat.env.bak 2>/dev/null || true
  msg_ok "Backed up configuration"

  fetch_and_deploy_gh_release "jellystat" "CyferShepard/Jellystat" "tarball" "latest" "$INSTALL_PATH"

  msg_info "Restoring configuration"
  cp /tmp/jellystat.env.bak "$CONFIG_PATH" 2>/dev/null || true
  rm -f /tmp/jellystat.env.bak
  msg_ok "Restored configuration"

  msg_info "Installing dependencies"
  cd "$INSTALL_PATH"
  npm install &>/dev/null
  msg_ok "Installed dependencies"

  msg_info "Building ${APP}"
  npm run build &>/dev/null
  msg_ok "Built ${APP}"

  msg_info "Starting service"
  systemctl start jellystat.service &>/dev/null
  msg_ok "Started service"

  echo ""
  msg_ok "${APP} updated successfully!"
else
  msg_ok "${APP} is already up-to-date"
fi
UPDATEEOF
  chmod +x /usr/local/bin/update_jellystat
  msg_ok "Created update script (/usr/local/bin/update_jellystat)"

  # Save credentials
  local CREDS_FILE="/root/jellystat.creds"
  cat <<EOF >"$CREDS_FILE"
Jellystat Credentials
=====================
Database User: ${DB_USER}
Database Password: ${DB_PASS}
Database Name: ${DB_NAME}
JWT Secret: ${JWT_SECRET}

Web UI: http://${ip}:${DEFAULT_PORT}
EOF
  chmod 600 "$CREDS_FILE"

  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${ip}:${DEFAULT_PORT}${CL}"
  msg_ok "Credentials saved to: ${BL}${CREDS_FILE}${CL}"
  echo ""
  msg_warn "On first access, you'll need to configure your Jellyfin server connection."
}

# ==============================================================================
# MAIN
# ==============================================================================
header_info

IP=$(get_ip)

# Check if already installed
if [[ -d "$INSTALL_PATH" && -f "$INSTALL_PATH/package.json" ]]; then
  msg_warn "${APP} is already installed."
  echo ""

  echo -n "${TAB}Uninstall ${APP}? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall
    exit 0
  fi

  echo -n "${TAB}Update ${APP}? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    update
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

# Fresh installation
msg_warn "${APP} is not installed."
echo ""
echo -e "${TAB}${INFO} This will install:"
echo -e "${TAB}  - Node.js 22"
echo -e "${TAB}  - PostgreSQL 17"
echo -e "${TAB}  - Jellystat"
echo ""

echo -n "${TAB}Install ${APP}? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi

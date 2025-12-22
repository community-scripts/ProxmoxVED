#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: rdeangel
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rdeangel/InstradaOGM

# App Metadata
APP="InstradaOGM"
var_tags="${var_tags:-firewall;management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/instrada-ogm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Get current version
  CURRENT_VERSION="unknown"
  if [[ -f /opt/instrada-ogm/.version ]]; then
    CURRENT_VERSION=$(cat /opt/instrada-ogm/.version)
  elif [[ -f /opt/instrada-ogm/package.json ]]; then
    CURRENT_VERSION="v$(grep '"version"' /opt/instrada-ogm/package.json | head -1 | cut -d'"' -f4)"
  fi

  # Check for latest release
  msg_info "Checking for updates"
  LATEST_RELEASE=$(curl -fsSL https://api.github.com/repos/rdeangel/InstradaOGM/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  
  if [[ -z "$LATEST_RELEASE" ]]; then
    msg_error "Failed to fetch latest release"
    exit 1
  fi

  # Check if already up to date
  if [[ "$CURRENT_VERSION" == "$LATEST_RELEASE" ]]; then
    msg_ok "Already running the latest version ($CURRENT_VERSION)"
    exit 0
  fi

  msg_ok "Update available: $CURRENT_VERSION → $LATEST_RELEASE"

  msg_info "Stopping Service"
  pm2 stop instrada-ogm >/dev/null 2>&1
  msg_ok "Stopped Service"

  # Backup current installation
  msg_info "Creating Backup"
  BACKUP_DIR="/opt/instrada-ogm-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  
  # Use rsync to preserve all timestamps and attributes
  if command -v rsync >/dev/null 2>&1; then
    rsync -a /opt/instrada-ogm/data/ "$BACKUP_DIR/data/" 2>/dev/null || true
    rsync -a /opt/instrada-ogm/.env.production "$BACKUP_DIR/" 2>/dev/null || true
  else
    # Fallback to cp if rsync not available
    cp -rp /opt/instrada-ogm/data "$BACKUP_DIR/" 2>/dev/null || true
    cp -p /opt/instrada-ogm/.env.production "$BACKUP_DIR/" 2>/dev/null || true
  fi
  msg_ok "Backup created at $BACKUP_DIR"

  # Download new release
  msg_info "Downloading ${LATEST_RELEASE}"
  cd /opt
  wget -q "https://github.com/rdeangel/InstradaOGM/archive/refs/tags/${LATEST_RELEASE}.tar.gz"
  
  if [[ ! -f "${LATEST_RELEASE}.tar.gz" ]]; then
    msg_error "Failed to download release"
    exit 1
  fi

  # Extract and replace
  msg_info "Extracting new version"
  tar -xzf "${LATEST_RELEASE}.tar.gz"
  rm "${LATEST_RELEASE}.tar.gz"
  
  # Keep old version as backup
  rm -rf /opt/instrada-ogm.old 2>/dev/null || true
  mv /opt/instrada-ogm /opt/instrada-ogm.old
  mv "InstradaOGM-${LATEST_RELEASE#v}" /opt/instrada-ogm
  cd /opt/instrada-ogm
  msg_ok "New version extracted"

  # Restore data and config BEFORE running npm commands
  msg_info "Restoring Configuration"
  cp -rp "$BACKUP_DIR/data" /opt/instrada-ogm/ 2>/dev/null || true
  cp -p "$BACKUP_DIR/.env.production" /opt/instrada-ogm/ 2>/dev/null || true
  
  # Create .env symlink if it doesn't exist
  if [[ ! -L /opt/instrada-ogm/.env ]]; then
    ln -sf .env.production /opt/instrada-ogm/.env
  fi
  msg_ok "Configuration restored"

  # Source NVM and set up environment
  export NVM_DIR="/root/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  export DATABASE_URL="file:/opt/instrada-ogm/data/db/instrada-ogm.db"
  
  msg_info "Installing Dependencies"
  $STD npm install
  msg_ok "Installed Dependencies"

  msg_info "Switching to SQLite Schema"
  $STD npm run db:switch:sqlite
  msg_ok "Schema switched to SQLite"

  msg_info "Updating Database"
  $STD npm run db:init
  msg_ok "Updated Database"

  msg_info "Rebuilding Application"
  $STD npm run build
  msg_ok "Rebuilt Application"

  # Save version info
  echo "${LATEST_RELEASE}" > /opt/instrada-ogm/.version

  msg_info "Starting Service"
  pm2 restart instrada-ogm >/dev/null 2>&1
  msg_ok "Started Service"

  msg_ok "Updated Successfully to ${LATEST_RELEASE}"
  echo ""
  echo -e "${INFO}${YW} Backup: ${CL}${BACKUP_DIR}"
  echo -e "${INFO}${YW} Old version: ${CL}/opt/instrada-ogm.old (can be deleted)"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"

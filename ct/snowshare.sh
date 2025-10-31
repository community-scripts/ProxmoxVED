#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

#source <(curl -fsSL https://raw.githubusercontent.com/TuroYT/ProxmoxVED/refs/heads/add-snowshare/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: TuroYT
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/TuroYT/snowshare

APP="SnowShare"
var_tags="${var_tags:-file-sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
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
  if [[ ! -d /opt/snowshare ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # S'assurer que jq est installé pour l'analyse de l'API
  if ! command -v jq &> /dev/null; then
    msg_info "Installing 'jq' (required for update check)..."
    apt-get update &>/dev/null
    apt-get install -y jq &>/dev/null
    if ! command -v jq &> /dev/null; then
      msg_error "Failed to install 'jq'. Cannot proceed with update."
      exit 1
    fi
    msg_ok "Installed 'jq'"
  fi

  msg_info "Checking for ${APP} updates..."
  cd /opt/snowshare
  
  # Obtenir le tag local actuel
  CURRENT_TAG=$(git describe --tags 2>/dev/null)
  if [ $? -ne 0 ]; then
    msg_warn "Could not determine current version tag. Fetching latest..."
    CURRENT_TAG="unknown"
  fi
  
  # Obtenir le tag de la dernière release depuis GitHub
  LATEST_TAG=$(curl -s "https://api.github.com/repos/TuroYT/snowshare/releases/latest" | jq -r .tag_name)

  if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
    msg_error "Failed to fetch the latest release tag from GitHub."
    exit 1
  fi
  
  msg_info "Current version: $CURRENT_TAG"
  msg_info "Latest version: $LATEST_TAG"

  if [ "$CURRENT_TAG" == "$LATEST_TAG" ]; then
    msg_ok "${APP} is already up to date."
    exit
  fi

  msg_info "Updating ${APP} to $LATEST_TAG..."
  systemctl stop snowshare
  
  # Récupérer les nouveaux tags
  git fetch --tags
  
  # Se placer sur le dernier tag
  git checkout $LATEST_TAG
  if [ $? -ne 0 ]; then
    msg_error "Failed to checkout tag $LATEST_TAG. Aborting update."
    systemctl start snowshare
    exit 1
  fi
  
  # Relancer les étapes d'installation et de build
  msg_info "Installing dependencies..."
  npm ci
  msg_info "Generating Prisma client..."
  npx prisma generate
  msg_info "Applying database migrations..."
  npx prisma migrate deploy # Important pour les changements de schéma
  msg_info "Building application..."
  npm run build
  
  systemctl start snowshare
  msg_ok "Updated ${APP} to $LATEST_TAG"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"

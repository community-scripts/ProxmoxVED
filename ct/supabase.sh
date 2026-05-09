#!/usr/bin/env bash
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main}"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://supabase.com/ | Github: https://github.com/supabase/supabase

APP="Supabase"
var_tags="${var_tags:-database;backend;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  INSTALL_PATH="/opt/supabase"
  COMPOSE_FILE="${INSTALL_PATH}/docker-compose.yml"
  ENV_FILE="${INSTALL_PATH}/.env"

  if [[ ! -f "$COMPOSE_FILE" || ! -f "$ENV_FILE" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if ! command -v git &>/dev/null || ! command -v rsync &>/dev/null; then
    msg_info "Installing Update Dependencies"
    $STD apt update
    $STD apt install -y git rsync
    msg_ok "Installed Update Dependencies"
  fi

  if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null; then
    DOCKER_SKIP_UPDATES="true" USE_DOCKER_REPO="true" setup_docker
  fi

  msg_info "Creating Backup"
  BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
  cp "$ENV_FILE" "${ENV_FILE}.bak_${BACKUP_STAMP}"
  cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak_${BACKUP_STAMP}"
  msg_ok "Created Backup"

  msg_info "Fetching Latest ${APP} Docker Files"
  TMP_DIR="$(mktemp -d)"
  git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase "$TMP_DIR/supabase" >/dev/null 2>&1
  cd "$TMP_DIR/supabase"
  git sparse-checkout set --cone docker >/dev/null 2>&1
  git checkout master >/dev/null 2>&1
  rsync -a --exclude ".env" --exclude "volumes/" "$TMP_DIR/supabase/docker/." "$INSTALL_PATH/"
  rm -rf "$TMP_DIR"
  msg_ok "Fetched Latest Docker Files"

  msg_info "Restoring Auth Key Configuration"
  sed -i \
    -e '/^[[:space:]]*#GOTRUE_JWT_KEYS:/ s/#//' \
    -e '/^[[:space:]]*#API_JWT_JWKS:/ s/#//' \
    -e '/^[[:space:]]*#JWT_JWKS:/ s/#//' \
    "$COMPOSE_FILE"
  msg_ok "Restored Auth Key Configuration"

  msg_info "Pulling Latest ${APP} Images"
  cd "$INSTALL_PATH"
  $STD docker compose pull
  msg_ok "Pulled Latest Images"

  msg_info "Restarting ${APP}"
  $STD docker compose up -d --remove-orphans
  msg_ok "Restarted ${APP}"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"

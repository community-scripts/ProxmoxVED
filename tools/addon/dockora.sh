#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MarcelRuh
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/MarcelRuh/dockora
if ! command -v curl &>/dev/null; then
  printf "\r\e[2K%b" '\033[93m Setup Source \033[m' >&2
  apt-get update >/dev/null 2>&1
  apt-get install -y curl >/dev/null 2>&1
fi
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func)
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/lib/tools.func)
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/error_handler.func)
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "dockora" "addon"

set -Eeuo pipefail
trap 'error_handler' ERR

APP="Dockora"
APP_TYPE="addon"
INSTALL_PATH="/opt/dockora"
COMPOSE_FILE="${INSTALL_PATH}/docker-compose.yml"
ENV_FILE="${INSTALL_PATH}/.env"
REPO="MarcelRuh/dockora"
DEFAULT_PORT=8080

load_functions

function header_info {
  clear
  cat <<"EOF"
    ____             __
   / __ \____  _____/ /______  _________ _
  / / / / __ \/ ___/ //_/ __ \/ ___/ __ `/
 / /_/ / /_/ / /__/ ,< / /_/ / /  / /_/ /
/_____/\____/\___/_/|_|\____/_/   \__,_/

EOF
}

function check_docker() {
  if ! command -v docker &>/dev/null; then
    msg_error "Docker is not installed. Run this addon inside an existing Docker LXC. Exiting."
    exit 10
  fi
  if ! docker compose version &>/dev/null; then
    msg_error "Docker Compose plugin is not available. Install it before running this script. Exiting."
    exit 10
  fi
  msg_ok "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') and Docker Compose are available"
}

function set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
  fi
}

function deploy_release() {
  if declare -f fetch_and_deploy_gh_release >/dev/null; then
    fetch_and_deploy_gh_release "dockora" "$REPO" "tarball" "latest" "$INSTALL_PATH"
  else
    local tmp archive src
    tmp="$(mktemp -d)"
    archive="${tmp}/dockora.tar.gz"
    curl -fsSL "https://github.com/${REPO}/archive/refs/heads/main.tar.gz" -o "$archive"
    tar -xzf "$archive" -C "$tmp"
    src="$(find "$tmp" -maxdepth 1 -type d -name 'dockora-*' | head -1)"
    mkdir -p "$INSTALL_PATH"
    shopt -s dotglob
    cp -a "$src"/. "$INSTALL_PATH"/
    shopt -u dotglob
    rm -rf "$tmp"
  fi
  chmod +x "${INSTALL_PATH}/scripts/"*.sh 2>/dev/null || true
}

function uninstall() {
  msg_info "Uninstalling ${APP}"
  if [[ -f "$COMPOSE_FILE" ]]; then
    cd "$INSTALL_PATH"
    $STD docker compose -f docker-compose.yml -f docker-compose.images.yml --profile proxy down --volumes --remove-orphans
  fi
  rm -rf "$INSTALL_PATH"
  rm -f /usr/local/bin/update_dockora
  msg_ok "${APP} has been uninstalled"
}

function update() {
  check_docker
  if [[ ! -f "$ENV_FILE" ]]; then
    msg_error "No ${APP} installation found!"
    exit 233
  fi

  local env_backup
  env_backup="$(mktemp)"
  cp "$ENV_FILE" "$env_backup"

  if declare -f check_for_gh_release >/dev/null && check_for_gh_release "dockora" "$REPO"; then
    CLEAN_INSTALL=1 deploy_release
    mv "$env_backup" "$ENV_FILE"
  else
    rm -f "$env_backup"
  fi

  msg_info "Pulling latest ${APP} images"
  cd "$INSTALL_PATH"
  $STD docker compose -f docker-compose.yml -f docker-compose.images.yml --profile proxy pull
  msg_ok "Pulled latest images"

  msg_info "Restarting ${APP}"
  $STD docker compose -f docker-compose.yml -f docker-compose.images.yml --profile proxy up -d --remove-orphans
  msg_ok "Restarted ${APP}"
  msg_ok "Updated successfully"
  exit
}

function install() {
  local port="${1:-$DEFAULT_PORT}"
  check_docker

  msg_info "Deploying ${APP}"
  mkdir -p "$INSTALL_PATH"
  deploy_release
  msg_ok "Deployed ${APP} to ${INSTALL_PATH}"

  if [[ ! -f "${INSTALL_PATH}/.env.example" ]]; then
    msg_error "Release is missing .env.example"
    exit 1
  fi

  local jwt_secret admin_pass docker_gid
  jwt_secret="$(openssl rand -hex 32)"
  admin_pass="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)"
  docker_gid="$(getent group docker 2>/dev/null | cut -d: -f3 || true)"
  docker_gid="${docker_gid:-999}"

  msg_info "Writing configuration"
  cp "${INSTALL_PATH}/.env.example" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  set_env JWT_SECRET "$jwt_secret"
  set_env BOOTSTRAP_ADMIN_EMAIL "admin@dockora.local"
  set_env BOOTSTRAP_ADMIN_PASSWORD "$admin_pass"
  set_env DOCKER_GID "$docker_gid"
  set_env DOCKORA_INSTALL_DIR "$INSTALL_PATH"
  set_env DOCKORA_REPO "$REPO"
  set_env DOCKORA_UPDATE_BRANCH "main"
  set_env DOCKORA_IMAGE_TAG "latest"
  set_env DOCKORA_PROXY_PORT "$port"
  set_env CORS_ORIGIN "http://${LOCAL_IP}:${port}"
  msg_ok "Wrote ${ENV_FILE}"

  msg_info "Starting ${APP}"
  cd "$INSTALL_PATH"
  $STD docker compose -f docker-compose.yml -f docker-compose.images.yml --profile proxy up -d
  msg_ok "Started ${APP}"

  msg_info "Creating update script"
  cat <<'UPDATEEOF' >/usr/local/bin/update_dockora
#!/usr/bin/env bash
type=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/addon/dockora.sh)"
UPDATEEOF
  chmod +x /usr/local/bin/update_dockora
  msg_ok "Created update script (/usr/local/bin/update_dockora)"

  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:${port}${CL}"
  echo ""
  echo -e "Dockora Credentials"
  echo -e "==================="
  echo -e "Email:    admin@dockora.local"
  echo -e "Password: ${admin_pass}"
  echo -e "Config:   ${ENV_FILE}"
  echo ""
  msg_warn "Save the password now – it is not shown again."
}

if [[ "${type:-}" == "update" ]]; then
  header_info
  if [[ -f "$COMPOSE_FILE" ]]; then
    update
  else
    msg_error "${APP} is not installed. Nothing to update."
    exit 233
  fi
  exit 0
fi

header_info
get_lxc_ip

if [[ -f "$COMPOSE_FILE" && -f "$ENV_FILE" ]]; then
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

msg_warn "${APP} is not installed."
echo ""
echo -e "${TAB}${INFO} This addon installs Dockora on an existing Docker LXC (GHCR images + Compose)."
echo -e "${TAB}${INFO} UI is served via the nginx same-origin proxy."
echo ""

echo -n "${TAB}UI port [${DEFAULT_PORT}]: "
read -r port_input
PORT="${port_input:-$DEFAULT_PORT}"

echo -n "${TAB}Install ${APP}? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install "$PORT"
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi

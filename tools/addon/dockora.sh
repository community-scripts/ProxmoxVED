#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MarcelRuh
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/MarcelRuh/dockora

if ! command -v curl &>/dev/null; then
  printf "\r\e[2K%b" '\033[93m Setup Source \033[m' >&2
  if [[ -f /etc/alpine-release ]]; then
    apk update >/dev/null 2>&1
    apk add --no-cache curl >/dev/null 2>&1
  else
    apt-get update >/dev/null 2>&1
    apt-get install -y curl >/dev/null 2>&1
  fi
fi
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func)
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/lib/tools.func)
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/error_handler.func)
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "dockora" "addon"

# Enable error handling
set -Eeuo pipefail
trap 'error_handler' ERR
load_functions

# ==============================================================================
# CONFIGURATION
# ==============================================================================
VERBOSE=${var_verbose:-no}
APP="Dockora"
APP_TYPE="addon"
INSTALL_PATH="/opt/dockora"
COMPOSE_FILE="${INSTALL_PATH}/docker-compose.yml"
ENV_FILE="${INSTALL_PATH}/.env"
REPO="MarcelRuh/dockora"
DEFAULT_PORT=8080
CREDS_FILE="/root/dockora.creds"

# ==============================================================================
# HEADER
# ==============================================================================
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

# ==============================================================================
# OS DETECTION
# ==============================================================================
if [[ -f "/etc/alpine-release" ]]; then
  msg_error "Alpine is not supported for ${APP}. Use a Debian/Ubuntu Docker LXC."
  exit 238
elif grep -qE 'ID=debian|ID=ubuntu' /etc/os-release 2>/dev/null; then
  OS="Debian"
else
  echo -e "${CROSS} Unsupported OS detected. Exiting."
  exit 238
fi

# ==============================================================================
# HELPERS
# ==============================================================================
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

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall() {
  msg_info "Uninstalling ${APP}"
  if [[ -f "$COMPOSE_FILE" ]]; then
    cd "$INSTALL_PATH"
    $STD docker compose -f docker-compose.yml -f docker-compose.images.yml --profile proxy down --volumes --remove-orphans
  fi
  rm -rf "$INSTALL_PATH"
  rm -f /usr/local/bin/update_dockora
  rm -f "$HOME/.dockora"
  rm -f "$CREDS_FILE"
  msg_ok "${APP} has been uninstalled"
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update() {
  check_docker
  if [[ ! -f "$ENV_FILE" ]]; then
    msg_error "No ${APP} installation found!"
    exit 233
  fi

  if check_for_gh_release "dockora" "$REPO"; then
    msg_info "Backing up configuration"
    cp "$ENV_FILE" /tmp/dockora.env.bak
    msg_ok "Backed up configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "dockora" "$REPO" "tarball" "latest" "$INSTALL_PATH"
    chmod +x "${INSTALL_PATH}/scripts/"*.sh 2>/dev/null || true

    msg_info "Restoring configuration"
    mv /tmp/dockora.env.bak "$ENV_FILE"
    msg_ok "Restored configuration"
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

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  local port="${1:-$DEFAULT_PORT}"
  check_docker

  fetch_and_deploy_gh_release "dockora" "$REPO" "tarball" "latest" "$INSTALL_PATH"
  chmod +x "${INSTALL_PATH}/scripts/"*.sh 2>/dev/null || true

  if [[ ! -f "${INSTALL_PATH}/.env.example" ]]; then
    msg_error "Release is missing .env.example"
    exit 1
  fi

  local jwt_secret admin_pass docker_gid
  jwt_secret="$(openssl rand -hex 32)"
  admin_pass="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)"
  docker_gid="$(getent group docker 2>/dev/null | cut -d: -f3 || true)"
  docker_gid="${docker_gid:-999}"

  msg_info "Creating configuration"
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
  msg_ok "Created configuration"

  msg_info "Starting ${APP}"
  cd "$INSTALL_PATH"
  $STD docker compose -f docker-compose.yml -f docker-compose.images.yml --profile proxy up -d
  msg_ok "Started ${APP}"

  msg_info "Creating update script"
  declare -f ensure_usr_local_bin_persist &>/dev/null && ensure_usr_local_bin_persist
  cat <<'UPDATEEOF' >/usr/local/bin/update_dockora
#!/usr/bin/env bash
# Dockora Update Script
type=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/addon/dockora.sh)"
UPDATEEOF
  chmod +x /usr/local/bin/update_dockora
  msg_ok "Created update script (/usr/local/bin/update_dockora)"

  cat <<EOF >"$CREDS_FILE"
Dockora Credentials
===================
Email:    admin@dockora.local
Password: ${admin_pass}

Web UI: http://${LOCAL_IP}:${port}
Config: ${ENV_FILE}
EOF
  chmod 600 "$CREDS_FILE"

  echo ""
  msg_ok "${APP} installed successfully"
  msg_ok "UI: ${BL}http://${LOCAL_IP}:${port}${CL}"
  msg_ok "Credentials saved to: ${BL}${CREDS_FILE}${CL}"
  echo ""
  msg_warn "Save the password now – it is not shown again."
}

# ==============================================================================
# MAIN
# ==============================================================================
header_info
declare -f ensure_usr_local_bin_persist &>/dev/null && ensure_usr_local_bin_persist
get_lxc_ip

# Handle type=update (called from update script)
if [[ "${type:-}" == "update" ]]; then
  if [[ -f "$COMPOSE_FILE" ]]; then
    update
  else
    msg_error "${APP} is not installed. Nothing to update."
    exit 233
  fi
  exit 0
fi

# Check if already installed
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

# Fresh installation
msg_warn "${APP} is not installed."
echo ""
echo -e "${TAB}${INFO} This will install:"
echo -e "${TAB}  - Dockora (GitHub release + GHCR images)"
echo -e "${TAB}  - nginx same-origin proxy (SSE/WebSocket)"
echo -e "${TAB}${INFO} Requires an existing Docker LXC (Engine + Compose v2)."
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

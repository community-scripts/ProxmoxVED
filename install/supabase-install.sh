#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://supabase.com/ | Github: https://github.com/supabase/supabase

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP="Supabase"
INSTALL_PATH="/opt/supabase"

function set_env_var() {
  local key="$1"
  local value="$2"

  sed -i "s|^${key}=.*|${key}=${value}|" "$INSTALL_PATH/.env"
}

function read_env_var() {
  local key="$1"

  sed -n "s|^${key}=||p" "$INSTALL_PATH/.env" | head -n1
}

function enable_new_auth_keys() {
  sed -i \
    -e '/^[[:space:]]*#GOTRUE_JWT_KEYS:/ s/#//' \
    -e '/^[[:space:]]*#API_JWT_JWKS:/ s/#//' \
    -e '/^[[:space:]]*#JWT_JWKS:/ s/#//' \
    "$INSTALL_PATH/docker-compose.yml"
}

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  openssl \
  rsync
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
DOCKER_SKIP_UPDATES="true" USE_DOCKER_REPO="true" setup_docker

msg_info "Fetching ${APP} Docker Files"
TMP_DIR="$(mktemp -d)"
git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase "$TMP_DIR/supabase" >/dev/null 2>&1
cd "$TMP_DIR/supabase"
git sparse-checkout set --cone docker >/dev/null 2>&1
git checkout master >/dev/null 2>&1
mkdir -p "$INSTALL_PATH"
cp -a "$TMP_DIR/supabase/docker/." "$INSTALL_PATH/"
rm -rf "$TMP_DIR"
msg_ok "Fetched ${APP} Docker Files"

msg_info "Configuring ${APP}"
cp "$INSTALL_PATH/.env.example" "$INSTALL_PATH/.env"
cd "$INSTALL_PATH"
$STD sh utils/generate-keys.sh --update-env
$STD sh utils/add-new-auth-keys.sh --update-env
set_env_var "DASHBOARD_PASSWORD" "supa$(openssl rand -hex 14)"
set_env_var "SUPABASE_PUBLIC_URL" "http://${LOCAL_IP}:8000"
set_env_var "API_EXTERNAL_URL" "http://${LOCAL_IP}:8000"
set_env_var "SITE_URL" "http://${LOCAL_IP}:3000"
set_env_var "POOLER_TENANT_ID" "supabase$(openssl rand -hex 4)"
set_env_var "OPENAI_API_KEY" ""
enable_new_auth_keys
chmod 600 "$INSTALL_PATH/.env"
msg_ok "Configured ${APP}"

msg_info "Pulling ${APP} Images"
cd "$INSTALL_PATH"
$STD docker compose pull
msg_ok "Pulled ${APP} Images"

msg_info "Starting ${APP}"
$STD docker compose up -d
msg_ok "Started ${APP}"

echo ""
msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:8000${CL}"
echo -e "${INFO}${YW} Dashboard credentials:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Username: $(read_env_var "DASHBOARD_USERNAME")${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Password: $(read_env_var "DASHBOARD_PASSWORD")${CL}"
echo -e "${INFO}${YW} Supabase keys and database credentials are stored in:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${INSTALL_PATH}/.env${CL}"

motd_ssh
customize
cleanup_lxc

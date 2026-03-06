#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tumeden
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Maintainerr/Maintainerr

APP="Maintainerr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-18}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function build_maintainerr() {
  NODE_VERSION="24" setup_nodejs
  msg_info "Preparing Build Runtime"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  $STD corepack enable
  if [[ -f /opt/maintainerr/package.json ]]; then
    if command -v jq >/dev/null 2>&1; then
      yarn_spec=$(jq -r '.packageManager // empty' /opt/maintainerr/package.json 2>/dev/null || true)
      if [[ -n "$yarn_spec" && "$yarn_spec" == yarn@* ]]; then
        yarn_ver="${yarn_spec#yarn@}"
        yarn_ver="${yarn_ver%%+*}"
        $STD corepack prepare "yarn@${yarn_ver}" --activate || true
      fi
    fi
  fi
  msg_ok "Prepared Build Runtime"

  msg_info "Building Maintainerr (Patience)"
  cd /opt/maintainerr || { msg_error "Failed to change to /opt/maintainerr"; return 1; }
  cat <<'EOF' >/opt/maintainerr/apps/ui/.env
VITE_BASE_PATH=/__PATH_PREFIX__
EOF
  export NODE_OPTIONS="--max-old-space-size=4096"
  $STD yarn install --immutable --network-timeout 99999999
  $STD yarn turbo build
  $STD yarn workspaces focus --all --production
  mkdir -p /opt/maintainerr/apps/server/dist/ui
  cp -a /opt/maintainerr/apps/ui/dist/. /opt/maintainerr/apps/server/dist/ui/
  ln -sfnT /opt/maintainerr /opt/app
  msg_ok "Built Maintainerr"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/maintainerr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if check_for_gh_release "maintainerr" "Maintainerr/Maintainerr"; then
    msg_info "Stopping Service"
    systemctl stop maintainerr
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "maintainerr" "Maintainerr/Maintainerr" "tarball" "latest" "/opt/maintainerr"
    build_maintainerr

    msg_info "Starting Service"
    systemctl daemon-reload
    systemctl start maintainerr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6246${CL}"

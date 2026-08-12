#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://castopod.org/

APP="Castopod"
var_tags="${var_tags:-podcast;media;fediverse}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2028}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/castopod/spark ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if GITLAB_URL="https://code.castopod.org" check_for_gl_release "castopod" "adaures/castopod"; then
    msg_info "Stopping Service"
    systemctl stop caddy
    msg_ok "Stopped Service"

    create_backup /opt/castopod/.env \
      /opt/castopod/public/media \
      /opt/castopod/writable

    CLEAN_INSTALL=1 GITLAB_URL="https://code.castopod.org" fetch_and_deploy_gl_release "castopod" "adaures/castopod" "prebuild" "latest" "/opt/castopod" "castopod-*.tar.gz"

    restore_backup

    msg_info "Updating Application"
    cd /opt/castopod
    mkdir -p public/media writable
    chown -R www-data:www-data /opt/castopod/public/media /opt/castopod/writable
    $STD php spark castopod:database-update
    msg_ok "Updated Application"

    msg_info "Starting Service"
    systemctl start caddy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"

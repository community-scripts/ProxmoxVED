#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://mailpit.axllent.org/

APP="Mailpit"
var_tags="${var_tags:-smtp;email;testing;development}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2025}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/mailpit/mailpit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "mailpit" "axllent/mailpit"; then
    msg_info "Stopping Service"
    systemctl stop mailpit
    msg_ok "Stopped Service"

    create_backup /opt/mailpit/.env \
      /opt/mailpit/data

    fetch_and_deploy_gh_release "mailpit" "axllent/mailpit" "prebuild" "latest" "/opt/mailpit" "mailpit-linux-$(arch_resolve).tar.gz"

    restore_backup

    msg_info "Starting Service"
    systemctl start mailpit
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
echo -e "${GATEWAY}${BGN}http://${IP}:8025${CL}"

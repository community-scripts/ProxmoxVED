#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: SavageCore
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/https://github.com/vogler/free-games-claimer
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="free-games-claimer"
var_tags="${var_tags:-automation;gaming}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
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

  if [[ ! -d /opt/free-games-claimer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  fetch_and_deploy_gh_release "free-games-claimer" "vogler/free-games-claimer" "tarball"
  $STD npm install

  PATCHRIGHT_VERSION=$(npm list patchright | grep patchright@ | awk -F@ '{print $2}' | tr -d ' ')
  REQUIRED_VERSION="1.55.0"
  if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PATCHRIGHT_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    msg_info "Updating patchright to version ${REQUIRED_VERSION} or higher"
    $STD npm install patchright@latest
    msg_ok "Updated patchright to version $(npm list patchright | grep patchright@ | awk -F@ '{print $2}' | tr -d ' ')"
  else
    msg_ok "patchright version ${PATCHRIGHT_VERSION} meets the requirement"
  fi

  msg_ok "Updated ${APP}"

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6080${CL}"

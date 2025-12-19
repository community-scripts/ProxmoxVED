#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: SavageCore
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/https://github.com/vogler/free-games-claimer
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="free-games-claimer"
var_tags="automation;gaming"
var_cpu="${var_cpu:-4}"
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
  cd /opt/free-games-claimer || exit
  $STD git pull
  $STD npm install

  # If Debian 13, ensure `patchright` npm package is 1.55 or higher.
  if grep -q 'Debian GNU/Linux 13' /etc/os-release
  then
    PATCHRIGHT_VERSION=$(npm list patchright | grep patchright@ | awk -F@ '{print $2}' | tr -d ' ')
    REQUIRED_VERSION="1.55.0"
    if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PATCHRIGHT_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
      msg_info "Updating patchright to version ${REQUIRED_VERSION} or higher"
      $STD npm install patchright@latest
      msg_ok "Updated patchright to version $(npm list patchright | grep patchright@ | awk -F@ '{print $2}' | tr -d ' ')"
    else
      msg_ok "patchright version ${PATCHRIGHT_VERSION} meets the requirement"
    fi
  fi

  msg_ok "Updated ${APP}"

  exit
}

start
build_container
description

# Display success message
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully completed!${CL}"
echo -e "${INFO}${YW}Next you need to configure your credentials by editing the config file located at:${CL}"
echo -e "${INFO}${YW}/opt/free-games-claimer/data/config.env${CL}"
echo -e "${INFO}${YW}After that you can start with the following command:${CL}\n"
echo -e "${TAB}${BOLD}systemctl start free-games-claimer${CL}"
echo -e "${INFO}${YW} When running you can access VNC to watch the browser using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6080${CL}"
echo -e "${INFO}${YW} There's a cron job set-up to run the claimer every day at 18:30.${CL}"

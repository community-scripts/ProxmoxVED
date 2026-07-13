#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Simon Bach Jessen (bachjessen)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.sprout-track.com/ | Github: https://github.com/Oak-and-Sprout/sprout-track

APP="Sprout-Track"
var_tags="${var_tags:-tracking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/sprout-track ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "sprout-track" "Oak-and-Sprout/sprout-track"; then
    create_backup \
      /opt/sprout-track/.env \
      /opt/sprout-track/db \
      /opt/sprout-track/env \
      /opt/sprout-track/Files

    msg_info "Stopping Service"
    systemctl stop sprout-track
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release \
      "sprout-track" \
      "Oak-and-Sprout/sprout-track" \
      "tarball"

    restore_backup

    msg_info "Updating Sprout Track"
    cd /opt/sprout-track || exit
    chmod +x scripts/*.sh ./*.sh 2>/dev/null || true
    $STD ./scripts/env-update.sh
    $STD npm install
    $STD npm run prisma:generate
    $STD npm run prisma:generate:log
    $STD npm run prisma:deploy
    $STD npm run prisma:push:log
    $STD npm run build
    msg_ok "Updated Sprout Track"

    msg_info "Starting Service"
    systemctl start sprout-track
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
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"

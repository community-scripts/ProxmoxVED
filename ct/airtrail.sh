#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Majiiin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/johanohly/AirTrail

APP="AirTrail"
var_tags="${var_tags:-travel;flight-tracker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/airtrail ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" setup_nodejs

  msg_info "Updating Bun"
  export BUN_INSTALL="/root/.bun"
  curl -fsSL https://bun.com/install | $STD bash
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx
  msg_ok "Updated Bun"

  if check_for_gh_release "airtrail" "johanohly/AirTrail"; then
    msg_info "Backing Up Database"
    mkdir -p /var/lib/airtrail/backups
    backup_file="/var/lib/airtrail/backups/airtrail-$(date +%Y%m%d-%H%M%S).sql"
    sudo -u postgres pg_dump airtrail | tee "$backup_file" >/dev/null
    find /var/lib/airtrail/backups \
      -type f \
      -name 'airtrail-*.sql' \
      -mtime +14 \
      -delete
    msg_ok "Backed Up Database"

    systemctl stop airtrail

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release \
      "airtrail" \
      "johanohly/AirTrail" \
      "tarball"

    msg_info "Building AirTrail"
    cd /opt/airtrail
    $STD bun install --frozen-lockfile
    $STD bun run build
    rm -rf /opt/airtrail/node_modules
    $STD bun install --frozen-lockfile --production
    msg_ok "Built AirTrail"

    msg_info "Applying Database Migrations"
    set -a
    source /etc/airtrail/airtrail.env
    set +a
    $STD node /opt/airtrail/docker/migrate.js
    msg_ok "Applied Database Migrations"

    systemctl start airtrail
    msg_ok "Updated successfully!"
  fi

  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"

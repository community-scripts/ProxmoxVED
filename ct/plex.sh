#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.plex.tv/

APP="Plex"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

    if [[ -f /etc/apt/sources.list.d/plexmediaserver.list ]]; then
    msg_info "Migrating Plex repository to Deb822 format"
    rm -f /etc/apt/sources.list.d/plexmediaserver.list
    curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.key | tee /usr/share/keyrings/PlexSign.asc >/dev/null
    cat <<EOF >/etc/apt/sources.list.d/plexmediaserver.sources
Types: deb
URIs: https://downloads.plex.tv/repo/deb/
Suites: public
Components: main
Signed-By: /usr/share/keyrings/PlexSign.asc
EOF
    msg_ok "Migrated Plex repository to Deb822"
  fi

  if [[ ! -f /etc/apt/sources.list.d/plexmediaserver.sources ]]; then
    msg_error "No ${APP} repository found!"
    exit 1
  fi

  msg_info "Updating ${APP}"
  $STD apt update
  $STD apt -y -o Dpkg::Options::="--force-confold" upgrade plexmediaserver
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:32400/web${CL}"

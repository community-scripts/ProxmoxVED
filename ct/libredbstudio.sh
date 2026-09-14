#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Yusuf Gundogdu (yusuf-gundogdu)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://libredb.org

APP="LibreDB Studio"
var_tags="${var_tags:-database;sql}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2261}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/bin/libredb-studio ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "libredb-studio" "libredb/libredb-studio"; then
    # An empty architecture would widen the asset pattern below and the engine
    # would fall back to the first .deb in the release, which is the desktop
    # package. Resolve it first and stop here instead.
    ARCH="$(arch_resolve)" || {
      msg_error "Could not resolve the container architecture"
      exit 1
    }

    msg_info "Stopping Service"
    systemctl stop libredb-studio
    msg_ok "Stopped Service"

    # The env file holds the only copy of the generated JWT secret and admin
    # password. It is a dpkg conffile, so an upgrade keeps it, but a future
    # package claiming that path would not.
    create_backup /etc/libredb-studio/env

    # The release carries two .deb files per architecture: the server package
    # and libredb-studio-desktop. Without this pattern the desktop package
    # sorts first and gets installed instead.
    # The package ships /etc/libredb-studio/env as a conffile and the install
    # script rewrote it, so keep the local copy on upgrade.
    if ! DPKG_FORCE_CONFOLD=1 fetch_and_deploy_gh_release "libredb-studio" \
      "libredb/libredb-studio" "binary" "latest" "" "libredb-studio_*_${ARCH}.deb"; then
      restore_backup
      msg_error "Update failed, starting the previous version again"
      systemctl start libredb-studio
      exit 1
    fi
    if [[ ! -x /usr/bin/libredb-studio ]] ||
      [[ ! -f /usr/lib/systemd/system/libredb-studio.service ]]; then
      restore_backup
      msg_error "The installed package is not the server build"
      exit 1
    fi
    restore_backup

    msg_info "Starting Service"
    systemctl start libredb-studio
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
echo -e "${INFO}${YW}Admin credentials: /etc/libredb-studio/env inside the container${CL}"

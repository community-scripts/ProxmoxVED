#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Bardesss
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bardesss/haelan

APP="Haelan"
var_tags="${var_tags:-health;dashboard;self-hosted}"
var_cpu="${var_cpu:-2}"
# The build is what sets this, not the running instance: vite bundles the web app inside the
# container. Idle afterwards is a couple of hundred megabytes.
var_ram="${var_ram:-4096}"
# About 120 MB of database per person-year, and the default seven daily backups are seven more
# copies of it, so the data alone reaches a couple of gigabytes before the node_modules tree.
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2263}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/haelan ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "haelan" "bardesss/haelan"; then
    msg_info "Stopping Service"
    systemctl stop haelan
    msg_ok "Stopped Service"

    # No create_backup: /opt/haelan holds nothing but code. The database, the encryption key and
    # the backups are in /opt/haelan_data, which the clean re-deploy below does not touch, and
    # copying a multi-gigabyte database on every update would be a real cost for no gain.
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "haelan" "bardesss/haelan" "tarball"

    PNPM_VERSION=$(sed -n 's/.*"packageManager": "pnpm@\([^"+]*\).*/\1/p' /opt/haelan/package.json)
    NODE_VERSION="24" NODE_MODULE="pnpm@${PNPM_VERSION:-11.22.0}" setup_nodejs

    msg_info "Building Haelan"
    cd /opt/haelan
    $STD pnpm install --frozen-lockfile
    $STD pnpm build
    msg_ok "Built Haelan"

    msg_info "Starting Service"
    systemctl start haelan
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4235${CL}"

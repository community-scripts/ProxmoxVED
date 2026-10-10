#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main"

_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Christian Meier (cm2962)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ep1cman/unifi-protect-backup

APP="UniFi-Protect-Backup"
var_tags="${var_tags:-backup;camera}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset until the bare-metal install has been verified on arm64
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2284}"

export var_ufp_address="${var_ufp_address:-}"
export var_ufp_username="${var_ufp_username:-}"
export var_ufp_password="${var_ufp_password:-}"
export var_ufp_ssl_verify="${var_ufp_ssl_verify:-false}"
export var_rclone_retention="${var_rclone_retention:-}"
export var_missing_range="${var_missing_range:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/unifi-protect-backup ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "unifi-protect-backup" "ep1cman/unifi-protect-backup"; then
    msg_info "Stopping UniFi Protect Backup"
    systemctl stop unifi-protect-backup
    msg_ok "Stopped UniFi Protect Backup"

    create_backup /opt/unifi-protect-backup/.env /opt/unifi-protect-backup/config

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "unifi-protect-backup" "ep1cman/unifi-protect-backup" "tarball"

    restore_backup

    msg_info "Installing UniFi Protect Backup"
    cd /opt/unifi-protect-backup
    $STD uv sync --locked --no-editable
    msg_ok "Installed UniFi Protect Backup"

    msg_info "Starting UniFi Protect Backup"
    systemctl start unifi-protect-backup
    msg_ok "Started UniFi Protect Backup"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Configuration: /opt/unifi-protect-backup/.env${CL}"
echo -e "${INFO}${YW}Configure cloud storage with: rclone --config /opt/unifi-protect-backup/config/rclone/rclone.conf config${CL}"
echo -e "${INFO}${YW}Use Advanced Install to choose a container disk size other than the 4 GB default.${CL}"

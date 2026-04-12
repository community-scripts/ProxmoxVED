#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 Themearr ORG
# Author: Themearr
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Themearr/themearr

# ============================================================================
# APP CONFIGURATION
# ============================================================================

APP="Themearr"
var_tags="${var_tags:-arr;media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# ============================================================================
# INITIALIZATION
# ============================================================================
header_info "$APP"
variables
color
catch_errors

# ============================================================================
# UPDATE SCRIPT
# ============================================================================

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Step 1: Verify installation exists
  if [[ ! -d /opt/themearr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Step 2: Check if update is available
  if check_for_gh_release "themearr" "Themearr/themearr"; then

    # Step 3: Stop service
    msg_info "Stopping Service"
    systemctl stop themearr
    msg_ok "Stopped Service"

    # Step 4: Backup data
    msg_info "Backing up Data"
    cp -r /opt/themearr/data /opt/themearr_data_backup
    msg_ok "Backed up Data"

    # Step 5: Download and deploy new pre-built release
    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64)  ARCH_SUFFIX="linux-x64" ;;
      aarch64) ARCH_SUFFIX="linux-arm64" ;;
    esac
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "themearr" "Themearr/themearr" "prebuild" "latest" "/opt/themearr" "themearr-${ARCH_SUFFIX}.tar.gz"

    # Step 6: Restore data
    msg_info "Restoring Data"
    cp -r /opt/themearr_data_backup/. /opt/themearr/data
    rm -rf /opt/themearr_data_backup
    msg_ok "Restored Data"

    # Step 7: Restart service
    msg_info "Starting Service"
    systemctl start themearr
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

start
build_container
description

# ============================================================================
# COMPLETION MESSAGE
# ============================================================================
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialised!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"

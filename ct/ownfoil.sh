#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: pajjski
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE 
# Source: https://github.com/a1ex4/ownfoil 

# ============================================================================
# APP CONFIGURATION
# ============================================================================
# These values are sent to build.func and define default container resources.
# Users can customize these during installation via the interactive prompts.
# ============================================================================

APP="ownfoil"
var_tags="${var_tags:-gaming}" # Max 2 tags, semicolon-separated
var_cpu="${var_cpu:-1}"                         # CPU cores: 1-4 typical
var_ram="${var_ram:-1024}"                      # RAM in MB: 512, 1024, 2048, etc.
var_disk="${var_disk:-4}"                       # Disk in GB: 6, 8, 10, 20 typical
var_os="${var_os:-debian}"                      # OS: debian, ubuntu, alpine
var_version="${var_version:-13}"                # OS Version: 13 (Debian), 24.04 (Ubuntu), 3.21 (Alpine)
var_unprivileged="${var_unprivileged:-1}"       # 1=unprivileged (secure), 0=privileged (for Docker/Podman)

# ============================================================================
# INITIALIZATION - These are required in all CT scripts
# ============================================================================
header_info "$APP" # Display app name and setup header
variables          # Initialize build.func variables
color              # Load color variables for output
catch_errors       # Enable error handling with automatic exit on failure

# ============================================================================
# UPDATE SCRIPT - Called when user selects "Update" from web interface
# ============================================================================

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Step 1: Verify installation exists
  if [[ ! -d /opt/ownfoil ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Step 2: Check if update is available
  if check_for_gh_release "ownfoil" "a1ex4/ownfoil"; then

    # Step 3: Stop services before update
    msg_info "Stopping Service"
    systemctl stop ownfoil
    msg_ok "Stopped Service"

    # Step 4: Backup critical data before overwriting
    msg_info "Backing up Data"
    cp -r /opt/ownfoil/app/config /opt/ownfoil_data_backup 2>/dev/null || true
    msg_ok "Backed up Data"

    # Step 5: Download and deploy new version
    fetch_and_deploy_gh_release "ownfoil" "a1ex4/ownfoil" "tarball" "latest" "/opt/ownfoil"

    #6: Run post-update commands 
    msg_info "Installing Dependencies"
    cd /opt/ownfoil
    $STD source .venv/bin/activate
    $STD uv pip install -r requirements.txt 
    msg_ok "Installed Dependencies"
  
    # Step 7: Restore data from backup
    msg_info "Restoring Data"
    cp -r /opt/ownfoil_data_backup /opt/ownfoil/app/config 2>/dev/null || true
    rm -rf /opt/ownfoil_data_backup
    msg_ok "Restored Data"

    # Step 8: Restart service with new version
    msg_info "Starting Service"
    systemctl start ownfoil
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# Step 8: Healthcheck!
function health_check() {
  header_info

  if [[ ! -d /opt/ownfoil ]]; then
    msg_error "Application not found!"
    exit 1
  fi

  if ! systemctl is-active --quiet ownfoil; then
    msg_error "Application service not running"
    exit 1
  fi

  msg_ok "Health check passed"
}

# ============================================================================
# MAIN EXECUTION - Container creation flow
# ============================================================================

start
build_container
description

# ============================================================================
# COMPLETION MESSAGE
# ============================================================================
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8465${CL}"

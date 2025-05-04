#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: rcourtman
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rcourtman/Pulse

# App Default Values
APP="Pulse"
var_tags="monitoring;nodejs"
var_cpu="1"
var_ram="1024"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    # Check if installation is present
    if [[ ! -d /opt/pulse-proxmox/.git ]]; then
        msg_error "No ${APP} Installation Found! Cannot check/update via git."
        exit 1
    fi

    # Check if jq is installed (needed for version parsing)
    if ! command -v jq &> /dev/null; then
        msg_error "jq is required for version checking but not installed. Please install it (apt-get install jq)."
        exit 1
    fi

    # Crawling the new version and checking whether an update is required
    msg_info "Checking for ${APP} updates..."
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/rcourtman/Pulse/releases/latest | jq -r '.tag_name')
    if [[ $? -ne 0 ]] || [[ -z "$LATEST_RELEASE" ]] || [[ "$LATEST_RELEASE" == "null" ]]; then
        msg_error "Failed to fetch latest release information from GitHub API."
        exit 1
    fi
    msg_ok "Latest available version: ${LATEST_RELEASE}"

    CURRENT_VERSION=""
    if [[ -f /opt/${APP}_version.txt ]]; then
      CURRENT_VERSION=$(cat /opt/${APP}_version.txt)
    else
      msg_warning "Version file /opt/${APP}_version.txt not found. Cannot determine current version. Will attempt update."
    fi

    if [[ "${LATEST_RELEASE}" != "$CURRENT_VERSION" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
        msg_info "Updating ${APP} to ${LATEST_RELEASE}..."

        # Stopping Service
        msg_info "Stopping ${APP} service..."
        systemctl stop pulse-monitor.service
        msg_ok "Stopped ${APP} service."

        # Execute Update using git and npm (run as root, chown later)
        msg_info "Fetching and checking out ${LATEST_RELEASE}..."
        cd /opt/pulse-proxmox || { msg_error "Failed to cd into /opt/pulse-proxmox"; exit 1; }

        # Reset local changes, fetch, checkout, clean (run as pulse user for safety if possible, but root often needed for npm install)
        # Let's use root for now, matching install script's likely execution context
        git fetch origin --tags --force $STD || { msg_error "Failed to fetch from git remote."; exit 1; }
        git checkout -f ${LATEST_RELEASE} $STD || { msg_error "Failed to checkout tag ${LATEST_RELEASE}."; exit 1; }
        # Consider resetting after checkout in case checkout failed partially?
        git reset --hard ${LATEST_RELEASE} $STD || { msg_error "Failed to reset to tag ${LATEST_RELEASE}."; exit 1; }
        git clean -fd $STD || { msg_warning "Failed to clean untracked files."; } # Non-fatal warning
        msg_ok "Fetched and checked out ${LATEST_RELEASE}."

        msg_info "Installing Node.js dependencies..."
        # Install root deps (includes dev for build)
        npm install --unsafe-perm $STD || { msg_error "Failed to install root npm dependencies."; exit 1; }
        # Install server deps
        cd server || { msg_error "Failed to cd into server directory."; exit 1; }
        npm install --unsafe-perm $STD || { msg_error "Failed to install server npm dependencies."; cd ..; exit 1; }
        cd ..
        msg_ok "Node.js dependencies installed."

        msg_info "Building CSS assets..."
        npm run build:css $STD || { msg_warning "Failed to build CSS assets. Proceeding anyway."; } # Non-fatal warning
        msg_ok "CSS assets built."

        msg_info "Setting permissions..."
        chown -R pulse:pulse /opt/pulse-proxmox
        msg_ok "Permissions set."

        # Starting Service
        msg_info "Starting ${APP} service..."
        systemctl start pulse-monitor.service
        msg_ok "Started ${APP} service."

        # Update version file
        echo "${LATEST_RELEASE}" > /opt/${APP}_version.txt
        msg_ok "Update Successful to ${LATEST_RELEASE}"
    else
        msg_ok "No update required. ${APP} is already at ${LATEST_RELEASE}."
    fi
    exit 0
}

start
build_container
description

# Read port from .env file if it exists, otherwise use default
PULSE_PORT=7655 # Default
if [ -f "/opt/pulse-proxmox/.env" ] && grep -q '^PORT=' "/opt/pulse-proxmox/.env"; then
    PULSE_PORT=$(grep '^PORT=' "/opt/pulse-proxmox/.env" | cut -d'=' -f2 | tr -d '[:space:]')
    # Basic validation if port looks like a number
    if ! [[ "$PULSE_PORT" =~ ^[0-9]+$ ]]; then
        PULSE_PORT=7655 # Fallback to default if not a number
    fi
fi

msg_ok "Completed Successfully!
"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:${PULSE_PORT}${CL}" 
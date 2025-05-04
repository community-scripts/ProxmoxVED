#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: rcourtman
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rcourtman/Pulse

# App Default Values
APP="Pulse"
# shellcheck disable=SC2034
var_tags="monitoring;nodejs"
# shellcheck disable=SC2034
var_cpu="1"
# shellcheck disable=SC2034
var_ram="1024"
# shellcheck disable=SC2034
var_disk="4"
# shellcheck disable=SC2034
var_os="debian"
# shellcheck disable=SC2034
var_version="12"
# shellcheck disable=SC2034
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
  if ! command -v jq &>/dev/null; then
    msg_error "jq is required for version checking but not installed. Please install it (apt-get install jq)."
    exit 1
  fi

  # Crawling the new version and checking whether an update is required
  msg_info "Checking for ${APP} updates..."
  LATEST_RELEASE=$(curl -s https://api.github.com/repos/rcourtman/Pulse/releases/latest | jq -r '.tag_name')
  if ! LATEST_RELEASE=$(curl -s https://api.github.com/repos/rcourtman/Pulse/releases/latest | jq -r '.tag_name') ||
    [[ -z "$LATEST_RELEASE" ]] || [[ "$LATEST_RELEASE" == "null" ]]; then
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
    cd /opt/pulse-proxmox || {
      msg_error "Failed to cd into /opt/pulse-proxmox"
      exit 1
    }

    msg_info "Configuring git safe directory..."
    set -x # Enable command tracing
    # Allow root user to operate on the pulse user's git repo - exit if it fails
    git config --global --add safe.directory /opt/pulse-proxmox
    local git_config_exit_code=$? # Capture exit code
    set +x                        # Disable command tracing
    if [ $git_config_exit_code -ne 0 ]; then
      msg_error "git config safe.directory failed with exit code $git_config_exit_code"
      exit 1
    fi
    msg_ok "Configured git safe directory."

    # Reset local changes, fetch, checkout, clean
    # Use silent function wrapper for non-interactive update
    silent git fetch origin --tags --force || {
      msg_error "Failed to fetch from git remote."
      exit 1
    }
    echo "DEBUG: Attempting checkout command: git checkout ${LATEST_RELEASE}" # DEBUG
    # Try checkout without -f and without silent wrapper
    git checkout "${LATEST_RELEASE}" || {
      msg_error "Failed to checkout tag ${LATEST_RELEASE}."
      exit 1
    }
    silent git reset --hard "${LATEST_RELEASE}" || {
      msg_error "Failed to reset to tag ${LATEST_RELEASE}."
      exit 1
    }
    silent git clean -fd || { msg_warning "Failed to clean untracked files."; } # Non-fatal warning
    msg_ok "Fetched and checked out ${LATEST_RELEASE}."

    msg_info "Setting ownership and permissions before npm install..."
    chown -R pulse:pulse /opt/pulse-proxmox || {
      msg_error "Failed to chown /opt/pulse-proxmox"
      exit 1
    }
    # Ensure correct execute permissions before npm install/build
    chmod -R u+rwX,go+rX,go-w /opt/pulse-proxmox || {
      msg_error "Failed to chmod /opt/pulse-proxmox"
      exit 1
    }
    # Explicitly add execute permission for node_modules binaries
    if [ -d "/opt/pulse-proxmox/node_modules/.bin" ]; then
      chmod +x /opt/pulse-proxmox/node_modules/.bin/* || msg_warning "Failed to chmod +x on node_modules/.bin"
    fi
    msg_ok "Ownership and permissions set."

    msg_info "Installing Node.js dependencies..."
    # Run installs as pulse user with simulated login shell, ensuring correct directory
    silent sudo -iu pulse sh -c 'cd /opt/pulse-proxmox && npm install --unsafe-perm' || {
      msg_error "Failed to install root npm dependencies."
      exit 1
    }
    # Install server deps
    # Explicitly set directory for server deps install as well
    silent sudo -iu pulse sh -c 'cd /opt/pulse-proxmox/server && npm install --unsafe-perm' || {
      msg_error "Failed to install server npm dependencies."
      exit 1
    }
    # No need for cd .. here as sh -c runs in a subshell
    msg_ok "Node.js dependencies installed."

    msg_info "Building CSS assets..."
    # Try running tailwindcss directly as pulse user, specifying full path
    TAILWIND_PATH="/opt/pulse-proxmox/node_modules/.bin/tailwindcss"
    TAILWIND_ARGS="-c ./src/tailwind.config.js -i ./src/index.css -o ./src/public/output.css"
    # Use sh -c to ensure correct directory context for paths in TAILWIND_ARGS
    if ! sudo -iu pulse sh -c "cd /opt/pulse-proxmox && $TAILWIND_PATH $TAILWIND_ARGS"; then
      # Use echo directly, remove BFR
      echo -e "${TAB}${YW}⚠️ Failed to build CSS assets (See errors above). Proceeding anyway.${CL}"
    else
      msg_ok "CSS assets built."
    fi

    msg_info "Setting permissions..."
    # Permissions might not be strictly needed now if installs run as pulse,
    # but doesn't hurt to ensure consistency.
    # Run chown again to be safe, though maybe less critical now.
    chown -R pulse:pulse /opt/pulse-proxmox || msg_warning "Final chown failed."
    # Final chmod removed as it's done earlier
    msg_ok "Permissions set."

    # Starting Service
    msg_info "Starting ${APP} service..."
    systemctl start pulse-monitor.service
    msg_ok "Started ${APP} service."

    # Update version file
    echo "${LATEST_RELEASE}" >/opt/${APP}_version.txt
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

#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: rcourtman
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rcourtman/Pulse

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

  if ! command -v jq &>/dev/null; then
    msg_info "jq is not installed. Installing..."
    $STD apt-get update >/dev/null
    $STD apt-get install -y jq >/dev/null
    if ! command -v jq &>/dev/null; then
      msg_error "Failed to install jq. Cannot proceed with update check."
      exit 1
    fi
    msg_ok "jq installed."
  fi

  msg_info "Checking for ${APP} updates..."
  LATEST_RELEASE=$(curl -s https://api.github.com/repos/rcourtman/Pulse/releases/latest | jq -r '.tag_name')
  msg_ok "Latest available version: ${LATEST_RELEASE}"

  CURRENT_VERSION=""
  if [[ -f /opt/${APP}_version.txt ]]; then
    CURRENT_VERSION=$(cat /opt/${APP}_version.txt)
  fi

  if [[ "${LATEST_RELEASE}" != "$CURRENT_VERSION" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Updating ${APP} to ${LATEST_RELEASE}..."

    msg_info "Stopping ${APP} service..."
    systemctl stop pulse-monitor.service
    msg_ok "Stopped ${APP} service."

    msg_info "Fetching and checking out ${LATEST_RELEASE}..."
    cd /opt/pulse-proxmox || {
      msg_error "Failed to cd into /opt/pulse-proxmox"
      exit 1
    }

    msg_info "Configuring git safe directory..."
    set -x
    git config --global --add safe.directory /opt/pulse-proxmox
    local git_config_exit_code=$?
    set +x
    if [ $git_config_exit_code -ne 0 ]; then
      msg_error "git config safe.directory failed with exit code $git_config_exit_code"
      exit 1
    fi
    msg_ok "Configured git safe directory."

    silent git fetch origin --tags --force || {
      msg_error "Failed to fetch from git remote."
      exit 1
    }
    echo "DEBUG: Attempting checkout command: git checkout ${LATEST_RELEASE}"
    git checkout "${LATEST_RELEASE}" || {
      msg_error "Failed to checkout tag ${LATEST_RELEASE}."
      exit 1
    }
    silent git reset --hard "${LATEST_RELEASE}" || {
      msg_error "Failed to reset to tag ${LATEST_RELEASE}."
      exit 1
    }
    silent git clean -fd || { msg_warning "Failed to clean untracked files."; }
    msg_ok "Fetched and checked out ${LATEST_RELEASE}."

    msg_info "Setting ownership and permissions before npm install..."
    chown -R pulse:pulse /opt/pulse-proxmox || {
      msg_error "Failed to chown /opt/pulse-proxmox"
      exit 1
    }
    chmod -R u+rwX,go+rX,go-w /opt/pulse-proxmox || {
      msg_error "Failed to chmod /opt/pulse-proxmox"
      exit 1
    }
    if [ -d "/opt/pulse-proxmox/node_modules/.bin" ]; then
      chmod +x /opt/pulse-proxmox/node_modules/.bin/* || msg_warning "Failed to chmod +x on node_modules/.bin"
    fi
    msg_ok "Ownership and permissions set."

    msg_info "Installing Node.js dependencies..."
    silent sudo -iu pulse sh -c 'cd /opt/pulse-proxmox && npm install --unsafe-perm' || {
      msg_error "Failed to install root npm dependencies."
      exit 1
    }
    silent sudo -iu pulse sh -c 'cd /opt/pulse-proxmox/server && npm install --unsafe-perm' || {
      msg_error "Failed to install server npm dependencies."
      exit 1
    }
    msg_ok "Node.js dependencies installed."

    msg_info "Building CSS assets..."
    TAILWIND_PATH="/opt/pulse-proxmox/node_modules/.bin/tailwindcss"
    TAILWIND_ARGS="-c ./src/tailwind.config.js -i ./src/index.css -o ./src/public/output.css"
    if ! sudo -iu pulse sh -c "cd /opt/pulse-proxmox && $TAILWIND_PATH $TAILWIND_ARGS"; then
      echo -e "${TAB}${YW}⚠️ Failed to build CSS assets (See errors above). Proceeding anyway.${CL}"
    else
      msg_ok "CSS assets built."
    fi

    msg_info "Setting permissions..."
    chown -R pulse:pulse /opt/pulse-proxmox || msg_warning "Final chown failed."
    msg_ok "Permissions set."

    msg_info "Starting ${APP} service..."
    systemctl start pulse-monitor.service
    msg_ok "Started ${APP} service."

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

PULSE_PORT=7655
if [ -f "/opt/pulse-proxmox/.env" ] && grep -q '^PORT=' "/opt/pulse-proxmox/.env"; then
  PULSE_PORT=$(grep '^PORT=' "/opt/pulse-proxmox/.env" | cut -d'=' -f2 | tr -d '[:space:]')
  if ! [[ "$PULSE_PORT" =~ ^[0-9]+$ ]]; then
    PULSE_PORT=7655
  fi
fi

msg_ok "Completed Successfully!
"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:${PULSE_PORT}${CL}"

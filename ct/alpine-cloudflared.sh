#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.cloudflare.com/

APP="Cloudflared"
var_tags="${var_tags:-network;cloudflare}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

user_configuration() {

  sanitize_token() {
    local token="$1"
    echo "$token" | tr -cd '[:print:]'
  }

  while true; do
    local type
    if type=$(
      whiptail --title "Tunnel Type" \
        --menu "Select Tunnel Type:" 9 53 2 \
        "remotely-managed" "Uses a token (Recommended)" \
        "locally-managed" "Uses a local configuration file" \
        3>&1 1>&2 2>&3
    ); then
      if [[ "$type" == "remotely-managed" ]]; then
        local token
        if token=$(whiptail --title "Tunnel Token" \
          --textbox "Enter Tunnel Token" 10 80 "" \
          3>&1 1>&2 2>&3); then
          token=$(sanitize_token "$token")
          if [[ "$token" =~ [^[:alnum:]] ]]; then
            export TOKEN=$token
            break
          else
            whiptail --msgbox "Invalid token: contains special characters" 7 46
          fi
        fi
      else
        break
      fi
    fi
  done
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if installation is present | -f for file, -d for folder
  if [[ ! -f [INSTALLATION_CHECK_PATH] ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  RELEASE=$(curl -fsSL [RELEASE_URL] | [PARSE_RELEASE_COMMAND])
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    # Stopping Services
    msg_info "Stopping $APP"
    systemctl stop [SERVICE_NAME]
    msg_ok "Stopped $APP"

    # Creating Backup
    msg_info "Creating Backup"
    tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" [IMPORTANT_PATHS]
    msg_ok "Backup Created"

    # Execute Update
    msg_info "Updating $APP to v${RELEASE}"
    [UPDATE_COMMANDS]
    msg_ok "Updated $APP to v${RELEASE}"

    # Starting Services
    msg_info "Starting $APP"
    systemctl start [SERVICE_NAME]
    msg_ok "Started $APP"

    # Cleaning up
    msg_info "Cleaning Up"
    rm -rf [TEMP_FILES]
    msg_ok "Cleanup Completed"

    # Last Action
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
user_configuration
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:[PORT]${CL}"

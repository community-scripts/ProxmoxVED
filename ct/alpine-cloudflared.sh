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
        token=$(whiptail --title "Tunnel Token" \
          --inputbox "Enter Tunnel Token" 10 80 "" \
          3>&1 1>&2 2>&3)
        token=$(echo "$token" | tr -cd '[:print:]')
        if [[ "$token" =~ ^[[:alnum:]]+$ ]]; then
          export TOKEN=$token
          break
        else
          whiptail --msgbox "Invalid token: contains special characters" 7 46
          continue
        fi
      else
        break
      fi
    else
      clear
      printf "\e[?25h"
      echo -e "\n${CROSS}${RD}User exited script${CL}\n"
      kill 0
      exit 1
    fi
  done
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if installation is present
  if [[ ! -f /etc/init.d/cloudflared ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Stopping Services
  msg_info "Stopping $APP"
  rc-service cloudflared stop
  msg_ok "Stopped $APP"

  # Execute Update
  msg_info "Updating $APP"
  $STD apk -U upgrade
  $STD cloudflared update
  msg_ok "Updated $APP to $(cloudflared -V)"

  # Starting Services
  msg_info "Starting $APP"
  rc-service cloudflared start
  msg_ok "Started $APP"

  # Cleaning up
  msg_info "Cleaning Up"
  $STD apk cache clean
  find /var/log -type f -delete 2>/dev/null
  find /tmp -mindepth 1 -delete 2>/dev/null
  $STD apk update
  msg_ok "Cleanup Completed"

  # Last Action
  msg_ok "Update Successful"
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

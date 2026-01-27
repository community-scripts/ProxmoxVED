#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.cloudflare.com/

APP="Alpine-Cloudflared"
var_tags="${var_tags:-network;cloudflare}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_unprivileged="${var_unprivileged:-1}"
var_token="${var_token:-}"
var_config_path="${var_config_path:-/usr/local/etc/cloudflared}"

header_info "$APP"
variables
color
catch_errors

user_configuration() {
  token_valid() {
    local token="$1"

    # Sanitize token of unprintable chars
    token=$(echo "$token" | tr -cd '[:print:]')

    # Validate token is present and alphanumeric (should be Base64)
    if [ -z "$token" ] || ! [[ "$token" =~ ^[[:alnum:]]+$ ]]; then
      return 1
    fi

    # export for use in install script
    export TOKEN=$token
  }

  # If user supplied $var_token and it's valid skip menu
  token_valid "$var_token" && return 0

  while true; do
    local type
    if type=$(
      whiptail --title "Tunnel Type" \
        --menu "Select Tunnel Type:" 9 53 2 \
        "remotely-managed" "Uses a token (Recommended)" \
        "locally-managed" "Uses a local configuration file" \
        3>&1 1>&2 2>&3
    ); then
      # if "remotely-managed" get token from user
      if [[ "$type" == "remotely-managed" ]]; then
        local token
        if token=$(
          whiptail --title "Tunnel Token" \
            --inputbox "Enter Tunnel Token" 10 80 "" \
            3>&1 1>&2 2>&3
        ); then
          if token_valid "$token"; then
            # break to continue script
            break
          else
            # || true to prevent failure on escape key
            whiptail --msgbox "Invalid token: contains special characters" 7 46 || true
          fi
        else
          # continue to prevent failure on escape key
          continue
        fi
      else
        # export for use in install script and break to continue script
        export CONFIG_PATH=$var_config_path
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
if [ -z "$TOKEN" ]; then
  echo -e "${INFO}${YW} Edit the config file at:${CL}"
  echo -e "${TAB}${ADVANCED}${GN} ${CONFIG_PATH}/config.yml${CL}"
  echo -e "${INFO}${BGN}Run \"rc-service cloudflared start\" to start!${CL}"
fi

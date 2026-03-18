#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Simon Friedrich
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://forgejo.org/

APP="Forgejo-Runner"
var_tags="${var_tags:-ci}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"

var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

var_forgejo_instance="${var_forgejo_instance:-https://codeberg.org}"
var_forgejo_runner_token="${var_forgejo_runner_token:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/forgejo-runner ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  msg_info "Stopping Services"
  systemctl stop forgejo-runner
  msg_ok "Stopped Services"

  RELEASE=$(curl -fsSL https://data.forgejo.org/api/v1/repos/forgejo/runner/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')
  msg_info "Updating Forgejo Runner to v${RELEASE}"
  curl -fsSL "https://code.forgejo.org/forgejo/runner/releases/download/v${RELEASE}/forgejo-runner-linux-amd64" -o forgejo-runner
  chmod +x /usr/local/bin/forgejo-runner
  msg_ok "Updated Forgejo Runner"

  msg_info "Starting Services"
  systemctl start forgejo-runner
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

advanced_settings() {
  default_settings

  if result=$(whiptail --title "Forgejo Instance" \
    --inputbox "Enter Forgejo Instance URL:" 10 70 "$var_forgejo_instance" \
    3>&1 1>&2 2>&3); then

    if [[ -z "$result" ]]; then
      whiptail --msgbox "Instance URL is required!" 8 40
      advanced_settings
      return
    fi

    var_forgejo_instance="$result"
  else
    return
  fi

  if result=$(whiptail --title "Forgejo Runner Token" \
    --passwordbox "Enter Runner Registration Token:" 10 70 "" \
    3>&1 1>&2 2>&3); then

    if [[ -z "$result" ]]; then
      whiptail --msgbox "Token is required!" 8 40
      advanced_settings
      return
    fi

    var_forgejo_runner_token="$result"
  else
    return
  fi
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"

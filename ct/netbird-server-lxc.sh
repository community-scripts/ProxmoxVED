#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://netbird.io

APP="NetBird Server LXC"
var_tags="${var_tags:-network;security;vpn}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.22}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

export var_netbird_domain="${var_netbird_domain:-}"
export var_netbird_email="${var_netbird_email:-}"

header_info "$APP"
variables
color
catch_errors

function valid_netbird_domain() {
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] && [[ "$1" != "netbird.example.com" ]]
}

function valid_netbird_email() {
  [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]]
}

function configure_netbird_setup() {
  while ! valid_netbird_domain "$var_netbird_domain"; do
    if var_netbird_domain=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "NETBIRD DOMAIN" \
      --inputbox "Enter the public domain for your NetBird server.\nDNS A record must point to this LXC's public IP.\n\ne.g. netbird.my-domain.com" 11 65 "" \
      --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if ! valid_netbird_domain "$var_netbird_domain"; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID DOMAIN" \
          --msgbox "Please enter a valid public domain name." 8 50
      fi
    else
      exit_script
    fi
  done
  echo -e "${INFO}${BOLD}${DGN}NetBird Domain: ${BGN}${var_netbird_domain}${CL}"

  while ! valid_netbird_email "$var_netbird_email"; do
    if var_netbird_email=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "LETSENCRYPT EMAIL" \
      --inputbox "Enter your email for Let's Encrypt certificates:" 8 65 "" \
      --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if ! valid_netbird_email "$var_netbird_email"; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID EMAIL" \
          --msgbox "Please enter a valid email address." 8 50
      fi
    else
      exit_script
    fi
  done
  echo -e "${INFO}${BOLD}${DGN}Let's Encrypt Email: ${BGN}${var_netbird_email}${CL}"
  echo -e "${INFO}${BOLD}${DGN}Reverse Proxy: ${BGN}Traefik (built-in with auto TLS)${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/netbird-server/docker-compose.yml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  msg_info "Updating NetBird Containers"
  cd /opt/netbird-server
  docker compose pull
  docker compose up -d
  msg_ok "Updated NetBird Containers"
  exit
}

if [[ -n "${mode:-}" ]]; then
  if ! valid_netbird_domain "$var_netbird_domain"; then
    msg_error "var_netbird_domain is required for unattended installs."
    exit 1
  fi
  if ! valid_netbird_email "$var_netbird_email"; then
    msg_error "var_netbird_email is required for unattended installs."
    exit 1
  fi
else
  configure_netbird_setup
fi

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${var_netbird_domain}${CL}"
echo -e "${INFO}${YW} Finish setup by creating the first admin account on /setup.${CL}"

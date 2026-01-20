#!/usr/bin/env bash

# Copyright (c) 2026 XplicitTrust GmbH
# Author: dstutz
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -euo pipefail

function header_info() {
  clear
  cat <<"EOF"
__   __      _ _      _ _   _____               _
\ \ / /     | (_)    (_) | |_   _|             | |
 \ V / _ __ | |_  ___ _| |_  | |_ __ _   _  ___| |_
  > < | '_ \| | |/ __| | __| | | '__| | | |/ __| __|
 / . \| |_) | | | (__| | |_  | | |  | |_| |\__ \ |_
/_/ \_\ .__/|_|_|\___|_|\__| \_/_|   \__,_||___/\__|
      | |
      |_|
EOF
}

function msg_info()  { echo -e " \e[1;36m➤\e[0m $1"; }
function msg_ok()    { echo -e " \e[1;32m✔\e[0m $1"; }
function msg_error() { echo -e " \e[1;31m✖\e[0m $1"; }

function select_storage() {
  local CONTENT_TYPE=$1
  local PROMPT_TEXT=$2
  local STORAGE_LIST MENU_OPTIONS=()

  STORAGE_LIST=$(pvesm status -content "$CONTENT_TYPE" | awk 'NR>1 {print $1}')

  if [[ -z "$STORAGE_LIST" ]]; then
    msg_error "No active storage found for content type: $CONTENT_TYPE"
    exit 1
  fi

  if [[ "$(echo "$STORAGE_LIST" | wc -l)" -eq 1 ]]; then
    echo "$STORAGE_LIST"
    return
  fi

  while read -r line; do
    MENU_OPTIONS+=("$line" "$CONTENT_TYPE")
  done <<<"$STORAGE_LIST"

  local SELECTION
  if ! SELECTION=$(whiptail --title "Storage Selection" \
      --menu "$PROMPT_TEXT" 15 60 6 \
      "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3); then
    exit 1
  fi

  echo "$SELECTION"
}

command -v pveversion >/dev/null || { msg_error "Run this on a Proxmox VE host."; exit 1; }
command -v whiptail   >/dev/null || { msg_error "whiptail is required."; exit 1; }

function install_xplicittrust() {
  local TARGET_CTID=$1
  local TARGET_CONFIG="/etc/pve/lxc/${TARGET_CTID}.conf"

  header_info
  msg_info "Installing XplicitTrust on CT $TARGET_CTID"

  trap 'rm -f "/tmp/${DEB_FILE:-}"' EXIT

  msg_info "Configuring TUN device permissions..."
  grep -q "c 10:200 rwm" "$TARGET_CONFIG" \
    || echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >>"$TARGET_CONFIG"

  grep -q "/dev/net/tun" "$TARGET_CONFIG" \
    || echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >>"$TARGET_CONFIG"

  msg_info "Detecting container architecture..."
  CT_ARCH=$(pct exec "$TARGET_CTID" -- dpkg --print-architecture)
  DEB_FILE="xtna-agent_${CT_ARCH}.deb"
  DOWNLOAD_URL="https://dl.xplicittrust.com/${DEB_FILE}"

  msg_info "Downloading agent (${CT_ARCH})..."
  wget -q "$DOWNLOAD_URL" -O "/tmp/$DEB_FILE"

  msg_info "Pushing agent into container..."
  pct push "$TARGET_CTID" "/tmp/$DEB_FILE" "/tmp/$DEB_FILE"

  msg_info "Installing & registering agent..."
  pct exec "$TARGET_CTID" -- env \
    XT_DOMAIN="$XT_DOMAIN" \
    XT_TOKEN="$XT_TOKEN" \
    bash -c '
      set -e
      export DEBIAN_FRONTEND=noninteractive

      echo "[LXC] Waiting for DNS..."
      for i in {1..15}; do
        getent hosts dl.xplicittrust.com >/dev/null && break || sleep 1
      done

      apt-get update -qq
      apt-get install -y /tmp/'"$DEB_FILE"' >/dev/null
      rm /tmp/'"$DEB_FILE"'

      /usr/sbin/xtna-util -domain "$XT_DOMAIN" -token "$XT_TOKEN"
    '

  local TAGS
  TAGS=$(awk -F': ' '/^tags:/ {print $2}' "$TARGET_CONFIG" | tr -d ' ')
  if [[ "$TAGS" != *xplicittrust* ]]; then
    pct set "$TARGET_CTID" -tags "${TAGS:+$TAGS; }xplicittrust"
  fi

  msg_ok "XplicitTrust agent successfully installed on CT $TARGET_CTID"
  msg_info "Reboot container if the agent does not connect immediately."
}


header_info

echo -e " \e[1;33mXplicitTrust Credentials\e[0m"

while [[ -z "${XT_DOMAIN:-}" ]]; do
  read -rp "Tenant Domain (e.g. company.com): " XT_DOMAIN
done

while [[ -z "${XT_TOKEN:-}" ]]; do
  read -s -rp "Asset Creation Token: " XT_TOKEN
  echo
done

CHOICE=$(whiptail --title "Installation Mode" \
  --menu "Choose an option:" 10 60 2 \
  "1" "Create NEW Container (Debian 12)" \
  "2" "Install into EXISTING Container" \
  3>&1 1>&2 2>&3) || exit 0

# -----------------------------------------------------------------------------
# NEW CONTAINER
# -----------------------------------------------------------------------------
if [[ "$CHOICE" == "1" ]]; then
  header_info
  echo -e " \e[1;33mNew Container Settings\e[0m"

  TEMPLATE_STORAGE=$(select_storage "vztmpl" "Template storage:")
  ROOTFS_STORAGE=$(select_storage "rootdir" "Root disk storage:")

  read -rp "Hostname: " NEW_HOSTNAME
  read -s -rp "Root Password: " NEW_PASS
  echo

  msg_info "Updating template list..."
  pveam update >/dev/null

  TEMPLATE_FILE=$(pveam available --section system \
    | awk '/debian-12-standard/ {print $2}' \
    | sort -V | tail -n 1)

  [[ -z "$TEMPLATE_FILE" ]] && { msg_error "Debian 12 template not found."; exit 1; }

  if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE_FILE"; then
    msg_info "Downloading Debian template..."
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_FILE"
  fi

  CTID=$(pvesh get /cluster/nextid)
  msg_info "Creating container $CTID..."

  pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_FILE}" \
    --hostname "$NEW_HOSTNAME" \
    --password "$NEW_PASS" \
    --cores 1 \
    --memory 512 \
    --swap 512 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --rootfs "${ROOTFS_STORAGE}:8" \
    --unprivileged 1 \
    --features nesting=1 \
    --ostype debian

  pct start "$CTID"
  sleep 5

  install_xplicittrust "$CTID"

else
  header_info
  msg_info "Loading containers..."

  MENU=()
  while read -r line; do
    MENU+=($(awk '{print $1, substr($0,36)}' <<<"$line") OFF)
  done < <(pct list | awk 'NR>1')

  CTID=$(whiptail --title "Select Container" \
    --radiolist "Choose target container:" \
    18 70 8 \
    "${MENU[@]}" 3>&1 1>&2 2>&3) || exit 1

  install_xplicittrust "$CTID"
fi


#!/usr/bin/env bash

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: nnsense
# License: MIT | https://github.com/--full/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/kieraneglin/pinchflat

APP="Pinchflat"
var_tags="${var_tags:-media;youtube;downloader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  DOWNLOADS_PATH="/opt/pinchflat/downloads"
  echo_default
}

function advanced_settings() {
  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$APP LXC" --yesno "Use advanced settings?" 10 58 || return

  CT_TYPE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Container Type" --radiolist "Choose container type" 10 58 2 \
    "1" "Unprivileged" ON \
    "0" "Privileged" OFF 3>&1 1>&2 2>&3)

  HN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Hostname" 8 58 "$NSAPP" 3>&1 1>&2 2>&3)
  CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "CPU cores" 8 58 "$var_cpu" 3>&1 1>&2 2>&3)
  RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "RAM in MiB" 8 58 "$var_ram" 3>&1 1>&2 2>&3)
  DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Disk size in GiB" 8 58 "$var_disk" 3>&1 1>&2 2>&3)

  DOWNLOADS_PATH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Pinchflat Downloads" --inputbox \
"Downloads path inside the LXC.

Default: /opt/pinchflat/downloads
Example external mount path: /mnt/pinchflat

If the path does not exist during installation, it will be created locally.
You can later stop the LXC, mount external storage at the same path, and start it again." \
18 78 "/opt/pinchflat/downloads" 3>&1 1>&2 2>&3)
  DOWNLOADS_PATH="${DOWNLOADS_PATH:-/opt/pinchflat/downloads}"

  BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Bridge" 8 58 "vmbr0" 3>&1 1>&2 2>&3)

  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Network" --yesno "Use DHCP?" 8 58; then
    NET="dhcp"
    GATE=""
  else
    NET=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Static IP/CIDR" 8 58 "192.168.0.100/24" 3>&1 1>&2 2>&3)
    GATE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Gateway" 8 58 "192.168.0.1" 3>&1 1>&2 2>&3)
  fi

  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pinchflat/app ]]; then
    msg_error "No ${APP} installation found."
    exit 1
  fi

  if check_for_gh_release "pinchflat" "kieraneglin/pinchflat"; then
    msg_info "Stopping Service"
    systemctl stop pinchflat
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "pinchflat" "kieraneglin/pinchflat" "tarball" "latest" "/opt/pinchflat-src"

    msg_info "Building Pinchflat"
    cd /opt/pinchflat-src || exit 1
    export MIX_ENV=prod
    export ERL_FLAGS="+JPperf true"
    $STD mix deps.get --only prod
    $STD mix deps.compile
    $STD yarn --cwd assets install
    $STD mix assets.deploy
    $STD mix compile
    $STD mix release --overwrite
    rm -rf /opt/pinchflat/app
    cp -r _build/prod/rel/pinchflat /opt/pinchflat/app
    msg_ok "Built Pinchflat"

    msg_info "Starting Service"
    systemctl start pinchflat
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

export DOWNLOADS_PATH

start
build_container
description
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8945${CL}"

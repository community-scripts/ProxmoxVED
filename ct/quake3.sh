#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2024 tteck
# Author: community-scripts
# License: MIT
# https://github.com/community-scripts/ProxmoxVE

function header_info {
clear
cat <<"EOF"
  _                               _    _____ 
 (_) ___   __ _ _   _ __ _| | _____|___ / 
 | |/ _ \ / _` | | | / _` | |/ / _ \ |_ \ 
 | | (_) | (_| | |_| | (_| |   <  __/___) |
 |_|\___/ \__, |\__,_|\__,_|_|\_\___|____/ 
             |_|                           
EOF
}
header_info
echo -e "Loading..."

APP="ioquake3"

# --- DEVELOPER OVERRIDES: FORCES PROXMOX TO USE YOUR REPO ---
export GITHUB_USER="geedoes"
export GITHUB_REPO="ProxmoxVE-ioquake3-beta"
export GITHUB_BRANCH="main"
# ------------------------------------------------------------

var_disk="5"
var_cpu="2"
var_ram="1024"
var_os="debian"
var_version="12"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$RN
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
  echo_default
}

function update_script() {
header_info
check_container_storage
check_container_resources
if [[ ! -d /opt/ioquake3 ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
msg_error "There is currently no auto-update path available for ioquake3."
exit
}

start
build_container
description

# 1. Run the internal setup script FIRST
# This creates the /opt/ioquake3 directory and the 'quake3' user
msg_info "Running internal Quake 3 installation..."
pct exec $CTID -- bash -c "$(curl -s https://raw.githubusercontent.com/geedoes/ProxmoxVED/refs/heads/main/install/ioquake3-install.sh)"

# 2. Check for the pak0.iso file
msg_info "Checking for pak0.iso in Proxmox ISO storage..."
HOST_ISO_PATH="/var/lib/vz/template/iso/pak0.iso"
DEST_PATH="/opt/ioquake3/baseq3/pak0.pk3"

if [ ! -f "$HOST_ISO_PATH" ]; then
  msg_warn "pak0.iso not found!"
  echo -e "  Please upload your pak0.pk3 file but rename it to **pak0.iso**"
  echo -e "  so the Proxmox UI allows the upload."
  
  while [ ! -f "$HOST_ISO_PATH" ]; do
    sleep 5
  done
  msg_ok "Found pak0.iso!"
fi

# 3. Deploy file and restart service
# Now that step 1 is done, these paths and users actually exist
msg_info "Deploying game files to Container..."
pct push $CTID "$HOST_ISO_PATH" "$DEST_PATH"
pct exec $CTID -- bash -c "chown -R quake3:quake3 /opt/ioquake3/ && systemctl restart ioquake3"

msg_ok "pak0.pk3 deployed and service restarted."
msg_ok "Completed Successfully!\n"

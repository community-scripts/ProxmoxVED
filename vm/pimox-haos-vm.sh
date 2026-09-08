#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

clear
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
APP="Home Assistant OS (ARM64)"
APP_TYPE="vm"
NSAPP="pimox-haos-vm"
var_os="pimox-haos"
var_arm64="yes"
DISK_SIZE="32G"

for channel in stable beta dev; do
  channel_version=$(curl -fsSL "https://raw.githubusercontent.com/home-assistant/version/master/${channel}.json" | grep '"ova"' | cut -d '"' -f 4) || channel_version=""
  printf -v "${channel^^}" '%s' "$channel_version"
done
if [ -z "$STABLE" ]; then
  echo -e "Could not determine the current Home Assistant OS release."
  exit 1
fi
BETA="${BETA:-$STABLE}"
DEV="${DEV:-$STABLE}"

THIN="discard=on,ssd=1,"

header_info
echo -e "\n Loading..."
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

vm_preflight

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

function default_settings() {
  METHOD="default"
  echo -e "${DGN}Using HAOS Version: ${BGN}${STABLE}${CL}"
  BRANCH=${STABLE}
  VMID=$(get_valid_nextid)
  echo -e "${DGN}Using Virtual Machine ID: ${BGN}$VMID${CL}"
  echo -e "${DGN}Using Hostname: ${BGN}haos${STABLE}${CL}"
  HN=haos${STABLE}
  echo -e "${DGN}Allocated Cores: ${BGN}2${CL}"
  CORE_COUNT="2"
  echo -e "${DGN}Allocated RAM: ${BGN}4096${CL}"
  RAM_SIZE="4096"
  echo -e "${DGN}Using Bridge: ${BGN}vmbr0${CL}"
  BRG="vmbr0"
  echo -e "${DGN}Using MAC Address: ${BGN}$GEN_MAC${CL}"
  MAC=$GEN_MAC
  echo -e "${DGN}Using VLAN: ${BGN}Default${CL}"
  VLAN=""
  echo -e "${DGN}Using Interface MTU Size: ${BGN}Default${CL}"
  MTU=""
  echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
  START_VM="yes"
  echo -e "${BL}Creating a HAOS VM using the above default settings${CL}"
}
function advanced_settings() {
  METHOD="advanced"
  BRANCH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HAOS VERSION" --radiolist "Choose Version" --cancel-button Exit-Script 10 58 3 \
    "$STABLE" "Stable" ON \
    "$BETA" "Beta" OFF \
    "$DEV" "Dev" OFF \
    3>&1 1>&2 2>&3)
  exitstatus=$?
  if [ $exitstatus = 0 ]; then echo -e "${DGN}Using HAOS Version: ${BGN}$BRANCH${CL}"; fi
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
  exitstatus=$?
  if [ -z $VMID ]; then
    VMID="$VMID"
    echo -e "${DGN}Virtual Machine: ${BGN}$VMID${CL}"
  else
    if echo "$USEDID" | egrep -q "$VMID"; then
      echo -e "\n🚨  ${RD}ID $VMID is already in use${CL} \n"
      echo -e "Exiting Script \n"
      sleep 2
      exit
    else
      if [ $exitstatus = 0 ]; then echo -e "${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"; fi
    fi
  fi
  VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 haos${BRANCH} --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
  exitstatus=$?
  if [ -z $VM_NAME ]; then
    HN="haos${BRANCH}"
    echo -e "${DGN}Using Hostname: ${BGN}$HN${CL}"
  else
    if [ $exitstatus = 0 ]; then
      HN=$(echo "${VM_NAME,,}" | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')
      if [ "$HN" != "${VM_NAME,,}" ]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "HOSTNAME ADJUSTED" --msgbox "Invalid characters detected. Hostname has been adjusted to:\n\n  $HN" 10 58
      fi
      echo -e "${DGN}Using Hostname: ${BGN}$HN${CL}"
    fi
  fi
  while true; do
    CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then exit_script; fi
    if [ -z "$CORE_COUNT" ]; then CORE_COUNT="2"; fi
    if [[ "$CORE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
      echo -e "${DGN}Allocated Cores: ${BGN}$CORE_COUNT${CL}"
      break
    fi
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "CPU Cores must be a positive integer (e.g., 2)." 8 58
  done
  while true; do
    RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 4096 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then exit_script; fi
    if [ -z "$RAM_SIZE" ]; then RAM_SIZE="4096"; fi
    if [[ "$RAM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
      echo -e "${DGN}Allocated RAM: ${BGN}$RAM_SIZE${CL}"
      break
    fi
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "RAM Size must be a positive integer in MiB (e.g., 4096)." 8 58
  done
  BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
  exitstatus=$?
  if [ -z $BRG ]; then
    BRG="vmbr0"
    echo -e "${DGN}Using Bridge: ${BGN}$BRG${CL}"
  else
    if [ $exitstatus = 0 ]; then echo -e "${DGN}Using Bridge: ${BGN}$BRG${CL}"; fi
  fi
  while true; do
    MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then exit_script; fi
    if [ -z "$MAC1" ]; then
      MAC="$GEN_MAC"
      echo -e "${DGN}Using MAC Address: ${BGN}$MAC${CL}"
      break
    fi
    if [[ "$MAC1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
      MAC="$MAC1"
      echo -e "${DGN}Using MAC Address: ${BGN}$MAC1${CL}"
      break
    fi
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid MAC address format. Use XX:XX:XX:XX:XX:XX (e.g., AA:BB:CC:DD:EE:FF)." 8 58
  done
  while true; do
    VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then exit_script; fi
    if [ -z "$VLAN1" ]; then
      VLAN1="Default"
      VLAN=""
      echo -e "${DGN}Using Vlan: ${BGN}$VLAN1${CL}"
      break
    fi
    if [[ "$VLAN1" =~ ^[0-9]+$ ]] && [ "$VLAN1" -ge 1 ] && [ "$VLAN1" -le 4094 ]; then
      VLAN=",tag=$VLAN1"
      echo -e "${DGN}Using Vlan: ${BGN}$VLAN1${CL}"
      break
    fi
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "VLAN must be a number between 1 and 4094, or leave blank for default." 8 58
  done
  while true; do
    MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then exit_script; fi
    if [ -z "$MTU1" ]; then
      MTU1="Default"
      MTU=""
      echo -e "${DGN}Using Interface MTU Size: ${BGN}$MTU1${CL}"
      break
    fi
    if [[ "$MTU1" =~ ^[0-9]+$ ]] && [ "$MTU1" -ge 576 ] && [ "$MTU1" -le 65520 ]; then
      MTU=",mtu=$MTU1"
      echo -e "${DGN}Using Interface MTU Size: ${BGN}$MTU1${CL}"
      break
    fi
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "MTU Size must be a number between 576 and 65520, or leave blank for default." 8 58
  done
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create HAOS ${BRANCH} VM?" --no-button Do-Over 10 58); then
    echo -e "${RD}Creating a HAOS VM using the above advanced settings${CL}"
  else
    clear
    header_info
    echo -e "${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}
vm_start_script "Use Default Settings?" 10 58
post_to_api_vm
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
if [ $((${#STORAGE_MENU[@]} / 3)) -eq 0 ]; then
  echo -e "'Disk image' needs to be selected for at least one storage location."
  die "Unable to detect valid storage location."
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for the HAOS VM?\n\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Getting URL for Home Assistant ${BRANCH} Disk Image"
# Dev builds never get a GitHub release, they are only published as artifacts.
if [ "$BRANCH" == "$DEV" ]; then
  URL="https://os-artifacts.home-assistant.io/${BRANCH}/haos_generic-aarch64-${BRANCH}.qcow2.xz"
else
  URL="https://github.com/home-assistant/operating-system/releases/download/${BRANCH}/haos_generic-aarch64-${BRANCH}.qcow2.xz"
fi
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
# A mirror serving an error page returns 200, so size decides whether this
# is an image. Anything real here is far above 5 MB.
CACHE_FILE="$(vm_image_cache_path "$URL")"
vm_fetch_image "$URL" "$CACHE_FILE" --cache --verify-xz --min-bytes $((5 * 1024 * 1024)) || exit 115
msg_info "Extracting Disk Image"
# Decompress out of the cache rather than over it, unxz eats its input.
FILE="$(basename "${CACHE_FILE%.xz}")"
unxz -kc "$CACHE_FILE" >"$FILE"
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done
msg_ok "Extracted Disk Image"
msg_info "Creating HAOS VM"
qm create $VMID -agent 1 -bios ovmf -cores $CORE_COUNT -memory $RAM_SIZE -name $HN \
  -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 64M 1>&/dev/null
qm importdisk $VMID "$FILE" $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF},efitype=4m,size=64M \
  -scsi0 ${DISK1_REF},size=32G >/dev/null
qm set $VMID \
  -boot order=scsi0 >/dev/null

set_description
vm_resize_disk

msg_ok "Created HAOS VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Home Assistant OS VM"
  $STD qm start $VMID
  msg_ok "Started Home Assistant OS VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

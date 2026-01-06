#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/api.func)
# Load Cloud-Init library for VM configuration
source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/cloud-init.func) 2>/dev/null || true

function header_info() {
  clear
  cat <<"EOF"
   __  __      _ _____    ____  _____    _____
  / / / /___  (_) __(_)  / __ \/ ___/   / ___/___  ______   _____  _____
 / / / / __ \/ / /_/ /  / / / /\__ \    \__ \/ _ \/ ___/ | / / _ \/ ___/
/ /_/ / / / / / __/ /  / /_/ /___/ /   ___/ /  __/ /   | |/ /  __/ /
\____/_/ /_/_/_/ /_/   \____//____/   /____/\___/_/    |___/\___/_/

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="UniFi OS Server"
var_os="-"
var_version="-"
USE_CLOUD_INIT="yes" # Always use Cloud-Init for UniFi OS (required for automated setup)
OS_TYPE=""
OS_VERSION=""
OS_CODENAME=""
OS_DISPLAY=""

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
HA=$(echo "\033[1;34m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"
CLOUD="${TAB}☁️${TAB}${CL}"
THIN="discard=on,ssd=1,"

set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  post_update_to_api "failed" "${command}"
  echo -e "\n${RD}[ERROR]${CL} line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing ${YW}$command${CL}\n"
  if qm status $VMID &>/dev/null; then qm stop $VMID &>/dev/null || true; fi
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  popd >/dev/null
  post_update_to_api "done" "none"
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Unifi OS VM" --yesno "This will create a New Unifi OS VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x and 9.0 – 9.1
pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"

  # Check for Proxmox VE 8.x: allow 8.0–8.9
  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 8.0 – 8.9"
      exit 1
    fi
    return 0
  fi

  # Check for Proxmox VE 9.x: allow 9.0–9.1
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 1)); then
      msg_error "This version of Proxmox VE is not yet supported."
      msg_error "Supported: Proxmox VE version 9.0 – 9.1"
      exit 1
    fi
    return 0
  fi

  # All other unsupported versions
  msg_error "This version of Proxmox VE is not supported."
  msg_error "Supported versions: Proxmox VE 8.0 – 8.x or 9.0"
  exit 1
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}${YWB}This script will not work with PiMox! \n"
    echo -e "\n ${YWB}Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

function select_os() {
  if OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SELECT OS" --radiolist \
    "Choose Operating System for UniFi OS VM" 12 68 2 \
    "debian13" "Debian 13 (Trixie) - Latest" ON \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF \
    3>&1 1>&2 2>&3); then
    case $OS_CHOICE in
    debian13)
      OS_TYPE="debian"
      OS_VERSION="13"
      OS_CODENAME="trixie"
      OS_DISPLAY="Debian 13 (Trixie)"
      ;;
    ubuntu2404)
      OS_TYPE="ubuntu"
      OS_VERSION="24.04"
      OS_CODENAME="noble"
      OS_DISPLAY="Ubuntu 24.04 LTS"
      ;;
    esac
    echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}${OS_DISPLAY}${CL}"
  else
    exit-script
  fi
}

function select_cloud_init() {
  # UniFi OS Server ALWAYS requires Cloud-Init for automated installation
  USE_CLOUD_INIT="yes"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}yes (required for UniFi OS)${CL}"
}

function get_image_url() {
  local arch=$(dpkg --print-architecture)
  case $OS_TYPE in
  debian)
    # Always use generic (Cloud-Init) variant for UniFi OS
    echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-generic-${arch}.qcow2"
    ;;
  ubuntu)
    # Ubuntu only has cloudimg variant (always with Cloud-Init support)
    echo "https://cloud-images.ubuntu.com/${OS_CODENAME}/current/${OS_CODENAME}-server-cloudimg-${arch}.img"
    ;;
  esac
}

function default_settings() {
  # OS Selection - ALWAYS ask
  select_os

  # Cloud-Init Selection - ALWAYS ask
  select_cloud_init

  # Set defaults for other settings
  VMID=$(get_valid_nextid)
  FORMAT=""
  MACHINE=" -machine q35"
  DISK_CACHE=""
  DISK_SIZE="32G"
  HN="unifi-server-os"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="2"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}Q35 (Modern)${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a UniFi OS VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"

  # OS Selection - ALWAYS ask
  select_os

  # Cloud-Init Selection - ALWAYS ask
  select_cloud_init

  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID=$(get_valid_nextid)
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Machine Type" 10 58 2 \
    "q35" "Q35 (Modern, PCIe, UEFI)" ON \
    "i440fx" "i440fx (Legacy)" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$MACH" = "q35" ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}Q35 (Modern)${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx (Legacy)${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 10 or 10G).${CL}"
      exit-script
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ $DISK_CACHE = "1" ]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 unifi-os-server --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="unifi-os-server"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose CPU Model" --cancel-button Exit-Script 10 58 2 \
    "Host" "Host (Faster, recommended)" ON \
    "KVM64" "KVM64 (Compatibility)" OFF \
    3>&1 1>&2 2>&3); then
    case "$CPU_TYPE1" in
    Host)
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
      ;;
    *)
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
      ;;
    esac
  else
    exit-script
  fi

  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $CORE_COUNT ]; then
      CORE_COUNT="2"
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    else
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    fi
  else
    exit-script
  fi

  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $RAM_SIZE ]; then
      RAM_SIZE="2048"
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    else
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    fi
  else
    exit-script
  fi

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then
      BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      MAC="$GEN_MAC"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
    else
      MAC="$MAC1"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC1${CL}"
    fi
  else
    exit-script
  fi

  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VLAN1 ]; then
      VLAN1="Default"
      VLAN=""
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    else
      VLAN=",tag=$VLAN1"
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    fi
  else
    exit-script
  fi

  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MTU1 ]; then
      MTU1="Default"
      MTU=""
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    else
      MTU=",mtu=$MTU1"
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    fi
  else
    exit-script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Unifi OS VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Unifi OS VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}
check_root
arch_check
pve_check
ssh_check
start_script
post_to_api_vm

msg_info "Validating Storage"
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
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    #if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
    printf "\e[?25h"
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

# Fetch latest UniFi OS Server version and download URL
msg_info "Fetching latest UniFi OS Server version"

# Install jq if not available
if ! command -v jq &>/dev/null; then
  msg_info "Installing jq for JSON parsing"
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y jq -qq >/dev/null 2>&1
fi

# Download firmware list from Ubiquiti API
API_URL="https://fw-update.ui.com/api/firmware-latest"
TEMP_JSON=$(mktemp)

if ! curl -fsSL "$API_URL" -o "$TEMP_JSON"; then
  rm -f "$TEMP_JSON"
  msg_error "Failed to fetch data from Ubiquiti API"
  exit 1
fi

# Parse JSON to find latest unifi-os-server linux-x64 version
LATEST=$(jq -r '
  ._embedded.firmware
  | map(select(.product == "unifi-os-server"))
  | map(select(.platform == "linux-x64"))
  | sort_by(.version_major, .version_minor, .version_patch)
  | last
' "$TEMP_JSON")

UOS_VERSION=$(echo "$LATEST" | jq -r '.version' | sed 's/^v//')
UOS_URL=$(echo "$LATEST" | jq -r '._links.data.href')

# Cleanup temp file
rm -f "$TEMP_JSON"

if [ -z "$UOS_URL" ] || [ -z "$UOS_VERSION" ]; then
  msg_error "Failed to parse UniFi OS Server version or download URL"
  exit 1
fi

UOS_INSTALLER="unifi-os-server-${UOS_VERSION}.bin"
msg_ok "Found UniFi OS Server ${UOS_VERSION}"

# --- Download Cloud Image ---
msg_info "Downloading ${OS_DISPLAY} Cloud Image"
URL=$(get_image_url)
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

msg_ok "Downloaded ${OS_DISPLAY} Cloud Image"

# Expand root partition to use full disk space
msg_info "Expanding disk image to ${DISK_SIZE}"

# Install virt-resize if not available
if ! command -v virt-resize &>/dev/null; then
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools -y >/dev/null
fi

qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE} >/dev/null 2>&1

# Detect partition device (sda1 for Ubuntu, vda1 for Debian)
PARTITION_DEV=$(virt-filesystems --long -h --all -a "${FILE}" | grep -oP '/dev/\K(s|v)da1' | head -1)
if [ -z "$PARTITION_DEV" ]; then
  PARTITION_DEV="sda1" # fallback
fi

virt-resize --quiet --expand /dev/${PARTITION_DEV} ${FILE} expanded.qcow2 >/dev/null 2>&1
mv expanded.qcow2 ${FILE}
msg_ok "Expanded disk image to ${DISK_SIZE}"

msg_info "Creating UniFi OS VM"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf \
  ${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script \
  -net0 virtio,bridge="$BRG",macaddr="$MAC""$VLAN""$MTU" \
  -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

pvesm alloc "$STORAGE" "$VMID" "vm-$VMID-disk-0" 4M >/dev/null
IMPORT_OUT="$(qm importdisk "$VMID" "$FILE" "$STORAGE" --format qcow2 2>&1 || true)"
DISK_REF="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p")"

if [[ -z "$DISK_REF" ]]; then
  DISK_REF="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$1 ~ ("vm-"id"-disk-") {print $1}' | sort | tail -n1)"
fi

qm set "$VMID" \
  -efidisk0 "${STORAGE}:0${FORMAT},size=4M" \
  -scsi0 "${DISK_REF},${DISK_CACHE}size=${DISK_SIZE}" \
  -boot order=scsi0 -serial0 socket >/dev/null
qm resize "$VMID" scsi0 "$DISK_SIZE" >/dev/null
qm set "$VMID" --agent enabled=1 >/dev/null

# Add Cloud-Init drive
msg_info "Configuring Cloud-Init"
setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" >/dev/null 2>&1
msg_ok "Cloud-Init configured"

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Unifi OS VM</h2>

  <p style='margin: 16px 0;'>
    <a href='https://ko-fi.com/community_scripts' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/&#x2615;-Buy us a coffee-blue' alt='spend Coffee' />
    </a>
  </p>

  <span style='margin: 0 10px;'>
    <i class="fa fa-github fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-comments fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/discussions' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Discussions</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-exclamation-circle fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/issues' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Issues</a>
  </span>
</div>
EOF
)
qm set "$VMID" -description "$DESCRIPTION" >/dev/null

msg_ok "Created a UniFi OS VM ${CL}${BL}(${HN})"
msg_info "Operating System: ${OS_DISPLAY}"
msg_info "Cloud-Init: ${USE_CLOUD_INIT}"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting UniFi OS VM"
  qm start $VMID
  msg_ok "Started UniFi OS VM"

  msg_info "Waiting for VM to boot and Cloud-Init to complete (60-90 seconds)"
  sleep 60
  msg_ok "VM boot complete"

  msg_info "Detecting VM IP address"
  VM_IP=""
  for i in {1..30}; do
    VM_IP=$(qm guest cmd $VMID network-get-interfaces 2>/dev/null | jq -r '.[1]["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4") | .["ip-address"]' 2>/dev/null | grep -v "127.0.0.1" | head -1 || echo "")

    if [ -n "$VM_IP" ]; then
      msg_ok "VM IP Address: ${VM_IP}"
      break
    fi
    sleep 2
  done

  if [ -z "$VM_IP" ]; then
    msg_error "Could not detect VM IP address"
    echo -e "${TAB}${INFO}${YW}Use Proxmox Console to login with Cloud-Init credentials${CL}"
    echo -e "${TAB}${INFO}${YW}User: ${BGN}${CLOUDINIT_USER:-root}${CL} / Password: ${BGN}${CLOUDINIT_PASSWORD}${CL}"
    exit 1
  fi

  # Wait for SSH to be ready
  msg_info "Waiting for SSH to be ready"
  SSH_READY=0
  for i in {1..30}; do
    if timeout 5 sshpass -p "${CLOUDINIT_PASSWORD}" ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "${CLOUDINIT_USER:-root}@${VM_IP}" "echo 'SSH Ready'" >/dev/null 2>&1; then
      SSH_READY=1
      msg_ok "SSH connection ready"
      break
    fi
    sleep 2
  done

  if [ $SSH_READY -eq 0 ]; then
    msg_error "SSH connection failed"
    echo -e "${TAB}${INFO}${YW}Manual login - User: ${BGN}${CLOUDINIT_USER:-root}${CL} / Password: ${BGN}${CLOUDINIT_PASSWORD}${CL}"
    exit 1
  fi

  # Check if sshpass is installed
  if ! command -v sshpass &>/dev/null; then
    msg_info "Installing sshpass for automated SSH"
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y sshpass -qq >/dev/null 2>&1
  fi

  # Execute UniFi OS installation directly via SSH
  msg_info "Installing UniFi OS Server ${UOS_VERSION} (takes 4-6 minutes)"

  # Create installation script
  INSTALL_SCRIPT=$(
    cat <<'EOFINSTALL'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[1/5] Updating system packages..."
apt-get update -qq
apt-get install -y curl wget ca-certificates podman uidmap slirp4netns iptables -qq

echo "[2/5] Configuring Podman..."
loginctl enable-linger root

echo "[3/5] Downloading UniFi OS Server installer..."
cd /root
curl -fsSL "UNIFI_URL" -o unifi-installer.bin
chmod +x unifi-installer.bin

echo "[4/5] Installing UniFi OS Server (this takes 3-5 minutes)..."
./unifi-installer.bin install

echo "[5/5] Starting UniFi OS Server..."
sleep 15

if systemctl list-unit-files | grep -q unifi-os-server; then
  systemctl enable unifi-os-server
  systemctl start unifi-os-server
  sleep 10

  if systemctl is-active --quiet unifi-os-server; then
    echo "✓ UniFi OS Server is running"
  else
    echo "⚠ Service status:"
    systemctl status unifi-os-server --no-pager || true
  fi
fi

echo "Installation completed!"
EOFINSTALL
  )

  # Replace URL placeholder
  INSTALL_SCRIPT="${INSTALL_SCRIPT//UNIFI_URL/$UOS_URL}"

  # Execute installation via SSH (with output streaming)
  if sshpass -p "${CLOUDINIT_PASSWORD}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${CLOUDINIT_USER:-root}@${VM_IP}" "bash -s" <<<"$INSTALL_SCRIPT" 2>&1 | while IFS= read -r line; do
    echo -e "${TAB}${DGN}${line}${CL}"
  done; then
    msg_ok "UniFi OS Server installed successfully"
  else
    msg_error "Installation failed"
    echo -e "${TAB}${INFO}${YW}Check logs: ${BL}ssh ${CLOUDINIT_USER:-root}@${VM_IP}${CL}"
    exit 1
  fi

  # Wait for UniFi OS web interface
  msg_info "Waiting for UniFi OS web interface (port 11443)"
  PORT_OPEN=0
  for i in {1..60}; do
    if timeout 2 bash -c ">/dev/tcp/${VM_IP}/11443" 2>/dev/null; then
      PORT_OPEN=1
      msg_ok "UniFi OS Server web interface is ready"
      break
    fi
    sleep 2
  done

  echo ""
  if [ $PORT_OPEN -eq 1 ]; then
    echo -e "${TAB}${GATEWAY}${BOLD}${GN}✓ UniFi OS Server is ready!${CL}"
    echo -e "${TAB}${GATEWAY}${BOLD}${GN}✓ Access at: ${BGN}https://${VM_IP}:11443${CL}"
  else
    echo -e "${TAB}${INFO}${YW}UniFi OS is installed but web interface not yet available${CL}"
    echo -e "${TAB}${INFO}${YW}Access at: ${BGN}https://${VM_IP}:11443${CL} ${YW}(may take 1-2 more minutes)${CL}"
  fi

  echo -e "${TAB}${INFO}${DGN}SSH Access: ${BL}ssh ${CLOUDINIT_USER:-root}@${VM_IP}${CL}"
  echo -e "${TAB}${INFO}${DGN}Password: ${BGN}${CLOUDINIT_PASSWORD}${CL}"
  echo ""
fi

post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"

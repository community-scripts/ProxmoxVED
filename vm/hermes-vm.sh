#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source /dev/stdin <<<$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/api.func")
source /dev/stdin <<<$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/cloud-init.func") 2>/dev/null || true

function header_info() {
  clear
  cat <<"EOF"
    __  __
   / / / /__  _________ ___  ___  _____
  / /_/ / _ \/ ___/ __ `__ \/ _ \/ ___/
 / __  /  __/ /  / / / / / /  __(__  )
/_/ /_/\___/_/  /_/ /_/ /_/\___/____/
                       (NousResearch)
EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="hermes-vm"
var_os="debian"
var_version="13"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
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
  if [ -n "${VMID:-}" ] && qm status "$VMID" &>/dev/null; then qm stop "$VMID" &>/dev/null || true; fi
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

function cleanup() {
  popd >/dev/null 2>&1 || true
  post_update_to_api "done" "none"
  [ -n "${TEMP_DIR:-}" ] && rm -rf "$TEMP_DIR"
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Hermes Agent VM" --yesno "This will create a New Hermes Agent VM on Debian 13. Proceed?" 10 58; then
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

pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"

  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 8.0 – 8.9"
      exit 1
    fi
  elif [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 1)); then
      msg_error "This version of Proxmox VE is not yet supported."
      msg_error "Supported: Proxmox VE version 9.0 – 9.1"
      exit 1
    fi
  else
    msg_error "This version of Proxmox VE is not supported."
    msg_error "Supported versions: Proxmox VE 8.0 – 8.x or 9.0 – 9.1"
    exit 1
  fi
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

function select_cloud_init() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?\n\nCloud-Init allows automatic configuration of:\n- User accounts and passwords\n- SSH keys\n- Network settings (DHCP/Static)\n- DNS configuration\n\nYou can also configure these settings later in Proxmox UI.\n\nNote: Without Cloud-Init, the nocloud image will be used with console auto-login." --defaultno 18 68); then
    CLOUD_INIT="yes"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  else
    CLOUD_INIT="no"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
  fi
}

function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_SIZE="20G"
  DISK_CACHE=""
  HN="hermes"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  select_cloud_init
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Hermes Agent VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 "$VMID" --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
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

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$MACH" = q35 ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 20, 30)" 8 58 "20" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 20 or 20G).${CL}"
      exit-script
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$DISK_CACHE" = "1" ]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 hermes --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VM_NAME" ]; then
      HN="hermes"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else
      HN=$(echo "${VM_NAME,,}" | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')
      if [ "$HN" != "${VM_NAME,,}" ]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "HOSTNAME ADJUSTED" --msgbox "Invalid characters detected. Hostname has been adjusted to:\n\n  $HN" 10 58
      fi
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$CPU_TYPE1" = "1" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  while true; do
    if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$CORE_COUNT" ]; then CORE_COUNT="2"; fi
      if [[ "$CORE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "CPU Cores must be a positive integer (e.g., 2)." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 4096 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$RAM_SIZE" ]; then RAM_SIZE="4096"; fi
      if [[ "$RAM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "RAM Size must be a positive integer in MiB (e.g., 4096)." 8 58
    else
      exit-script
    fi
  done

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$BRG" ]; then
      BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit-script
  fi

  while true; do
    if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 "$GEN_MAC" --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$MAC1" ]; then
        MAC="$GEN_MAC"
        echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
        break
      fi
      if [[ "$MAC1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        MAC="$MAC1"
        echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid MAC address format. Use XX:XX:XX:XX:XX:XX (e.g., AA:BB:CC:DD:EE:FF)." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VLAN1" ]; then
        VLAN1="Default"
        VLAN=""
        echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
        break
      fi
      if [[ "$VLAN1" =~ ^[0-9]+$ ]] && [ "$VLAN1" -ge 1 ] && [ "$VLAN1" -le 4094 ]; then
        VLAN=",tag=$VLAN1"
        echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "VLAN must be a number between 1 and 4094, or leave blank for default." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$MTU1" ]; then
        MTU1="Default"
        MTU=""
        echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
        break
      fi
      if [[ "$MTU1" =~ ^[0-9]+$ ]] && [ "$MTU1" -ge 576 ] && [ "$MTU1" -le 65520 ]; then
        MTU=",mtu=$MTU1"
        echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "MTU Size must be a number between 576 and 65520, or leave blank for default." 8 58
    else
      exit-script
    fi
  done

  select_cloud_init

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Hermes Agent VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Hermes Agent VM using the above advanced settings${CL}"
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
STORAGE_MENU=()
MSG_MAX_LENGTH=0
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
  FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-0} ]]; then
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
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

# ==============================================================================
# PREREQUISITES
# ==============================================================================
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y libguestfs-tools -qq >/dev/null 2>&1
  msg_ok "Installed libguestfs-tools"
fi

msg_info "Retrieving the URL for the Debian 13 Qcow2 Disk Image"
if [ "$CLOUD_INIT" == "yes" ]; then
  URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
else
  URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
fi
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename "$URL")
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# ==============================================================================
# IMAGE CUSTOMIZATION
# ==============================================================================
msg_info "Customizing ${FILE} image"

# Write the firstboot install script to a temp file on the host, then upload it
# into the image. The installer needs live network access (downloads Python 3.11,
# Node.js v22, ripgrep, ffmpeg via uv), so it must run inside the booted VM.
FIRSTBOOT_SCRIPT=$(mktemp)
cat >"$FIRSTBOOT_SCRIPT" <<'FBEOF'
#!/bin/bash
set -e
export HOME=/root
export DEBIAN_FRONTEND=noninteractive
LOG="/var/log/hermes-install.log"
exec > >(tee -a "$LOG") 2>&1

echo "[$(date)] Starting Hermes Agent first-boot installation..."
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
touch /etc/hermes-installed
systemctl disable hermes-install.service
echo "[$(date)] Hermes Agent installation complete."
FBEOF

FIRSTBOOT_SVC=$(mktemp)
cat >"$FIRSTBOOT_SVC" <<'SVCEOF'
[Unit]
Description=Install Hermes Agent (NousResearch) on first boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/etc/hermes-installed

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hermes-install.sh
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

virt-customize -q -a "$FILE" \
  --hostname "${HN}" \
  --run-command "truncate -s 0 /etc/machine-id" \
  --run-command "rm -f /var/lib/dbus/machine-id" \
  --run-command "systemctl disable systemd-firstboot.service 2>/dev/null || true; ln -sf /dev/null /etc/systemd/system/systemd-firstboot.service" \
  --run-command "echo 'Etc/UTC' > /etc/timezone && ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime" \
  --run-command "touch /etc/locale.conf" \
  --install git \
  --upload "$FIRSTBOOT_SCRIPT:/usr/local/bin/hermes-install.sh" \
  --chmod 0755:/usr/local/bin/hermes-install.sh \
  --upload "$FIRSTBOOT_SVC:/etc/systemd/system/hermes-install.service" \
  --run-command "systemctl enable hermes-install.service" \
  >/dev/null 2>&1

if [ "$CLOUD_INIT" == "yes" ]; then
  virt-customize -q -a "$FILE" \
    --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" \
    --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" \
    >/dev/null 2>&1 || true
else
  virt-customize -q -a "$FILE" \
    --run-command "mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d" \
    --write '/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf:[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM' \
    --run-command "mkdir -p /etc/systemd/system/getty@tty1.service.d" \
    --write '/etc/systemd/system/getty@tty1.service.d/autologin.conf:[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM' \
    >/dev/null 2>&1 || true
fi

rm -f "$FIRSTBOOT_SCRIPT" "$FIRSTBOOT_SVC"
msg_ok "Customized image"

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK"${i}"=vm-"${VMID}"-disk-"${i}"${DISK_EXT:-}
  eval DISK"${i}"_REF="${STORAGE}":"${DISK_REF:-}"${!disk}
done

msg_info "Creating a Hermes Agent VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script,hermes -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
if [ "$CLOUD_INIT" == "yes" ]; then
  qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -scsi1 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket >/dev/null
else
  qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -boot order=scsi0 \
    -serial0 socket >/dev/null
fi

msg_info "Resizing disk to ${DISK_SIZE}"
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
msg_ok "Resized disk to ${DISK_SIZE}"

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://hermes-agent.nousresearch.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Hermes Agent VM</h2>

  <p style='margin: 16px 0;'>
    <a href='https://ko-fi.com/community_scripts' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/&#x2615;-Buy us a coffee-blue' alt='spend Coffee' />
    </a>
  </p>

  <p style='margin: 8px 0; font-size: 14px;'>
    Hermes Agent installs automatically on first boot.<br/>
    Monitor: <code>journalctl -u hermes-install.service -f</code><br/>
    Configure: <code>hermes setup</code>
  </p>

  <span style='margin: 0 10px;'>
    <a href='https://github.com/community-scripts/ProxmoxVE' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>
  </span>
  <span style='margin: 0 10px;'>
    <a href='https://github.com/community-scripts/ProxmoxVE/discussions' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Discussions</a>
  </span>
  <span style='margin: 0 10px;'>
    <a href='https://github.com/community-scripts/ProxmoxVE/issues' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Issues</a>
  </span>
</div>
EOF
)
qm set $VMID -description "$DESCRIPTION" >/dev/null

msg_ok "Created a Hermes Agent VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Hermes Agent VM"
  qm start $VMID
  msg_ok "Started Hermes Agent VM"
fi

echo -e "\n${INFO}${BOLD}${YW}Hermes Agent is being installed on first boot.${CL}"
echo -e "${TAB}Monitor progress inside the VM: ${BL}journalctl -u hermes-install.service -f${CL}"
echo -e "${TAB}After install completes, run: ${BL}hermes setup${CL} to configure your LLM provider.\n"
msg_ok "Completed successfully!\n"
echo "More Info at https://hermes-agent.nousresearch.com/docs/getting-started/installation"

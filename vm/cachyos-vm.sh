#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

# ==============================================================================
# CachyOS VM - Creates a CachyOS Virtual Machine
# CachyOS is a performance-focused Arch Linux distribution with optimized 
# packages, custom kernels, and various desktop environment options.
# ==============================================================================

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source /dev/stdin <<<$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/api.func")

function header_info {
  clear
  cat <<"EOF"
   ______           __          ____  _____
  / ____/___ ______/ /_  __  __/ __ \/ ___/
 / /   / __ `/ ___/ __ \/ / / / / / /\__ \ 
/ /___/ /_/ / /__/ / / / /_/ / /_/ /___/ / 
\____/\__,_/\___/_/ /_/\__, /\____//____/  
                      /____/               
         Performance-Optimized Arch Linux
EOF
}

header_info
echo -e "\n Loading..."
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="cachyos-vm"
var_os="cachyos"
var_version=" "
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
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

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  post_update_to_api "failed" "${command}"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  cleanup_vmid
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
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "CachyOS VM" --yesno "This will create a New CachyOS VM.\n\nCachyOS is a performance-optimized Arch Linux distribution with:\n• Custom kernels tuned for performance\n• Optimized packages with LTO/PGO\n• Multiple desktop environments (KDE, GNOME, XFCE, etc.)\n• BORE/EEVDF/sched-ext CPU schedulers\n\nYou will need to complete the installation via the graphical Calamares installer.\n\nProceed?" 18 68; then
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

function pve_check() {
  if ! pveversion | grep -Eq "pve-manager/(8\.[1-4]|9\.[0-1])(\.[0-9]+)*"; then
    msg_error "${CROSS}${RD}This version of Proxmox Virtual Environment is not supported"
    echo -e "Requires Proxmox Virtual Environment Version 8.1 - 8.4 or 9.0 - 9.1."
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}${YW}This script will not work with PiMox! \n"
    echo -e "\n ${YW}Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
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

# ==============================================================================
# DEFAULT SETTINGS - Optimized for desktop usage with GUI
# ==============================================================================
function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=""
  MACHINE=" -machine q35"
  DISK_SIZE="40G"
  DISK_CACHE=""
  HN="cachyos"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="4"
  RAM_SIZE="8192"
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
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host (Recommended for CachyOS optimizations)${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE} MiB${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a CachyOS VM using the above default settings${CL}"
}

# ==============================================================================
# ADVANCED SETTINGS
# ==============================================================================
function advanced_settings() {
  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)

  # VM ID
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

  # Machine Type
  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "q35" "Q35 (Modern, PCIe - Recommended)" ON \
    "i440fx" "i440fx (Legacy, PCI)" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
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

  # Disk Size
  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (Recommended: 40+ for desktop)" 8 58 "40" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 40 or 40G).${CL}"
      exit-script
    fi
  else
    exit-script
  fi

  # Disk Cache
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

  # Hostname
  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 cachyos --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="cachyos"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
    fi
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
  else
    exit-script
  fi

  # CPU Model
  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose (Host recommended for CachyOS optimizations)" --cancel-button Exit-Script 10 68 2 \
    "1" "Host (Recommended - enables x86-64-v3/v4)" ON \
    "0" "KVM64 (Compatible)" OFF \
    3>&1 1>&2 2>&3); then
    if [ $CPU_TYPE1 = "1" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  # CPU Cores
  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores (Recommended: 4+ for desktop)" 8 58 4 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $CORE_COUNT ]; then
      CORE_COUNT="4"
    fi
    echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
  else
    exit-script
  fi

  # RAM Size
  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB (Recommended: 8192+ for desktop)" 8 58 8192 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $RAM_SIZE ]; then
      RAM_SIZE="8192"
    fi
    echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE MiB${CL}"
  else
    exit-script
  fi

  # Bridge
  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then
      BRG="vmbr0"
    fi
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
  else
    exit-script
  fi

  # MAC Address
  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      MAC="$GEN_MAC"
    else
      MAC="$MAC1"
    fi
    echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
  else
    exit-script
  fi

  # VLAN
  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan (leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VLAN1 ]; then
      VLAN1="Default"
      VLAN=""
    else
      VLAN=",tag=$VLAN1"
    fi
    echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
  else
    exit-script
  fi

  # MTU
  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MTU1 ]; then
      MTU1="Default"
      MTU=""
    else
      MTU=",mtu=$MTU1"
    fi
    echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
  else
    exit-script
  fi

  # Start VM
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  # Confirm
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a CachyOS VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a CachyOS VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?\n\nDefaults are optimized for desktop usage:\n• 4 CPU Cores (Host model)\n• 8 GB RAM\n• 40 GB Disk\n• Q35 Machine Type" --no-button Advanced 14 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
check_root
arch_check
pve_check
ssh_check
start_script
post_to_api_vm

# ==============================================================================
# STORAGE SELECTION
# ==============================================================================
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
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

# ==============================================================================
# ISO DOWNLOAD
# ==============================================================================
msg_info "Retrieving the URL for the CachyOS Desktop ISO"

# Get latest release version from SourceForge (format: YYMMDD in folder links)
CACHYOS_VERSION=$(curl -fsSL "https://sourceforge.net/projects/cachyos-arch/files/gui-installer/desktop/" 2>/dev/null | grep -oP 'desktop/\K[0-9]{6}(?=/)' | sort -rn | head -1)
if [ -z "$CACHYOS_VERSION" ]; then
  CACHYOS_VERSION="260124"
fi

# SourceForge download URL with mirror redirect
URL="https://sourceforge.net/projects/cachyos-arch/files/gui-installer/desktop/${CACHYOS_VERSION}/cachyos-desktop-linux-${CACHYOS_VERSION}.iso/download"
FILENAME="cachyos-desktop-linux-${CACHYOS_VERSION}.iso"
CACHE_DIR="/var/lib/vz/template/iso"
CACHE_FILE="${CACHE_DIR}/${FILENAME}"

mkdir -p "$CACHE_DIR"
msg_ok "${CL}${BL}CachyOS Desktop ISO (Release: ${CACHYOS_VERSION})${CL}"

if [[ -s "$CACHE_FILE" ]]; then
  msg_ok "Using cached ISO ${CL}${BL}${FILENAME}${CL}"
else
  msg_info "Downloading CachyOS ISO (approximately 3.1 GB, this may take a while)"
  if curl -fSL -o "$CACHE_FILE" -L "$URL"; then
    echo -en "\e[1A\e[0K"
    msg_ok "Downloaded ${CL}${BL}${FILENAME}${CL}"
  else
    msg_error "Failed to download CachyOS ISO"
    exit 1
  fi
fi

# ==============================================================================
# VM CREATION
# ==============================================================================
msg_info "Creating a CachyOS VM"

qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 0 -ostype l26 -scsihw virtio-scsi-pci \
  -efidisk0 ${STORAGE}:1,efitype=4m,pre-enrolled-keys=0 -scsi0 ${STORAGE}:${DISK_SIZE},${DISK_CACHE}${THIN%,} \
  -cdrom local:iso/${FILENAME} -vga qxl -serial0 socket >/dev/null

msg_ok "Created a CachyOS VM ${CL}${BL}(${HN})"

# ==============================================================================
# VM DESCRIPTION
# ==============================================================================
DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>CachyOS VM</h2>

  <p style='font-size: 14px; margin: 10px 0;'>
    Performance-optimized Arch Linux with custom kernels,<br/>
    BORE/EEVDF schedulers, and x86-64-v3/v4 optimizations.
  </p>

  <p style='margin: 16px 0;'>
    <a href='https://ko-fi.com/community_scripts' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/&#x2615;-Buy us a coffee-blue' alt='Buy us a coffee' />
    </a>
  </p>

  <span style='margin: 0 10px;'>
    <i class="fa fa-globe fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://cachyos.org/' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>CachyOS Website</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-book fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://wiki.cachyos.org/' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Wiki</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-github fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/CachyOS' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>
  </span>
</div>
EOF
)
qm set "$VMID" -description "$DESCRIPTION" >/dev/null

msg_ok "Created a CachyOS VM ${CL}${BL}(${HN})"

# ==============================================================================
# START VM
# ==============================================================================
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting CachyOS VM"
  qm start $VMID
  msg_ok "Started CachyOS VM"
fi

post_update_to_api "done" "none"

# ==============================================================================
# FINAL OUTPUT
# ==============================================================================
echo -e "\n${INFO}${BOLD}${GN}CachyOS VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
echo -e "${TAB}${DGN}RAM: ${BGN}${RAM_SIZE} MiB${CL}"
echo -e "${TAB}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"

echo -e "\n${INFO}${BOLD}${YW}Next Steps:${CL}"
echo -e "${TAB}1. Open the VM Console in Proxmox (noVNC or SPICE)"
echo -e "${TAB}2. Boot from the CachyOS ISO"
echo -e "${TAB}3. Use the Calamares installer to complete installation"
echo -e "${TAB}4. Choose your preferred desktop environment during setup:"
echo -e "${TAB}   ${BL}KDE Plasma, GNOME, XFCE, Hyprland, i3, and more${CL}"
echo -e "${TAB}5. After installation, remove the ISO from VM settings"
echo -e "${TAB}6. Change boot order to boot from disk (scsi0)"

echo -e "\n${INFO}${BOLD}${GN}CachyOS Features:${CL}"
echo -e "${TAB}• Custom linux-cachyos kernel with BORE scheduler"
echo -e "${TAB}• x86-64-v3/v4 optimized packages (auto-detected)"
echo -e "${TAB}• LTO/PGO optimized applications"
echo -e "${TAB}• Multiple filesystem options: btrfs, ext4, xfs, f2fs, zfs"

msg_ok "Completed successfully!\n"

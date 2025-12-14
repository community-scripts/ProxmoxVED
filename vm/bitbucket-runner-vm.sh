#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Roberto (ComeCaramelos)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://support.atlassian.com/bitbucket-cloud/docs/runners/

source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)

function header_info() {
  clear
  cat <<"EOF"
    ____  _ __  __                __        __    ____
   / __ )(_) /_/ /_  __  _ _____/ /_____  / /_   / __ \__  ______  ____  ___  _____
  / __  / / __/ __ \/ / / / ___/ //_/ _ \/ __/  / /_/ / / / / __ \/ __ \/ _ \/ ___/
 / /_/ / / /_/ /_/ / /_/ / /__/ ,< /  __/ /_   / _, _/ /_/ / / / / / / /  __/ /
/_____/_/\__/_.___/\__,_/\___/_/|_|\___/\__/  /_/ |_|\__,_/_/ /_/_/ /_/\___/_/

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="bitbucket-runner-vm"
var_os="debian"
var_version="12"
DISK_SIZE="10G"
var_cpu="2"
var_ram="8192"
var_brg="vmbr0"
var_mac="$GEN_MAC"
var_vlan=""
var_mtu=""
var_net="dhcp"
var_ip=""
var_gateway=""
var_dns=""

YW=$(echo "\033[33m")
YWB=$(echo "\033[33;1m")
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
CLOUD="${TAB}☁️${TAB}${CL}"

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
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  post_update_to_api "failed" "${command}"
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
  post_update_to_api "done" "none"
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Bitbucket Runner VM" --yesno "This will create a New Bitbucket Runner VM. Proceed?" 10 58; then
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
      msg_error "Supported: Proxmox VE version 8.0 - 8.9"
      exit 1
    fi
    return 0
  fi
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 1)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 9.0 - 9.1"
      exit 1
    fi
    return 0
  fi
  msg_error "This version of Proxmox VE is not supported."
  msg_error "Supported versions: Proxmox VE 8.0 - 8.x or 9.0 - 9.1"
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

function get_bitbucket_creds() {
  if [ -z "$ACCOUNT_UUID" ]; then
    if ! ACCOUNT_UUID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter Account UUID (mandatory)" 10 58 --title "Bitbucket Config" 3>&1 1>&2 2>&3); then exit-script; fi
  fi
  if [ -z "$ACCOUNT_UUID" ]; then msg_error "Account UUID is mandatory"; exit; fi
  
  if [ -z "$REPOSITORY_UUID" ]; then
    if ! REPOSITORY_UUID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter Repository UUID (optional, leave empty for workspace runner)" 10 58 --title "Bitbucket Config" 3>&1 1>&2 2>&3); then exit-script; fi
  fi
  
  if [ -z "$RUNNER_UUID" ]; then
    if ! RUNNER_UUID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter Runner UUID (mandatory)" 10 58 --title "Bitbucket Config" 3>&1 1>&2 2>&3); then exit-script; fi
  fi
  if [ -z "$RUNNER_UUID" ]; then msg_error "Runner UUID is mandatory"; exit; fi

  if [ -z "$OAUTH_CLIENT_ID" ]; then
    if ! OAUTH_CLIENT_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter OAuth Client ID (mandatory)" 10 58 --title "Bitbucket Config" 3>&1 1>&2 2>&3); then exit-script; fi
  fi
  if [ -z "$OAUTH_CLIENT_ID" ]; then msg_error "OAuth Client ID is mandatory"; exit; fi

  if [ -z "$OAUTH_CLIENT_SECRET" ]; then
    if ! OAUTH_CLIENT_SECRET=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Enter OAuth Client Secret (mandatory)" 10 58 --title "Bitbucket Config" 3>&1 1>&2 2>&3); then exit-script; fi
  fi
  if [ -z "$OAUTH_CLIENT_SECRET" ]; then msg_error "OAuth Client Secret is mandatory"; exit; fi

  if [ -z "$var_pw" ]; then
    if ! var_pw=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Set Root Password" 10 58 --title "ROOT PASSWORD" 3>&1 1>&2 2>&3); then exit-script; fi
  fi


  if [ -z "$var_ssh_authorized_key" ]; then
    if ! var_ssh_authorized_key=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter SSH Public Key (optional)" 10 58 --title "SSH KEYS" 3>&1 1>&2 2>&3); then exit-script; fi
  fi

  # Sanitize UUIDs: remove {}, remove whitespace, convert to lower case
  ACCOUNT_UUID=$(echo "$ACCOUNT_UUID" | tr -d '{}[:space:]' | tr '[:upper:]' '[:lower:]')
  if [[ -n "$REPOSITORY_UUID" ]]; then
    REPOSITORY_UUID=$(echo "$REPOSITORY_UUID" | tr -d '{}[:space:]' | tr '[:upper:]' '[:lower:]')
  fi
  RUNNER_UUID=$(echo "$RUNNER_UUID" | tr -d '{}[:space:]' | tr '[:upper:]' '[:lower:]')


  if [[ ! "$ACCOUNT_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    msg_error "Invalid Account UUID format: $ACCOUNT_UUID"
    exit
  fi
  if [[ -n "$REPOSITORY_UUID" ]] && [[ ! "$REPOSITORY_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    msg_error "Invalid Repository UUID format: $REPOSITORY_UUID"
    exit
  fi
  if [[ ! "$RUNNER_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    msg_error "Invalid Runner UUID format: $RUNNER_UUID"
    exit
  fi


  ACCOUNT_UUID="{${ACCOUNT_UUID}}"
  RUNNER_UUID="{${RUNNER_UUID}}"
  if [[ -n "$REPOSITORY_UUID" ]]; then
    REPOSITORY_UUID="{${REPOSITORY_UUID}}"
  fi

  echo -e "${INFO}${BOLD}${DGN}Bitbucket credentials collected and validated${CL}"
}

function default_settings() {
  [ -z "${var_vmid}" ] && var_vmid=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""
  [ -z "${DISK_SIZE}" ] && DISK_SIZE="10G"
  [ -z "${HN}" ] && HN="bitbucket-runner"
  CPU_TYPE=""
  [ -z "${var_cpu}" ] && var_cpu="2"
  [ -z "${var_ram}" ] && var_ram="8192"
  [ -z "${var_brg}" ] && var_brg="vmbr0"
  [ -z "${var_mac}" ] && var_mac="$GEN_MAC"
  [ -z "${var_vlan}" ] && var_vlan=""
  [ -z "${var_mtu}" ] && var_mtu=""
  [ -z "${var_net}" ] && var_net="dhcp"
  [ -z "${var_ip}" ] && var_ip=""
  [ -z "${var_gateway}" ] && var_gateway=""
  [ -z "${var_dns}" ] && var_dns=""
  [ -z "${var_ssh}" ] && var_ssh="yes"
  START_VM="yes"
  METHOD="default"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${var_vmid}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${var_cpu}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${var_ram}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${var_brg}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${var_mac}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Network Type: ${BGN}DHCP${CL}"
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
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Bitbucket Runner VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  [ -z "${var_vmid:-}" ] && var_vmid=$(get_valid_nextid)
  while true; do
    if var_vmid=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $var_vmid --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$var_vmid" ]; then
        var_vmid=$(get_valid_nextid)
      fi
      if pct status "$var_vmid" &>/dev/null || qm status "$var_vmid" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $var_vmid is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$var_vmid${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
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

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 bitbucket-runner --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="bitbucket-runner"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
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

  if var_cpu=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $var_cpu ]; then
      var_cpu="2"
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$var_cpu${CL}"
    else
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$var_cpu${CL}"
    fi
  else
    exit-script
  fi

  if var_ram=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 8192 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $var_ram ]; then
      var_ram="8192"
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$var_ram${CL}"
    else
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$var_ram${CL}"
    fi
  else
    exit-script
  fi

  if var_brg=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $var_brg ]; then
      var_brg="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$var_brg${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$var_brg${CL}"
    fi
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      var_mac="$GEN_MAC"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$var_mac${CL}"
    else
      var_mac="$MAC1"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$var_mac${CL}"
    fi
  else
    exit-script
  fi

  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan (leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VLAN1 ]; then
      VLAN1="Default"
      var_vlan=""
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    else
      var_vlan=",tag=$VLAN1"
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    fi
  else
    exit-script
  fi

  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MTU1 ]; then
      MTU1="Default"
      var_mtu=""
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    else
      var_mtu=",mtu=$MTU1"
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    fi
  else
    exit-script
  fi

  if var_net=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "NETWORK CONFIGURATION" --radiolist "Choose Network Type" --cancel-button Exit-Script 10 58 2 \
    "dhcp" "DHCP (Default)" ON \
    "static" "Static IP" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$var_net" = "static" ]; then
      if var_ip=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set IP Address (CIDR format, e.g., 192.168.1.50/24)" 8 58 --title "STATIC IP" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$var_ip" ]; then msg_error "IP Address is mandatory for Static IP"; exit; fi
      else exit-script; fi

      if var_gateway=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Gateway IP" 8 58 --title "GATEWAY" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$var_gateway" ]; then msg_error "Gateway is mandatory for Static IP"; exit; fi
      else exit-script; fi
      
      if var_dns=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set DNS Server (optional, leave blank for host default)" 8 58 --title "DNS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        :
      else exit-script; fi
      
      echo -e "${DEFAULT}${BOLD}${DGN}Network Type: ${BGN}Static${CL}"
      echo -e "${DEFAULT}${BOLD}${DGN}IP Address: ${BGN}$var_ip${CL}"
      echo -e "${DEFAULT}${BOLD}${DGN}Gateway: ${BGN}$var_gateway${CL}"
    else
      echo -e "${DEFAULT}${BOLD}${DGN}Network Type: ${BGN}DHCP${CL}"
    fi
  else
    exit-script
  fi

  if var_ssh=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SSH ACCESS" --radiolist "Enable SSH Access?" --cancel-button Exit-Script 10 58 2 \
    "yes" "Enable SSH (Default)" ON \
    "no" "Disable SSH" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$var_ssh" = "yes" ]; then
      echo -e "${DEFAULT}${BOLD}${DGN}SSH Access: ${BGN}Enabled${CL}"
    else
      echo -e "${DEFAULT}${BOLD}${DGN}SSH Access: ${BGN}Disabled${CL}"
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

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Bitbucket Runner VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Bitbucket Runner VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if [ -n "$ACCOUNT_UUID" ]; then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Unattended Settings${CL}"
    default_settings
  elif (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
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
get_bitbucket_creds
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
elif [ -n "$var_storage" ]; then
  STORAGE="$var_storage"
elif [ -n "$ACCOUNT_UUID" ] && [ -n "${STORAGE_MENU[0]}" ]; then
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
msg_ok "Virtual Machine ID is ${CL}${BL}$var_vmid${CL}."
msg_info "Retrieving the URL for the Debian 12 Qcow2 Disk Image"
URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-$(dpkg --print-architecture).qcow2"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$var_vmid/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$var_vmid/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${var_vmid}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing Pre-Requisite libguestfs-tools onto Host"
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools lsb-release -y >/dev/null
  # Workaround for Proxmox VE 9.0 libguestfs issue
  apt-get -qq install dhcpcd-base -y >/dev/null 2>&1 || true
  msg_ok "Installed libguestfs-tools successfully"
fi

msg_info "Generating Bitbucket Runner Configuration"

# Create docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3'
services:
  runner:
    image: docker-public.packages.atlassian.com/sox/atlassian/bitbucket-pipelines-runner:latest
    container_name: bitbucket-runner
    environment:
      - ACCOUNT_UUID=${ACCOUNT_UUID}
      - REPOSITORY_UUID=${REPOSITORY_UUID}
      - RUNNER_UUID=${RUNNER_UUID}
      - OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID}
      - OAUTH_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}
      - WORKING_DIRECTORY=/opt/atlassian/bitbucketci/agent/build
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /opt/bitbucket_runner/data:/opt/atlassian/bitbucketci/agent/build
    restart: unless-stopped
EOF

# Create systemd service
cat <<EOF > bitbucket-runner.service
[Unit]
Description=Bitbucket Runner via Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=simple
WorkingDirectory=/opt/bitbucket_runner
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always

[Install]
WantedBy=multi-user.target
EOF

msg_ok "Configuration Generated"

msg_info "Installing Prerequisites"
virt-customize -q -a "${FILE}" --install qemu-guest-agent,apt-transport-https,ca-certificates,curl,gnupg,software-properties-common,lsb-release >/dev/null
msg_ok "Installed Prerequisites"

msg_info "Installing Docker"
virt-customize -q -a "${FILE}" \
  --run-command "mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg" \
  --run-command "echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable' > /etc/apt/sources.list.d/docker.list" \
  --run-command "apt-get update -qq && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin" \
  --run-command "systemctl enable docker" >/dev/null
msg_ok "Installed Docker"

if [ "$var_ssh" = "yes" ]; then
  msg_info "Configuring SSH Access"
  virt-customize -q -a "${FILE}" \
    --install openssh-server \
    --run-command "sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" \
    --run-command "systemctl enable ssh" >/dev/null
  msg_ok "Configured SSH Access"
fi

msg_info "Configuring Bitbucket Runner Service"
virt-customize -q -a "${FILE}" \
  --run-command "mkdir -p /opt/bitbucket_runner/data && chmod 777 /opt/bitbucket_runner/data" \
  --upload docker-compose.yml:/opt/bitbucket_runner/docker-compose.yml \
  --upload bitbucket-runner.service:/etc/systemd/system/bitbucket-runner.service \
  --run-command "systemctl enable bitbucket-runner.service" >/dev/null
msg_ok "Configured Bitbucket Runner"

msg_info "Finalizing System Configuration"
virt-customize -q -a "${FILE}" \
  --root-password password:"${var_pw}" \
  --hostname "${HN}" \
  --run-command "echo 'kernel.printk = 3 4 1 3' > /etc/sysctl.d/20-quiet-console.conf" \
  --run-command "echo -n > /etc/machine-id" >/dev/null

if [ -n "$var_ssh_authorized_key" ]; then
  virt-customize -q -a "${FILE}" --ssh-inject root:string:"$var_ssh_authorized_key" >/dev/null
fi


msg_ok "Image Customized Successfully"

msg_info "Expanding root partition to use full disk space"
qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE} >/dev/null 2>&1
virt-resize --expand /dev/sda1 ${FILE} expanded.qcow2 >/dev/null 2>&1
mv expanded.qcow2 ${FILE} >/dev/null 2>&1
msg_ok "Expanded image to full size"

msg_info "Creating a Bitbucket Runner VM"
qm create $var_vmid -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $var_cpu -memory $var_ram \
  -name $HN -tags community-script -net0 virtio,bridge=$var_brg,macaddr=$var_mac$var_vlan$var_mtu -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $var_vmid $DISK0 4M 1>&/dev/null
qm importdisk $var_vmid ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $var_vmid \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -ide2 ${STORAGE}:cloudinit \
  -boot order=scsi0 \
  -serial0 socket >/dev/null

# Network Configuration using Cloud-Init
if [ "$var_net" = "static" ]; then
  qm set $var_vmid -ipconfig0 ip=$var_ip,gw=$var_gateway >/dev/null
  if [ -n "$var_dns" ]; then
    qm set $var_vmid -nameserver $var_dns >/dev/null
  fi
else
  qm set $var_vmid -ipconfig0 ip=dhcp >/dev/null
fi

qm set $var_vmid --agent enabled=1 >/dev/null

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Bitbucket Runner VM</h2>

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
qm set "$var_vmid" -description "$DESCRIPTION" >/dev/null

msg_ok "Created a Bitbucket Runner VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Bitbucket Runner VM"
  qm start $var_vmid
  msg_ok "Started Bitbucket Runner VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"

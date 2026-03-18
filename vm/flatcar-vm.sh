#!/usr/bin/env bash

# Copyright (c) 2026.03.18 Artur Zdoliński
# License: MIT
# Flatcar Container Linux VM - Deploy / Rebuild
# Supports proxmoxve (cloud-init) and qemu (fw_cfg) images
# Auto-detects flatcar.yaml, import storage, image versions
# Ignition configs stored in /etc/pve/ignition/ (pmxcfs - shared across cluster)

function header_info {
  clear
  cat <<"EOF"
    ________      __                     __    _
   / ____/ /___ _/ /__________ ______   / /   (_)___  __  ___  __
  / /_  / / __ `/ __/ ___/ __ `/ ___/  / /   / / __ \/ / / / |/_/
 / __/ / / /_/ / /_/ /__/ /_/ / /     / /___/ / / / / /_/ />  <
/_/   /_/\__,_/\__/\___/\__,_/_/     /_____/_/_/ /_/\__,_/_/|_|
     Container Linux (Immutable + Docker)
EOF
}

header_info
echo -e "\n Loading..."

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
METHOD=""
NSAPP="flatcar-vm"
var_os="flatcar"

BASE_URL="https://stable.release.flatcar-linux.net/amd64-usr/current"
PROXMOXVE_IMG="flatcar_production_proxmoxve_image.img"
QEMU_IMG="flatcar_production_qemu_image.img"

# Shared ignition config directory (pmxcfs - accessible on all cluster nodes)
IGN_DIR="/etc/pve/ignition"

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
CLOUD="${TAB}☁️${TAB}${CL}"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
}

function cleanup() {
  popd >/dev/null 2>&1 || true
  rm -rf "${TEMP_DIR:-}" 2>/dev/null || true
}

ORIG_DIR="$(pwd)"
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

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

function ignition_notice() {
  echo -e "\n  ${RD}⚠️  IMPORTANT:${CL} Ignition config is only applied on the FIRST boot of a new"
  echo -e "  system disk. Subsequent reboots will NOT re-read the ignition file."
  echo -e "  To apply config changes, you must rebuild scsi0 (re-deploy), which will"
  echo -e "  destroy all data stored on the system disk. For this reason, it is"
  echo -e "  strongly recommended to add a separate data disk (scsi1) and store"
  echo -e "  all critical data there (Docker volumes, configs, databases, etc.).\n"
}

function exit-script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================
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
  if ! command -v pveversion &>/dev/null; then
    msg_error "This script must be run on a Proxmox VE host."
    exit 1
  fi
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    msg_error "Flatcar Container Linux only supports amd64 architecture."
    exit 1
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

function check_butane() {
  if ! command -v butane &>/dev/null; then
    if whiptail --backtitle "Proxmox VE Helper Scripts" --title "BUTANE NOT FOUND" --yesno "Butane transpiler is required but not installed.\n\nInstall it now?" 10 58; then
      msg_info "Installing butane"
      wget -qO /usr/local/bin/butane https://github.com/coreos/butane/releases/latest/download/butane-x86_64-unknown-linux-gnu
      chmod +x /usr/local/bin/butane
      msg_ok "Installed butane"
    else
      msg_error "Butane is required. Cannot continue."
      exit 1
    fi
  fi
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

# ==============================================================================
# FLATCAR.YAML DETECTION
# ==============================================================================
function find_config_yaml() {
  CONFIG_YAML=""

  if [[ -f "$ORIG_DIR/flatcar.yaml" ]]; then
    CONFIG_YAML="$(realpath "$ORIG_DIR/flatcar.yaml")"
    return 0
  fi

  if [[ -f "$HOME/flatcar.yaml" ]]; then
    CONFIG_YAML="$(realpath "$HOME/flatcar.yaml")"
    return 0
  fi

  local KNOWN_PATHS=()
  while IFS= read -r path_line; do
    local P
    P=$(echo "$path_line" | awk '{print $2}')
    [[ -n "$P" ]] && KNOWN_PATHS+=("$P/snippets/flatcar.yaml")
  done < <(grep "^\s*path " /etc/pve/storage.cfg 2>/dev/null)
  KNOWN_PATHS+=("/var/lib/vz/snippets/flatcar.yaml")

  for CHECK_PATH in "${KNOWN_PATHS[@]}"; do
    if [[ -f "$CHECK_PATH" ]]; then
      CONFIG_YAML="$CHECK_PATH"
      return 0
    fi
  done

  return 1
}

# ==============================================================================
# IMPORT STORAGE DETECTION
# ==============================================================================
function find_import_storage() {
  declare -g -a IMPORT_STORAGES=()
  declare -g -a IMPORT_PATHS=()

  while IFS= read -r line; do
    local S_NAME S_STATUS
    S_NAME=$(echo "$line" | awk '{print $1}')
    S_STATUS=$(echo "$line" | awk '{print $3}')

    if [[ "$S_STATUS" == "active" ]]; then
      local S_PATH
      S_PATH=$(awk -v name="$S_NAME" '
        $2 == name { found=1; next }
        found && /^\s*path / { print $2; exit }
        found && /^[^ ]/ { exit }
      ' /etc/pve/storage.cfg 2>/dev/null)

      if [[ -n "$S_PATH" ]]; then
        IMPORT_STORAGES+=("$S_NAME")
        IMPORT_PATHS+=("$S_PATH/import")
      fi
    fi
  done < <(pvesm status --content import 2>/dev/null | tail -n +2)

  local ALREADY_HAS_LOCAL=false
  for s in "${IMPORT_STORAGES[@]}"; do
    [[ "$s" == "local" ]] && ALREADY_HAS_LOCAL=true
  done
  if [[ "$ALREADY_HAS_LOCAL" == false && -d "/var/lib/vz/import" ]]; then
    IMPORT_STORAGES=("local" "${IMPORT_STORAGES[@]}")
    IMPORT_PATHS=("/var/lib/vz/import" "${IMPORT_PATHS[@]}")
  fi

  if [[ ${#IMPORT_STORAGES[@]} -eq 0 ]]; then
    IMPORT_STORAGES+=("local")
    IMPORT_PATHS+=("/var/lib/vz/import")
  fi
}

# ==============================================================================
# COMPILE & DEPLOY IGNITION (cluster-shared via /etc/pve/ignition/)
# ==============================================================================
function setup_ignition() {
  IGN_FILENAME="vm-${VMID}.ign"
  CONFIG_IGN="${IGN_DIR}/${IGN_FILENAME}"

  # Ensure shared ignition directory exists (pmxcfs - replicated to all nodes)
  mkdir -p "$IGN_DIR"

  msg_info "Generating ignition config (${IGN_FILENAME})"
  butane --pretty --strict < "$CONFIG_YAML" > "$CONFIG_IGN"
  msg_ok "Ignition saved: ${CL}${BL}${CONFIG_IGN}${CL} ${GN}(cluster-shared)"
}

function attach_ignition() {
  if [[ "$USE_IGNITION" != "true" ]]; then
    msg_info "Setting up Cloud-Init (no ignition)"
    qm set "$VMID" --ide2 "$STORAGE:cloudinit" >/dev/null
    qm set "$VMID" --ipconfig0 "ip=dhcp" >/dev/null
    msg_ok "Cloud-Init configured (use Proxmox UI for SSH keys, network, etc.)"
    return
  fi

  # Both image types use fw_cfg for ignition delivery from shared /etc/pve/ignition/
  # This ensures cluster-wide accessibility without snippet storage dependency
  if [[ "$IMG_TYPE" == "proxmoxve" ]]; then
    msg_info "Setting up Cloud-Init (network) + fw_cfg Ignition"
    qm set "$VMID" --ide2 "$STORAGE:cloudinit" >/dev/null
    qm set "$VMID" --ipconfig0 "ip=dhcp" >/dev/null
    qm set "$VMID" --args "-fw_cfg name=opt/org.flatcar-linux/config,file=${CONFIG_IGN}" >/dev/null
    msg_ok "Cloud-Init (network) + fw_cfg Ignition (${CONFIG_IGN})"
  else
    msg_info "Setting up fw_cfg Ignition"
    qm set "$VMID" --args "-fw_cfg name=opt/org.flatcar-linux/config,file=${CONFIG_IGN}" >/dev/null
    msg_ok "fw_cfg Ignition (${CONFIG_IGN})"
  fi
}

function reattach_ignition() {
  if [[ "$USE_IGNITION" != "true" ]]; then
    return
  fi

  if [[ "$IMG_TYPE" == "proxmoxve" ]]; then
    # Ensure cloudinit drive exists for network config
    if ! qm config "$VMID" 2>/dev/null | grep -q "^ide2.*cloudinit"; then
      msg_info "Recreating Cloud-Init drive"
      qm set "$VMID" --ide2 "$STORAGE:cloudinit" >/dev/null
      msg_ok "Cloud-Init drive recreated"
    fi
    qm set "$VMID" --ipconfig0 "ip=dhcp" >/dev/null
    # Remove any old cicustom reference (migration from snippet-based setup)
    qm set "$VMID" --delete cicustom 2>/dev/null || true
    qm set "$VMID" --args "-fw_cfg name=opt/org.flatcar-linux/config,file=${CONFIG_IGN}" >/dev/null
    msg_ok "Ignition reattached via fw_cfg (${CONFIG_IGN})"
  else
    qm set "$VMID" --args "-fw_cfg name=opt/org.flatcar-linux/config,file=${CONFIG_IGN}" >/dev/null
    msg_ok "fw_cfg Ignition reattached (${CONFIG_IGN})"
  fi
}

# ==============================================================================
# IMAGE VERSION CHECK
# ==============================================================================
function check_and_update_image() {
  local IMG_FILE="$1"
  local IMPORT_PATH="$2"

  local TEMPLATE_IMG="$IMPORT_PATH/$IMG_FILE"
  local LOCAL_DIGESTS="$IMPORT_PATH/$IMG_FILE.DIGESTS"
  local REMOTE_URL="$BASE_URL/$IMG_FILE"
  local REMOTE_DIGESTS_URL="$BASE_URL/$IMG_FILE.DIGESTS"

  msg_info "Checking image version for $IMG_FILE"
  local REMOTE_DIGESTS REMOTE_MD5
  REMOTE_DIGESTS=$(wget -qO- "$REMOTE_DIGESTS_URL" 2>/dev/null) || { msg_error "Failed to fetch DIGESTS"; return 1; }
  REMOTE_MD5=$(echo "$REMOTE_DIGESTS" | grep -A1 "MD5" | tail -1 | awk '{print $1}')

  if [[ -z "$REMOTE_MD5" ]]; then
    msg_error "Failed to parse MD5 from DIGESTS"
    return 1
  fi

  local NEED_DOWNLOAD=false

  if [[ ! -f "$TEMPLATE_IMG" ]]; then
    msg_ok "Image not found locally - download required"
    NEED_DOWNLOAD=true
  elif [[ ! -f "$LOCAL_DIGESTS" ]]; then
    local LOCAL_MD5
    LOCAL_MD5=$(md5sum "$TEMPLATE_IMG" | awk '{print $1}')
    if [[ "$LOCAL_MD5" != "$REMOTE_MD5" ]]; then
      msg_ok "Hash mismatch - newer version available"
      NEED_DOWNLOAD=true
    else
      echo "$REMOTE_DIGESTS" > "$LOCAL_DIGESTS"
      msg_ok "Image is up to date (MD5: ${LOCAL_MD5:0:12}...)"
    fi
  else
    local LOCAL_MD5
    LOCAL_MD5=$(grep -A1 "MD5" "$LOCAL_DIGESTS" | tail -1 | awk '{print $1}')
    if [[ "$LOCAL_MD5" != "$REMOTE_MD5" ]]; then
      msg_ok "Newer image version available"
      NEED_DOWNLOAD=true
    else
      msg_ok "Image is up to date (MD5: ${LOCAL_MD5:0:12}...)"
    fi
  fi

  if [[ "$NEED_DOWNLOAD" == true ]]; then
    if whiptail --backtitle "Proxmox VE Helper Scripts" --title "IMAGE UPDATE" --yesno "A new version of $IMG_FILE is available (or image is missing).\n\nDownload now?\n\nDestination: $IMPORT_PATH" 14 68; then
      msg_info "Downloading $IMG_FILE"
      mkdir -p "$IMPORT_PATH"
      wget --show-progress -O "$TEMPLATE_IMG.tmp" "$REMOTE_URL" || { msg_error "Download failed"; return 1; }
      echo -en "\e[1A\e[0K"

      msg_info "Verifying download"
      local DL_MD5
      DL_MD5=$(md5sum "$TEMPLATE_IMG.tmp" | awk '{print $1}')
      if [[ "$DL_MD5" != "$REMOTE_MD5" ]]; then
        rm -f "$TEMPLATE_IMG.tmp"
        msg_error "MD5 verification failed!"
        return 1
      fi
      mv "$TEMPLATE_IMG.tmp" "$TEMPLATE_IMG"
      echo "$REMOTE_DIGESTS" > "$LOCAL_DIGESTS"
      msg_ok "Downloaded and verified $IMG_FILE"
    else
      if [[ ! -f "$TEMPLATE_IMG" ]]; then
        msg_error "No local image available. Cannot continue."
        exit 1
      fi
      msg_ok "Continuing with existing image"
    fi
  fi
}

# ==============================================================================
# VM DISK STORAGE SELECTION
# ==============================================================================
function select_vm_storage() {
  local LABEL="${1:-Hard Drive (scsi0)}"

  msg_info "Validating Storage"
  STORAGE_MENU=()
  MSG_MAX_LENGTH=0
  while read -r line; do
    TAG=$(echo "$line" | awk '{print $1}')
    TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
    FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
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
    exit 1
  elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
    STORAGE=${STORAGE_MENU[0]}
  else
    while [ -z "${STORAGE:+x}" ]; do
      STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
        "Which storage pool would you like to use for ${LABEL}?\nTo make a selection, use the Spacebar.\n" \
        16 $(($MSG_MAX_LENGTH + 23)) 6 \
        "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit-script
    done
  fi
  msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
}

# ==============================================================================
# IMPORT & ATTACH DISK
# ==============================================================================
function import_and_attach_disk() {
  msg_info "Importing Flatcar disk image to $STORAGE"
  qm importdisk "$VMID" "$TEMPLATE_IMG" "$STORAGE" 2>/dev/null
  echo -en "\e[1A\e[0K"

  UNUSED_DISK=$(qm config "$VMID" 2>/dev/null | grep "^unused" | head -1 | awk '{print $2}')
  if [[ -n "$UNUSED_DISK" ]]; then
    qm set "$VMID" --scsi0 "$UNUSED_DISK" >/dev/null
  else
    STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
    case $STORAGE_TYPE in
      lvm|lvmthin|zfspool) qm set "$VMID" --scsi0 "$STORAGE:vm-$VMID-disk-0" >/dev/null ;;
      *) qm set "$VMID" --scsi0 "$STORAGE:$VMID/vm-$VMID-disk-0.raw" >/dev/null ;;
    esac
  fi
  qm set "$VMID" --boot order=scsi0 >/dev/null
  msg_ok "Imported and attached disk"
}

# ==============================================================================
# SETTINGS
# ==============================================================================
function default_settings() {
  VMID=$(get_valid_nextid)
  DISK_SIZE=""
  HN="flatcar"
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}Auto (image default)${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Image: ${BGN}${IMG_TYPE}${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Provisioning: ${BGN}${PROVISION_MODE}${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Flatcar Container Linux VM using the above default settings${CL}"
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

  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Expand disk by (GiB, 0 = image default)" 8 58 "0" --title "DISK EXPANSION" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" == "0" || -z "$DISK_SIZE" ]]; then
      DISK_SIZE=""
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}Auto (image default)${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Expansion: ${BGN}+${DISK_SIZE}G${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid size.${CL}"
      exit-script
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 flatcar --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VM_NAME" ]; then
      HN="flatcar"
    else
      HN=$(echo "${VM_NAME,,}" | tr -d ' ')
    fi
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
  else
    exit-script
  fi

  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$CORE_COUNT" ] && CORE_COUNT="2"
    echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
  else
    exit-script
  fi

  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$RAM_SIZE" ] && RAM_SIZE="2048"
    echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
  else
    exit-script
  fi

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$BRG" ] && BRG="vmbr0"
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 "$GEN_MAC" --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$MAC1" ] && MAC1="$GEN_MAC"
    MAC="$MAC1"
    echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
  else
    exit-script
  fi

  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a VLAN (leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VLAN1" ]; then
      VLAN=""
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
    else
      VLAN=",tag=$VLAN1"
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    fi
  else
    exit-script
  fi

  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$MTU1" ]; then
      MTU=""
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
    else
      MTU=",mtu=$MTU1"
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    fi
  else
    exit-script
  fi

  echo -e "${CLOUD}${BOLD}${DGN}Image: ${BGN}${IMG_TYPE}${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Provisioning: ${BGN}${PROVISION_MODE}${CL}"

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    START_VM="yes"
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  else
    START_VM="no"
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Flatcar Container Linux VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Flatcar Container Linux VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Hardware Virtual Machine Default Settings?\n\n  VM ID:       Auto (next available)\n  Hostname:    flatcar\n  CPU Cores:   2\n
RAM:         2048 MiB\n  Disk:        Image default\n  Bridge:      vmbr0\n  VLAN:        None\n  MTU:         Default\n  Start VM:    Yes" --no-button Advanced 20 58); then
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
# PREFLIGHT
# ==============================================================================
check_root
arch_check
pve_check
ssh_check

# ==============================================================================
# FIND FLATCAR.YAML
# ==============================================================================
msg_info "Searching for flatcar.yaml"
if find_config_yaml; then
  msg_ok "Found config: ${CL}${BL}$CONFIG_YAML${CL}"
else
  msg_error "flatcar.yaml not found!"
  echo -e "\n  Create a Butane YAML config before running this script."
  echo -e "  Expected locations:\n"
  echo -e "    1. ./flatcar.yaml"
  echo -e "    2. ~/flatcar.yaml"
  echo -e "    3. <storage>/snippets/flatcar.yaml\n"
  echo -e "  Butane YAML examples & documentation:"
  echo -e "    ${BL}https://coreos.github.io/butane/examples/${CL}\n"
  exit 1
fi

# ==============================================================================
# DETECT IMPORT STORAGE
# ==============================================================================
msg_info "Detecting import storages"
find_import_storage

if [[ ${#IMPORT_STORAGES[@]} -eq 1 ]]; then
  IMPORT_STORAGE_NAME="${IMPORT_STORAGES[0]}"
  IMPORT_PATH="${IMPORT_PATHS[0]}"
else
  IMPORT_MENU=()
  for i in "${!IMPORT_STORAGES[@]}"; do
    IMPORT_MENU+=("${IMPORT_STORAGES[$i]}" "  ${IMPORT_PATHS[$i]}" "OFF")
  done
  IMPORT_MENU[2]="ON"

  IMPORT_STORAGE_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Import Storage" --radiolist \
    "Select storage for Flatcar images:\n" \
    14 68 ${#IMPORT_STORAGES[@]} \
    "${IMPORT_MENU[@]}" 3>&1 1>&2 2>&3) || exit-script

  for i in "${!IMPORT_STORAGES[@]}"; do
    if [[ "${IMPORT_STORAGES[$i]}" == "$IMPORT_STORAGE_NAME" ]]; then
      IMPORT_PATH="${IMPORT_PATHS[$i]}"
      break
    fi
  done
fi
mkdir -p "$IMPORT_PATH"
msg_ok "Import storage: ${CL}${BL}$IMPORT_STORAGE_NAME${CL} ${GN}($IMPORT_PATH)"

# ==============================================================================
# SELECT IMAGE TYPE
# ==============================================================================
PROXMOXVE_STATUS="NOT DOWNLOADED"
QEMU_STATUS="NOT DOWNLOADED"
if [[ -f "$IMPORT_PATH/$PROXMOXVE_IMG" && -f "$IMPORT_PATH/$PROXMOXVE_IMG.DIGESTS" ]]; then
  PVE_MD5=$(grep -A1 "MD5" "$IMPORT_PATH/$PROXMOXVE_IMG.DIGESTS" | tail -1 | awk '{print substr($1,length($1)-6)}')
  PROXMOXVE_STATUS="EXIST md5:...${PVE_MD5}"
fi
if [[ -f "$IMPORT_PATH/$QEMU_IMG" && -f "$IMPORT_PATH/$QEMU_IMG.DIGESTS" ]]; then
  QEMU_MD5=$(grep -A1 "MD5" "$IMPORT_PATH/$QEMU_IMG.DIGESTS" | tail -1 | awk '{print substr($1,length($1)-6)}')
  QEMU_STATUS="EXIST md5:...${QEMU_MD5}"
fi

IMG_TYPE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "FLATCAR IMAGE TYPE" --radiolist \
  "Select image type:\n\nproxmoxve: Uses cloud-init for network + fw_cfg for ignition\nqemu: Uses QEMU fw_cfg for ignition delivery\n" \
  16 68 2 \
  "proxmoxve" "  cloud-init + fw_cfg  [$PROXMOXVE_STATUS]" ON \
  "qemu" "  fw_cfg only          [$QEMU_STATUS]" OFF \
  3>&1 1>&2 2>&3) || exit-script

if [[ "$IMG_TYPE" == "proxmoxve" ]]; then
  IMG_FILE="$PROXMOXVE_IMG"
else
  IMG_FILE="$QEMU_IMG"
fi
TEMPLATE_IMG="$IMPORT_PATH/$IMG_FILE"
msg_ok "Image type: ${CL}${BL}$IMG_TYPE${CL}"

# ==============================================================================
# PROVISIONING MODE (proxmoxve: cloud-init vs ignition)
# ==============================================================================
USE_IGNITION="true"
PROVISION_MODE="Ignition (flatcar.yaml)"

if [[ "$IMG_TYPE" == "proxmoxve" ]]; then
  PROV_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "PROVISIONING METHOD" --radiolist \
    "How should this VM be provisioned?\n\nIgnition and Cloud-Init are mutually exclusive.\nIgnition uses flatcar.yaml (Butane) for full system config.\nCloud-Init uses Proxmox UI for basic setup (SSH keys, network).\n" \
    18 72 2 \
    "ignition" "  Ignition via flatcar.yaml (recommended)" ON \
    "cloudinit" "  Cloud-Init only (basic, no ignition)" OFF \
    3>&1 1>&2 2>&3) || exit-script

  if [[ "$PROV_CHOICE" == "cloudinit" ]]; then
    USE_IGNITION="false"
    PROVISION_MODE="Cloud-Init only"
    msg_ok "Provisioning: ${CL}${BL}Cloud-Init only${CL} ${GN}(configure via Proxmox UI)"
  else
    msg_ok "Provisioning: ${CL}${BL}Ignition via fw_cfg${CL} ${GN}(${IGN_DIR}/)"
  fi
else
  msg_ok "Provisioning: ${CL}${BL}Ignition via fw_cfg${CL} ${GN}(${IGN_DIR}/)"
fi

# Check butane only if ignition is needed
if [[ "$USE_IGNITION" == "true" ]]; then
  check_butane
fi

# ==============================================================================
# CHECK IMAGE VERSION
# ==============================================================================
check_and_update_image "$IMG_FILE" "$IMPORT_PATH"

# ==============================================================================
# CREATE NEW vs REBUILD EXISTING
# ==============================================================================
REBUILD_MODE=false
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Flatcar Container Linux VM" --yesno "What would you like to do?" --yes-button "Create New" --no-button "Rebuild Existing" 10 58; then
  REBUILD_MODE=false
else
  REBUILD_MODE=true
fi

if [[ "$REBUILD_MODE" == true ]]; then
  # ============================================================================
  # REBUILD EXISTING VM
  # ============================================================================
  VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter VM ID to rebuild:" 8 58 --title "REBUILD VM" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit-script

  if ! qm status "$VMID" &>/dev/null; then
    msg_error "VM $VMID does not exist!"
    exit 1
  fi

  VM_NAME_CURRENT=$(qm config "$VMID" 2>/dev/null | grep "^name:" | awk '{print $2}')
  VM_STATUS=$(qm status "$VMID" 2>/dev/null | awk '{print $2}')
  HN="${VM_NAME_CURRENT:-flatcar}"

  if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "⚠️  REBUILD WARNING" --yesno \
    "VM $VMID ($VM_NAME_CURRENT) - Status: $VM_STATUS\n\nThis will DESTROY the system disk (scsi0)!\nAll data on scsi0 will be permanently lost.\nOther disks (scsi1, scsi2...) will NOT be affected.\n\nActions:\n  1. Stop the VM (if running)\n  2. Delete system disk (scsi0)\n  3. Import fresh Flatcar image\n  4. Apply ignition config and boot\n\nSelect REBUILD to continue." \
    --yes-button "REBUILD" --no-button "Cancel" 22 68; then
    msg_error "Rebuild cancelled."
    exit 0
  fi

  # Compile ignition (if needed)
  if [[ "$USE_IGNITION" == "true" ]]; then
    setup_ignition
  fi

  # Select VM disk storage
  select_vm_storage "${HN} Hard Drive (scsi0)"

  if [[ "$VM_STATUS" == "running" ]]; then
    msg_info "Stopping VM $VMID"
    qm stop "$VMID" --timeout 30 || true
    sleep 3
    msg_ok "Stopped VM $VMID"
  fi

  msg_info "Removing old system disk"
  qm set "$VMID" --delete scsi0 2>/dev/null || true
  while IFS= read -r line; do
    KEY=$(echo "$line" | cut -d: -f1)
    qm set "$VMID" --delete "$KEY" 2>/dev/null || true
  done < <(qm config "$VMID" 2>/dev/null | grep "^unused")
  msg_ok "Removed old disk"

  import_and_attach_disk
  reattach_ignition

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "⚠️  START VM" --yesno \
    "Rebuild complete. Start VM $VMID now?\n\nWARNING: Starting the VM will trigger the first boot\nand apply the ignition config permanently.\nThis action cannot be undone without another rebuild." \
    --yes-button "Start Now" --no-button "Don't Start" 14 64); then
    msg_info "Starting VM $VMID"
    qm start "$VMID"
    msg_ok "Started VM $VMID"
    msg_ok "Rebuild complete! VM ${CL}${BL}$VMID ($VM_NAME_CURRENT)${CL} ${GN}is booting with fresh system."
    ignition_notice
  else
    msg_ok "Rebuild complete! VM ${CL}${BL}$VMID ($VM_NAME_CURRENT)${CL} ${GN}is ready but NOT started."
    echo -e "\n  ${INFO}${YW}Start manually when ready: ${CL}${BL}qm start $VMID${CL}"
    ignition_notice
  fi

else
  # ============================================================================
  # CREATE NEW VM
  # ============================================================================
  start_script

  # Compile ignition (if needed)
  if [[ "$USE_IGNITION" == "true" ]]; then
    setup_ignition
  fi

  # Select VM disk storage
  select_vm_storage "${HN} Hard Drive (scsi0)"
  msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

  # Create VM
  msg_info "Creating Flatcar Container Linux VM"
  qm create $VMID -agent 1 -tablet 0 -localtime 1 -cores $CORE_COUNT -memory $RAM_SIZE \
    -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU \
    -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
  msg_ok "Created VM shell"

  import_and_attach_disk
  attach_ignition

  # Expand disk if requested
  if [[ -n "$DISK_SIZE" && "$DISK_SIZE" != "0" ]]; then
    msg_info "Expanding disk by ${DISK_SIZE}G"
    qm resize "$VMID" scsi0 "+${DISK_SIZE}G" >/dev/null
    msg_ok "Disk expanded by ${DISK_SIZE}G"
  fi

  # Add serial console
  qm set "$VMID" --serial0 socket >/dev/null 2>&1 || true

  # Set description
  DESCRIPTION=$(cat <<EOF
<div align='center'>
  <h2 style='font-size: 24px; margin: 20px 0;'>Flatcar Container Linux</h2>
  <p>Immutable OS with Docker pre-installed</p>
  <p><b>Image:</b> ${IMG_TYPE} | <b>Provisioning:</b> ${PROVISION_MODE}</p>
  <p><b>Ignition:</b> ${IGN_DIR}/vm-${VMID}.ign (cluster-shared)</p>
</div>
EOF
  )
  qm set "$VMID" -description "$DESCRIPTION" >/dev/null

  if [ "$START_VM" == "yes" ]; then
    msg_info "Starting Flatcar Container Linux VM"
    qm start $VMID
    msg_ok "Started Flatcar Container Linux VM"
  fi

  msg_ok "Completed successfully!\n"
  echo -e "  ${INFO}${YW}Ignition config:               ${CL}${BL}${IGN_DIR}/vm-${VMID}.ign${CL}"
  echo -e "  ${INFO}${YW}Rebuild scsi0 with ignition:   ${CL}${BL}Re-run this script and select 'Rebuild Existing'${CL}"
  echo -e "  ${INFO}${YW}Add Data disk (scsi1):         ${CL}${BL}qm set $VMID --scsi1 $STORAGE:50${CL}\n"
  ignition_notice
fi

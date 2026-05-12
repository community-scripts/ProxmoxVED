#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}/misc/vm-core.func")
load_functions

function header_info {
  clear
  cat <<"EOF"
   __  ____                __           ___   ______ ____  __ __     _    ____  ___
  / / / / /_  __  ______  / /___  __   |__ \ / ____// __ \/ // /    | |  / /  |/  /
 / / / / __ \/ / / / __ \/ __/ / / /   __/ //___ \ / / / / // /_    | | / / /|_/ / 
/ /_/ / /_/ / /_/ / / / / /_/ /_/ /   / __/____/ // /_/ /__  __/    | |/ / /  / /  
\____/_.___/\__,_/_/ /_/\__/\__,_/   /____/_____(_)____/  /_/       |___/_/  /_/ (Plucky Puffin)
                                                                                   
EOF
}

APP="Ubuntu 26.04 VM"
APP_TYPE="vm"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="ubuntu2604-vm"
var_os="ubuntu"
var_version="2604"
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"

# ---------- Defaults ----------
VMID=""
MACHINE_TYPE=""
DISK_SIZE="7G"
DISK_CACHE=""
HN="ubuntu"
CPU_TYPE=""                 # only the CPU model name (e.g. host, kvm64)
CORE_COUNT="2"
RAM_SIZE="2048"
BRG="vmbr0"
MAC="$GEN_MAC"
VLAN=""
MTU=""
START_VM="yes"
FAST_BOOT="no"
STORAGE_PRESET=""
CLI_MODE=false
# -----------------------------

# ---------- Valid CPU models (built-in) ----------
VALID_CPU_TYPES="host kvm64 qemu64 max x86-64-v2-AES x86-64-v3 x86-64-v4"
# --------------------------------------------------

# ---------- Parse command line arguments ----------
while [[ $# -gt 0 ]]; do
  _flag="${1//$'\r'/}"
  _flag="${_flag#"${_flag%%[![:space:]]*}"}"
  _flag="${_flag%"${_flag##*[![:space:]]}"}"
  case "$_flag" in
    -cpu) CORE_COUNT="$2"; shift 2; CLI_MODE=true ;;
    -ram) RAM_SIZE="$2"; shift 2; CLI_MODE=true ;;
    -name) HN="$2"; shift 2; CLI_MODE=true ;;
    -vlan) VLAN=",tag=$2"; shift 2; CLI_MODE=true ;;
    -cpu-type)
      CPU_TYPE="$2"
      # validate
      if ! echo "$VALID_CPU_TYPES" | grep -qw "$CPU_TYPE"; then
        echo "Error: Invalid CPU model '$CPU_TYPE'."
        echo "Valid built-in models: $VALID_CPU_TYPES"
        echo "For machine type, use -machine (e.g. -machine q35)"
        exit 1
      fi
      shift 2
      CLI_MODE=true
      ;;
    -disk) DISK_SIZE="$2"; shift 2; CLI_MODE=true ;;
    -bridge) BRG="$2"; shift 2; CLI_MODE=true ;;
    -mac) MAC="$2"; shift 2; CLI_MODE=true ;;
    -mtu) MTU=",mtu=$2"; shift 2; CLI_MODE=true ;;
    -start) START_VM="$2"; shift 2; CLI_MODE=true ;;
    -vmid) VMID="$2"; shift 2; CLI_MODE=true ;;
    -storage) STORAGE_PRESET="$2"; shift 2; CLI_MODE=true ;;
    -cloudinit) USE_CLOUD_INIT="$2"; shift 2; CLI_MODE=true ;;
    -fast-boot) FAST_BOOT="$2"; shift 2; CLI_MODE=true ;;
    -machine) MACHINE_TYPE="$2"; shift 2; CLI_MODE=true ;;
    *) echo "Unknown option: ${_flag:-$1}"; exit 1 ;;
  esac
done
# ---------------------------------------------------

if ! $CLI_MODE; then
  header_info
fi
echo -e "\n Loading..."

set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

# If CLI mode, skip the confirmation prompt
if $CLI_MODE; then
  : # no confirmation needed
else
  if vm_confirm_new_vm "$APP" "This will create a New $APP. Proceed?"; then
    :
  else
    header_info && exit_script
  fi
fi

check_root
arch_check
pve_check
ssh_check

# Cloud‑init prompt only in interactive mode
if $CLI_MODE; then
  : ${USE_CLOUD_INIT:="no"}
  : ${FAST_BOOT:="no"}
  if [[ "$USE_CLOUD_INIT" == "yes" ]] && declare -f load_cloud_init_functions >/dev/null 2>&1; then
    load_cloud_init_functions
  fi
else
  vm_prompt_cloud_init "ubuntu"
fi

function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="7G"
  DISK_CACHE=""
  HN="ubuntu"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  FAST_BOOT="no"
  METHOD="default"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$(vm_machine_type_label "$MACHINE_TYPE")${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Fast boot: ${BGN}${FAST_BOOT}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 26.04 VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Fast boot: ${BGN}${FAST_BOOT}${CL}"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "${DISK_SIZE:-7G}" "Set Disk Size in GiB (e.g., 10, 20)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "ubuntu"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Ubuntu 26.04 VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 26.04 VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function cli_settings_display() {
  [[ -z "$MACHINE_TYPE" ]] && MACHINE_TYPE="q35"
  vm_apply_machine_type "$MACHINE_TYPE"

  [[ -z "$VMID" ]] && VMID=$(get_valid_nextid)

  local cpu_display="${CPU_TYPE:-KVM64}"
  local vlan_display="Default"
  [[ -n "$VLAN" ]] && vlan_display="${VLAN#,tag=}"
  local mtu_display="Default"
  [[ -n "$MTU" ]] && mtu_display="${MTU#,mtu=}"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$(vm_machine_type_label "$MACHINE_TYPE")${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}${DISK_CACHE:-None}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Storage pool: ${BGN}${STORAGE_PRESET:-Prompt}${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}${cpu_display}${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Fast boot: ${BGN}${FAST_BOOT}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}${vlan_display}${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}${mtu_display}${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 26.04 VM with the above settings${CL}"
}

function start_script() {
  if $CLI_MODE; then
    METHOD="cli"
    echo -e "${DEFAULT}${BOLD}${BL}Using Command-Line Settings${CL}"
    cli_settings_display
  else
    if vm_choose_settings_mode; then
      header_info
      echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
      default_settings
    else
      header_info
      echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
      advanced_settings
    fi
  fi
}

start_script

if qm status "$VMID" &>/dev/null; then
  msg_error "VM ID ${VMID} already exists on this node. Use another -vmid or destroy VM ${VMID} first."
  exit 1
fi

post_to_api_vm

if [[ -n "$STORAGE_PRESET" ]]; then
  msg_info "Validating Storage"
  if ! pvesm status -content images 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$STORAGE_PRESET"; then
    msg_error "Unknown storage '${STORAGE_PRESET}', or it does not support content type 'images'."
    exit 1
  fi
  STORAGE="$STORAGE_PRESET"
  STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
  vm_apply_storage_layout "$STORAGE_TYPE"
  msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
  msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
else
  vm_select_storage "$HN"
fi
vm_define_disk_references 2
DISK_IMPORT="-format ${DISK_IMPORT_FORMAT}"

msg_info "Retrieving the URL for the Ubuntu 26.04 Disk Image"
URL="https://cloud-images.ubuntu.com/releases/server/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -fsSL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE="$(basename "$URL")"
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

msg_info "Creating a Ubuntu 26.04 VM"
# Build the -cpu part separately if CPU_TYPE is not empty
CPU_OPT=""
[[ -n "$CPU_TYPE" ]] && CPU_OPT="-cpu $CPU_TYPE"

qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf $CPU_OPT -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID $FILE $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
set_description

msg_info "Resizing disk to $DISK_SIZE"
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f setup_cloud_init >/dev/null 2>&1; then
  _ci_user="${CLOUDINIT_USER:-ubuntu}"
  _ci_net="${CLOUDINIT_NETWORK_MODE:-dhcp}"
  _ci_ip="${CLOUDINIT_IP:-}"
  _ci_gw="${CLOUDINIT_GW:-}"
  _ci_dns="${CLOUDINIT_DNS:-${CLOUDINIT_DNS_SERVERS:-1.1.1.1 8.8.8.8}}"
  setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "$_ci_user" "$_ci_net" "$_ci_ip" "$_ci_gw" "$_ci_dns"
  qm set "$VMID" -boot order=scsi0 >/dev/null 2>&1 || true
  if [ "$FAST_BOOT" = "yes" ]; then
    qm set "$VMID" --ciupgrade 0 >/dev/null 2>&1 || true
  fi
  qm cloudinit update "$VMID" >/dev/null 2>&1 || true
fi

msg_ok "Created a Ubuntu 26.04 VM ${CL}${BL}(${HN})"
if [ "$START_VM" = "yes" ]; then
  msg_info "Starting Ubuntu 26.04 VM"
  qm start $VMID
  msg_ok "Started Ubuntu 26.04 VM"
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"
if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f display_cloud_init_info >/dev/null 2>&1; then
  display_cloud_init_info "$VMID" "$HN"
elif [ "$USE_CLOUD_INIT" = "yes" ]; then
  msg_warn "Cloud-init helpers did not load; use VM → Cloud-Init in the UI if needed."
else
  echo -e "Cloud-Init is disabled. The VM disk was resized on the Proxmox side only.\nIf the guest does not auto-expand its root filesystem after first boot, expand it manually inside the VM.\n\nMore info at https://github.com/community-scripts/ProxmoxVED/discussions/272 \n"
fi


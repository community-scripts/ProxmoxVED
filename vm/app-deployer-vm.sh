#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

# ==============================================================================
# APP DEPLOYER VM - Deploy LXC Applications Inside a Virtual Machine
# ==============================================================================
#
# Creates a VM (Debian 12/13, Ubuntu 22.04/24.04) and deploys any LXC
# application inside it using the existing install scripts.
#
# Usage:
#   bash app-deployer-vm.sh                  # Interactive mode
#   APP=yamtrack bash app-deployer-vm.sh     # Pre-select application
#
# Update the application later (inside the VM):
#   bash /opt/community-scripts/update-app.sh
#
# ==============================================================================

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func") 2>/dev/null
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func") 2>/dev/null
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/vm/cloud-init.func") 2>/dev/null || true
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-app.func") 2>/dev/null
load_functions

# ==============================================================================
# SCRIPT VARIABLES
# ==============================================================================
APP="${APP:-App Deployer}"
APP_TYPE="vm"
NSAPP="app-deployer-vm"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
DISK_SIZE="20G"
USE_CLOUD_INIT="no"
OS_TYPE=""
OS_VERSION=""
THIN="discard=on,ssd=1,"
APP_INSTALL_SCRIPT=""

# ==============================================================================
# ERROR HANDLING & CLEANUP
# ==============================================================================
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

# ==============================================================================
# SETTINGS FUNCTIONS
# ==============================================================================
function default_settings() {
  vm_apply_machine_type "q35"
  # App & OS selection (always interactive)
  select_app "${PRE_APP:-}"
  get_app_metadata
  select_vm_os

  # SSH Key selection for Cloud-Init VMs
  if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f configure_cloudinit_ssh_keys >/dev/null 2>&1; then
    configure_cloudinit_ssh_keys || true
  fi

  # Use app-recommended resources (with reasonable VM minimums)
  local min_disk=$((APP_DISK > 10 ? APP_DISK : 10))
  local min_ram=$((APP_RAM > 2048 ? APP_RAM : 2048))

  VMID=$(get_valid_nextid)
  DISK_CACHE=""
  DISK_SIZE="${min_disk}G"
  HN="${APP_INSTALL_SCRIPT}"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="${APP_CPU}"
  RAM_SIZE="${min_ram}"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  # Update NSAPP and APP for descriptions
  NSAPP="${APP_INSTALL_SCRIPT}-vm"
  APP="${APP_NAME}"

  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "${min_disk}G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "${APP_INSTALL_SCRIPT}"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "${APP_CPU}"
  vm_prompt_ram "${min_ram}"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a ${APP:-App Deployer} VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a ${APP:-App Deployer} VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}


# ==============================================================================
# STORAGE SELECTION (same pattern as docker-vm.sh)
# ==============================================================================
select_storage() {
  vm_select_storage "$HN"
  msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

  # Detect storage type for disk format
  STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
  case $STORAGE_TYPE in
  nfs | dir)
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    DISK_IMPORT="--format qcow2"
    THIN=""
    ;;
  btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="--format raw"
    FORMAT=",efitype=4m"
    THIN=""
    ;;
  *)
    DISK_EXT=""
    DISK_REF=""
    DISK_IMPORT=""
    ;;
  esac
}

# ==============================================================================
# MAIN
# ==============================================================================
header_info

check_root
arch_check
pve_check

# Support pre-selecting app via environment variable
if [[ -n "${APP_SELECT:-}" ]]; then
  PRE_APP="${APP_SELECT}"
else
  PRE_APP=""
fi

if whiptail --backtitle "Proxmox VE Helper Scripts" --title "App Deployer VM" --yesno \
  "This will create a new VM and deploy an LXC application inside it.\n\nSupported OS: Debian 12/13, Ubuntu 22.04/24.04\n\nProceed?" 14 68; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

select_storage

# Build the App VM
build_app_vm

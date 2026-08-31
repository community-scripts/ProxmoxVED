#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

# ==============================================================================
# CachyOS VM - Creates a CachyOS Virtual Machine
# CachyOS is a performance-focused Arch Linux distribution with optimized
# packages, custom kernels, and various desktop environment options.
#
# Unlike the cloud-image VMs here, this one boots an installer ISO: the disks
# are allocated by qm create and the user finishes the install in Calamares.
# That is why there is no qm importdisk and no cloud-init.
# ==============================================================================

source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="CachyOS"
APP_TYPE="vm"
NSAPP="cachyos-vm"
var_os="cachyos"
var_version=" "
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
THIN="discard=on,ssd=1,"

header_info
echo -e "\n Loading..."

set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

if vm_confirm_new_vm "$APP" "This will create a New CachyOS VM.\n\nCachyOS is a performance-optimized Arch Linux distribution with:\n• Custom kernels tuned for performance\n• Optimized packages with LTO/PGO\n• Multiple desktop environments (KDE, GNOME, XFCE, etc.)\n• BORE/EEVDF/sched-ext CPU schedulers\n\nYou will need to complete the installation via the graphical Calamares installer.\n\nProceed?"; then
  :
else
  header_info && exit_script
fi

check_root
arch_check
pve_check
ssh_check

# ==============================================================================
# DEFAULT SETTINGS - Optimized for desktop usage with GUI
# ==============================================================================
function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
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
  vm_echo_default_settings
}

# ==============================================================================
# ADVANCED SETTINGS
# ==============================================================================
function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "40G" "Set Disk Size in GiB (Recommended: 40+ for desktop)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "cachyos"
  # host rather than kvm64: the optimised packages and the custom kernel are the
  # reason to run CachyOS, and a generic CPU model gives most of that away.
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "8192"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a CachyOS VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a CachyOS VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
vm_start_script "Use Default Settings?\n\nDefaults are optimized for desktop usage:\n• 4 CPU Cores (Host model)\n• 8 GB RAM\n• 40 GB Disk\n• Q35 Machine Type" 14 58
post_to_api_vm

vm_select_storage "$HN"

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

set_description

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

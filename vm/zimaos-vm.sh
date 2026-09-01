#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/IceWhaleTech/ZimaOS

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="ZimaOS"
APP_TYPE="vm"
NSAPP="zimaos-vm"
var_os="zimaos"
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

if vm_confirm_new_vm "$APP" "This will create a new ZimaOS VM.\n\nZimaOS is the successor to CasaOS: a NAS operating system with an app store, ZFS-backed storage and A/B system updates.\n\nInstallation is completed in the graphical installer after the VM boots.\n\nProceed?"; then
  :
else
  header_info && exit_script
fi

check_root
arch_check
pve_check
ssh_check

function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="64G"
  DISK_CACHE=""
  HN="zimaos"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="4"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "64G" "Set Disk Size in GiB (Recommended: 64+ for apps)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "zimaos"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a ZimaOS VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a ZimaOS VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 4 CPU Cores (Host model)\n• 4 GB RAM\n• 64 GB Disk\n• Q35 Machine Type" 14 58
post_to_api_vm

vm_select_storage "$HN"

msg_info "Retrieving the URL for the ZimaOS installer"

# Older guides import a ready-made .img as the system disk. Since 1.x IceWhale
# only ships an installer, so this boots the ISO and lets it write the disk.
RELEASE_API="https://api.github.com/repos/IceWhaleTech/ZimaOS/releases/latest"
URL=$(curl -fsSL "$RELEASE_API" 2>/dev/null | grep -oP '"browser_download_url":\s*"\K[^"]+_installer\.iso' | head -1)
if [[ -z "$URL" ]]; then
  msg_error "Could not determine the current ZimaOS installer"
  msg_error "GitHub rate-limits unauthenticated requests to 60 per hour; try again shortly."
  exit 1
fi

FILENAME="$(basename "$URL")"
ZIMAOS_VERSION="$(echo "$FILENAME" | grep -oP 'zimaos-x86_64-\K[0-9.]+(?=_installer)')"
CACHE_DIR="/var/lib/vz/template/iso"
CACHE_FILE="${CACHE_DIR}/${FILENAME}"

mkdir -p "$CACHE_DIR"
msg_ok "ZimaOS ${CL}${BL}${ZIMAOS_VERSION}${CL}"

# A redirect to an error page still returns 200, so the size decides whether
# this is really an ISO, not curl's exit code.
MIN_ISO_BYTES=$((1024 * 1024 * 1024))

msg_info "Downloading ZimaOS installer (approximately 2 GB, this may take a while)"
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes "$MIN_ISO_BYTES" || exit 115

msg_info "Creating a ZimaOS VM"

# ZimaOS needs UEFI with Secure Boot off. pre-enrolled-keys=0 does that here,
# which saves the manual trip through the OVMF device manager that the upstream
# Proxmox guide describes. VirtIO SCSI single is what IceWhale documents.
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-single \
  -efidisk0 ${STORAGE}:1,efitype=4m,pre-enrolled-keys=0 -scsi0 ${STORAGE}:${DISK_SIZE%G},${DISK_CACHE}${THIN%,} \
  -cdrom local:iso/${FILENAME} -boot order='scsi0;ide2' -vga std -serial0 socket >/dev/null

set_description

msg_ok "Created a ZimaOS VM ${CL}${BL}(${HN})"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting ZimaOS VM"
  qm start $VMID
  msg_ok "Started ZimaOS VM"
fi

post_update_to_api "done" "none"

echo -e "\n${INFO}${BOLD}${GN}ZimaOS VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}Version: ${BGN}${ZIMAOS_VERSION}${CL}"
echo -e "${TAB}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"

echo -e "\n${INFO}${BOLD}${YW}Next Steps:${CL}"
echo -e "${TAB}1. Open the VM Console in Proxmox"
echo -e "${TAB}2. Follow the installer and select ${BL}scsi0${CL} as the target disk"
echo -e "${TAB}3. When it says ${BL}Remove Disk and Reboot${CL}, just reboot -- the boot"
echo -e "${TAB}   order prefers the disk, so the installed system wins from here on"
echo -e "${TAB}4. Detach the ISO afterwards to tidy up (Hardware -> CD/DVD -> Remove)"

echo -e "\n${INFO}${BOLD}${YW}Finding the VM:${CL}"
echo -e "${TAB}ZimaOS does not print its IP on the console. Read it from the"
echo -e "${TAB}Proxmox summary once the guest agent is up, or use ${BL}https://find.zimaspace.com${CL}."

echo -e "\n${INFO}${BOLD}${GN}Storage:${CL}"
echo -e "${TAB}For a real NAS, add a second disk in Proxmox and let ZimaOS"
echo -e "${TAB}manage it. Keeping data off the system disk survives reinstalls."

msg_ok "Completed successfully!\n"

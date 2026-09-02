#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://blissos.org/

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="BlissOS"
APP_TYPE="vm"
NSAPP="blissos-vm"
var_os="android"
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

if vm_confirm_new_vm "$APP" "This will create a new BlissOS VM -- Android x86 as a full operating system, with a kernel of its own.\n\nNote that the last official x86 release is from October 2024 (Android 13).\n\nWithout a passed-through GPU everything renders in software, which is usable but slow. If you only want Android apps on a Linux host, waydroid-vm is the lighter answer.\n\nProceed?"; then
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
  DISK_SIZE="32G"
  DISK_CACHE=""
  HN="blissos"
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
  vm_prompt_disk_size "32G" "Set Disk Size in GiB"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "blissos"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a BlissOS VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a BlissOS VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 4 CPU Cores (Host model)\n• 4 GB RAM\n• 32 GB Disk\n• Q35 Machine Type" 14 58
post_to_api_vm

vm_select_storage "$HN"

msg_info "Retrieving the URL for the BlissOS installer"

# The official x86 builds live under blissos-x86. Both blissos and blissos-dev
# also exist and are years out of date, which is an easy way to end up shipping
# a script that points at a 2020 image. BlissOS17 has directories but no builds
# in them, so BlissOS16 really is the newest branch with files.
#
# FOSS rather than Gapps by default: the same build without the Google apps,
# which also avoids redistributing those. The Gapps tree sits beside it.
ISO_DIR="https://sourceforge.net/projects/blissos-x86/files/Official/BlissOS16/FOSS/Generic"

# The build date orders these, not the version -- 16.9.7 exists more than once
# with different dates.
FILENAME=$(curl -fsSL "${ISO_DIR}/" 2>/dev/null |
  grep -oP 'Bliss-v[0-9.]+-x86_64-OFFICIAL-foss-[0-9]{8}\.iso' |
  sort -t- -k6 | tail -1)

if [[ -z "$FILENAME" ]]; then
  msg_error "Could not determine the current BlissOS image"
  exit 1
fi

BLISS_VERSION=$(echo "$FILENAME" | grep -oP 'Bliss-v\K[0-9.]+')
BLISS_BUILD=$(echo "$FILENAME" | grep -oP 'foss-\K[0-9]{8}')
URL="${ISO_DIR}/${FILENAME}/download"
CACHE_DIR="/var/lib/vz/template/iso"
CACHE_FILE="${CACHE_DIR}/${FILENAME}"

mkdir -p "$CACHE_DIR"
msg_ok "BlissOS ${CL}${BL}${BLISS_VERSION}${CL} ${GN}(build ${BLISS_BUILD})"

# A bad SourceForge mirror serves an HTML notice with status 200, so the size
# decides whether this is an ISO, not curl's exit code. Learned from cachyos.
MIN_ISO_BYTES=$((1024 * 1024 * 1024))

msg_info "Downloading BlissOS (approximately 2 GB, this may take a while)"
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes "$MIN_ISO_BYTES" || exit 115

msg_info "Creating a BlissOS VM"

# Android x86 carries virtio drivers -- the project targets QEMU as well as
# bare metal -- so unlike ChromeOS Flex this does not need SATA and e1000.
# UEFI with Secure Boot off; it will not boot with the Microsoft keys enrolled.
# virtio, not std: with stdvga Android gets as far as switch_root and then hangs
# on a black screen. vmwgfx does not help either; virtio-gpu is the DRM driver
# Android 13 actually carries. nomodeset also works but only until installation,
# since the installer writes its own bootloader config.
qm create $VMID -agent 1${MACHINE} -tablet 1 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 0 -ostype l26 -scsihw virtio-scsi-single \
  -efidisk0 ${STORAGE}:1,efitype=4m,pre-enrolled-keys=0 -scsi0 ${STORAGE}:${DISK_SIZE%G},${DISK_CACHE}${THIN%,} \
  -cdrom local:iso/${FILENAME} -boot order='scsi0;ide2' -vga virtio >/dev/null

set_description

msg_ok "Created a BlissOS VM ${CL}${BL}(${HN})"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting BlissOS VM"
  $STD qm start $VMID
  msg_ok "Started BlissOS VM"
fi

post_update_to_api "done" "none"

echo -e "\n${INFO}${BOLD}${GN}BlissOS VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}Version: ${BGN}${BLISS_VERSION} (build ${BLISS_BUILD})${CL}"
echo -e "${TAB}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"

echo -e "\n${INFO}${BOLD}${YW}Next Steps:${CL}"
echo -e "${TAB}1. Open the VM Console in Proxmox"
echo -e "${TAB}2. Pick ${BL}Installation${CL} from the boot menu"
echo -e "${TAB}3. Create and format a partition on ${BL}sda${CL}, then install there"
echo -e "${TAB}4. Say yes to GRUB and to a writable /system"
echo -e "${TAB}5. Reboot -- the boot order prefers the disk, so the installed"
echo -e "${TAB}   system takes over. Detach the ISO afterwards to tidy up."

echo -e "\n${INFO}${BOLD}${YW}Worth knowing:${CL}"
echo -e "${TAB}• The last official x86 release is from October 2024 (Android 13)."
echo -e "${TAB}  BlissOS17 has directories on SourceForge but no builds in them."
echo -e "${TAB}• Without a passed-through GPU, rendering happens in software."
echo -e "${TAB}• This is the FOSS build. Google apps live in the Gapps tree at"
echo -e "${TAB}  ${BL}sourceforge.net/projects/blissos-x86/files/Official/BlissOS16/Gapps/${CL}"

msg_ok "Completed successfully!\n"

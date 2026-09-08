#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Agent-Fennec
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/vm/cloud-init.func") || true
load_functions

APP="AlmaLinux"
APP_TYPE="vm"
NSAPP="almalinux-vm"
var_os="almalinux"
var_version="10"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
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

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

if [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
  var_version="${VM_OS_VERSION:-$var_version}"
elif vm_dialog radiolist "ALMALINUX VERSION" "Choose the AlmaLinux release to install" --cancel-button Exit-Script 12 58 3 \
  "10" "AlmaLinux 10 (Purple Lion)" ON \
  "9" "AlmaLinux 9 (Seafoam Ocelot)" OFF \
  "8" "AlmaLinux 8 (Sapphire Caracal)" OFF; then
  var_version="$VM_DIALOG_RESULT"
else
  exit_script
fi

# AlmaLinux 10 raises the baseline to x86-64-v3; 8 and 9 still run on v2 hosts.
case "$var_version" in
10) ALMA_CPU=" -cpu x86-64-v3" ;;
9 | 8) ALMA_CPU="" ;;
*)
  msg_error "Unsupported AlmaLinux version '${var_version}'"
  exit 1
  ;;
esac
APP="AlmaLinux ${var_version} VM"

# The GenericCloud image has no other way in, so this is not a choice; set once
# here rather than in default_settings, where the advanced path missed it and
# vm_provision then skipped provisioning entirely.
USE_CLOUD_INIT="yes"

function default_settings() {
  vm_apply_machine_type "q35"
  VMID=$(get_valid_nextid)
  DISK_SIZE="10G"
  DISK_CACHE=""
  HN="almalinux"
  CPU_TYPE="$ALMA_CPU"
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="no"
  METHOD="default"
  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "10G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "almalinux"
  vm_prompt_cpu_model "kvm64"
  if [[ "$var_version" == "10" && -z "$CPU_TYPE" ]]; then
    CPU_TYPE="$ALMA_CPU"
    msg_warn "AlmaLinux 10 needs an x86-64-v3 CPU - keeping ${CPU_TYPE# -cpu } instead of kvm64"
  fi
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a ${APP}?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a ${APP} using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}


vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

vm_select_storage "$HN"

# ==============================================================================
# PREREQUISITES
# ==============================================================================
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  $STD apt-get update
  $STD apt-get install -y libguestfs-tools
  msg_ok "Installed libguestfs-tools"
fi

msg_info "Retrieving the URL for the ${APP} Qcow2 Disk Image"
URL="https://repo.almalinux.org/almalinux/${var_version}/cloud/x86_64/images/AlmaLinux-${var_version}-GenericCloud-latest.x86_64.qcow2"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
CACHE_FILE="$(vm_image_cache_path "$URL")"
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes $((100 * 1024 * 1024)) || exit 115
FILE="$(basename "$CACHE_FILE")"

# ==============================================================================
# IMAGE CUSTOMIZATION
# ==============================================================================
msg_info "Customizing ${FILE} image"

WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$CACHE_FILE" "$WORK_FILE"
popd >/dev/null
rm -rf "$TEMP_DIR"
vm_prepare_cloud_image "$WORK_FILE" "$HN" || true
virt-customize -q -a "$WORK_FILE" --run-command "systemctl disable systemd-firstboot.service 2>/dev/null; rm -f /etc/systemd/system/sysinit.target.wants/systemd-firstboot.service; ln -sf /dev/null /etc/systemd/system/systemd-firstboot.service" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "systemctl enable serial-getty@ttyS0.service" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --selinux-relabel >/dev/null 2>&1 || true
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
for i in {0,1,2}; do
  disk="DISK$i"
  eval DISK"${i}"=vm-"${VMID}"-disk-"${i}"${DISK_EXT:-}
  eval DISK"${i}"_REF="${STORAGE}":"${DISK_REF:-}""${!disk}"
done

if [[ "$STORAGE_TYPE" != "nfs" && "$STORAGE_TYPE" != "dir" ]]; then
  msg_info "Converting image to raw format"
  RAW_FILE=$(mktemp --suffix=.raw)
  qemu-img convert -f qcow2 -O raw "$WORK_FILE" "$RAW_FILE"
  rm -f "$WORK_FILE"
  WORK_FILE="$RAW_FILE"
  msg_ok "Converted image to raw format"
fi

msg_info "Creating an ${APP}"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script -net0 virtio,bridge="$BRG",macaddr="$MAC""$VLAN""$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc "$STORAGE" "$VMID" "$DISK0" 4M 1>&/dev/null
pvesm alloc "$STORAGE" "$VMID" "$DISK2" 4M 1>&/dev/null
qm importdisk "$VMID" "${WORK_FILE}" "$STORAGE" ${DISK_IMPORT:-} 1>&/dev/null
qm set "$VMID" \
  -efidisk0 "${DISK0_REF}"${FORMAT} \
  -scsi0 "${DISK1_REF}",${DISK_CACHE}${THIN}size="${DISK_SIZE}" \
  -tpmstate0 "${DISK2_REF}",version=v2.0 \
  -boot order=scsi0 \
  -serial0 socket >/dev/null

rm -f "$WORK_FILE"
set_description
msg_ok "Created an ${APP} ${CL}${BL}(${HN})"

vm_resize_disk

vm_provision "$VMID" || true

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting ${APP}"
  $STD qm start "$VMID"
  msg_ok "Started ${APP}"
fi

post_update_to_api "done" "none"

msg_ok "Completed successfully!"
if [ -n "${CLOUDINIT_CRED_FILE:-}" ]; then
  echo -e "${INFO}${YW} Cloud-Init credentials saved to: ${BGN}${CLOUDINIT_CRED_FILE}${CL}"
fi


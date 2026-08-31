#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://fedoraproject.org/cloud/

source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="Fedora"
APP_TYPE="vm"
NSAPP="fedora-vm"
var_os="fedora"
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

if vm_confirm_new_vm "$APP" "This will create a new Fedora VM from the official Cloud Base image.\n\nFedora ships a current kernel and toolchain roughly every six months, with a 13-month support window per release.\n\nProceed?"; then
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
  DISK_SIZE="20G"
  DISK_CACHE=""
  HN="fedora"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="2"
  RAM_SIZE="2048"
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
  vm_prompt_disk_size "20G" "Set Disk Size in GiB"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "fedora"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_cloud_init "fedora"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Fedora VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Fedora VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 2 CPU Cores\n• 2 GB RAM\n• 20 GB Disk\n• Cloud-Init enabled" 14 58
post_to_api_vm

vm_select_storage "$HN"

if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  $STD apt-get update
  $STD apt-get install -y libguestfs-tools
  msg_ok "Installed libguestfs-tools"
fi

msg_info "Retrieving the URL for the Fedora Cloud Base image"

# Fedora has no "latest" symlink and the build number is part of the filename,
# so both the release and the image have to be read off the mirror. Pinning
# either one means the script breaks at the next respin.
MIRROR="https://dl.fedoraproject.org/pub/fedora/linux/releases"
FEDORA_RELEASE=$(curl -fsSL "$MIRROR/" 2>/dev/null | grep -oP 'href="\K[0-9]+(?=/")' | sort -rn | head -1)
[[ -z "$FEDORA_RELEASE" ]] && FEDORA_RELEASE="44"

IMAGE_DIR="${MIRROR}/${FEDORA_RELEASE}/Cloud/x86_64/images"
FILE=$(curl -fsSL "${IMAGE_DIR}/" 2>/dev/null | grep -oP 'href="\KFedora-Cloud-Base-Generic-[^"]+\.x86_64\.qcow2(?=")' | sort -V | tail -1)
if [[ -z "$FILE" ]]; then
  msg_error "Could not determine the current Fedora Cloud image"
  exit 1
fi

msg_ok "Fedora ${CL}${BL}${FEDORA_RELEASE}${CL} ${GN}(${FILE})"

curl -f#SL -o "$FILE" "${IMAGE_DIR}/${FILE}"
echo -en "\e[1A\e[0K"
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

msg_info "Customizing ${FILE}"
WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$FILE" "$WORK_FILE"
popd >/dev/null
rm -rf "$TEMP_DIR"

virt-customize -q -a "$WORK_FILE" --hostname "$HN" >/dev/null 2>&1
virt-customize -q -a "$WORK_FILE" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1
virt-customize -q -a "$WORK_FILE" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1
virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "systemctl enable serial-getty@ttyS0.service" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --selinux-relabel >/dev/null 2>&1 || true
msg_ok "Customized image"

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
vm_apply_storage_layout "$STORAGE_TYPE"
vm_define_disk_references 3

if [[ "$DISK_IMPORT_FORMAT" == "raw" ]]; then
  msg_info "Converting image to raw format"
  RAW_FILE=$(mktemp --suffix=.raw)
  qemu-img convert -f qcow2 -O raw "$WORK_FILE" "$RAW_FILE"
  rm -f "$WORK_FILE"
  WORK_FILE="$RAW_FILE"
  msg_ok "Converted image to raw format"
fi

msg_info "Creating a Fedora VM"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script -net0 virtio,bridge="$BRG",macaddr="$MAC""$VLAN""$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc "$STORAGE" "$VMID" "$DISK0" 4M 1>&/dev/null
pvesm alloc "$STORAGE" "$VMID" "$DISK2" 4M 1>&/dev/null
qm importdisk "$VMID" "$WORK_FILE" "$STORAGE" -format "$DISK_IMPORT_FORMAT" 1>&/dev/null
qm set "$VMID" \
  -efidisk0 "${DISK0_REF}${FORMAT:-}" \
  -scsi0 "${DISK1_REF}",${DISK_CACHE}${THIN}size="${DISK_SIZE}" \
  -tpmstate0 "${DISK2_REF}",version=v2.0 \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
set_description
rm -f "$WORK_FILE"
msg_ok "Created a Fedora VM ${CL}${BL}(${HN})"

msg_info "Resizing disk to ${DISK_SIZE}"
qm resize "$VMID" scsi0 "${DISK_SIZE}" >/dev/null
msg_ok "Resized disk to ${DISK_SIZE}"

load_cloud_init_functions
setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Fedora VM"
  qm start "$VMID"
  msg_ok "Started Fedora VM"
fi

post_update_to_api "done" "none"

echo -e "\n${INFO}${BOLD}${GN}Fedora VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}Release: ${BGN}Fedora ${FEDORA_RELEASE}${CL}"
if [ -n "${CLOUDINIT_CRED_FILE:-}" ]; then
  echo -e "${TAB}${DGN}Cloud-Init credentials: ${BGN}${CLOUDINIT_CRED_FILE}${CL}"
fi

msg_ok "Completed successfully!\n"

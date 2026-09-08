#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
APP="Umbrel OS"
APP_TYPE="vm"
NSAPP="umbrel-os-vm"
var_os="umbrel-os"
var_version="n.d."

HA=$(echo "\033[1;34m")

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
pushd $TEMP_DIR >/dev/null
if vm_confirm_new_vm "Umbrel OS VM" "This will create a New Umbrel OS VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

# Ensure pv is installed or abort with instructions
function ensure_pv() {
  if ! command -v pv &>/dev/null; then
    msg_info "Installing required package: pv"
    if ! apt-get update -qq &>/dev/null || ! apt-get install -y pv &>/dev/null; then
      msg_error "Failed to install pv automatically."
      echo -e "\nPlease run manually on the Proxmox host:\n  apt install pv\n"
      exit 237
    fi
    msg_ok "Installed pv"
  fi
}

# Extract .xz with pv
# Args: $1=cache_file $2=target_img
function extract_xz_with_pv() {
  set -o pipefail
  local file="$1"
  local target="$2"

  msg_info "Decompressing $(basename "$file") to $target"
  if ! xz -dc "$file" | pv -N "Extracting" >"$target"; then
    msg_error "Failed to extract $file"
    rm -f "$target"
    exit 115
  fi
  msg_ok "Decompressed to $target"
}

function default_settings() {
  vm_apply_machine_type "q35"
  VMID=$(get_valid_nextid)
  DISK_SIZE="32G"
  HN="umbrelos"
  CPU_TYPE=""
  CORE_COUNT="2"
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
  vm_prompt_disk_size "32G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "umbrelos"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Umbrel OS VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Umbrel OS VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}


vm_preflight
ensure_pv
vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

vm_select_storage "$HN"


URL="https://download.umbrel.com/release/latest/umbrelos-amd64.img.xz"
CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="$CACHE_DIR/$(basename "$URL")"
FILE_IMG="/var/lib/vz/template/tmp/${CACHE_FILE##*/%.xz}"

mkdir -p "$CACHE_DIR" "$(dirname "$FILE_IMG")"

vm_fetch_image "$URL" "$CACHE_FILE" --cache --verify-xz || exit 115

qm create $VMID${MACHINE} -bios ovmf -agent 1 -tablet 0 -localtime 1 ${CPU_TYPE} \
  -cores "$CORE_COUNT" -memory "$RAM_SIZE" -name "$HN" -tags community-script \
  -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null

extract_xz_with_pv "$CACHE_FILE" "$FILE_IMG"

if qm disk import --help >/dev/null 2>&1; then
  IMPORT_CMD=(qm disk import)
else
  IMPORT_CMD=(qm importdisk)
fi
IMPORT_OUT="$("${IMPORT_CMD[@]}" "$VMID" "$FILE_IMG" "$STORAGE" --format raw 2>&1 || true)"
DISK_REF="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*imported disk '\([^']\+\)'.*/\1/p" | tr -d "\r\"'")"
[[ -z "$DISK_REF" ]] && DISK_REF="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"

qm set $VMID \
  --efidisk0 ${STORAGE}:0,efitype=4m \
  --scsi0 ${DISK_REF},ssd=1,discard=on \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
qm set $VMID --agent enabled=1 >/dev/null
vm_resize_disk

set_description

if [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
  KEEP_IMAGE="${VM_KEEP_IMAGE:-yes}"
elif vm_dialog yesno "Image Cache" \
  "Keep downloaded Umbrel OS image for future VMs?\n\nFile: $CACHE_FILE" 10 70; then
  KEEP_IMAGE="yes"
else
  KEEP_IMAGE="no"
fi

if [[ "$KEEP_IMAGE" == "yes" ]]; then
  msg_ok "Keeping cached image"
else
  rm -f "$CACHE_FILE"
  msg_ok "Deleted cached image"
fi
rm -f "$FILE_IMG"

msg_ok "Created a Umbrel OS VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Umbrel OS VM"
  $STD qm start $VMID
  msg_ok "Started Umbrel OS VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

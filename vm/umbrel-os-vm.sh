#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

header_info
echo -e "\n Loading..."
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
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Umbrel OS VM" --yesno "This will create a New Umbrel OS VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x, 9.0 and 9.2

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

# Download an .xz file and validate it
# Args: $1=url $2=cache_file
function download_and_validate_xz() {
  local url="$1"
  local file="$2"

  # If file exists, check validity
  if [[ -s "$file" ]]; then
    if xz -t "$file" &>/dev/null; then
      msg_ok "Using cached image $(basename "$file")"
      return 0
    else
      msg_error "Cached file $(basename "$file") is corrupted. Deleting and retrying download..."
      rm -f "$file"
    fi
  fi

  # Download fresh file
  msg_info "Downloading image: $(basename "$file")"
  if ! curl -fSL -o "$file" "$url"; then
    msg_error "Download failed: $url"
    rm -f "$file"
    exit 115
  fi

  # Validate again
  if ! xz -t "$file" &>/dev/null; then
    msg_error "Downloaded file $(basename "$file") is corrupted. Please try again later."
    rm -f "$file"
    exit 115
  fi
  msg_ok "Downloaded and validated $(basename "$file")"
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


check_root
arch_check
pve_check
ssh_check
ensure_pv
vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

vm_select_storage "$HN"


URL="https://download.umbrel.com/release/latest/umbrelos-amd64.img.xz"
CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="$CACHE_DIR/$(basename "$URL")"
FILE_IMG="/var/lib/vz/template/tmp/${CACHE_FILE##*/%.xz}"

mkdir -p "$CACHE_DIR" "$(dirname "$FILE_IMG")"

download_and_validate_xz "$URL" "$CACHE_FILE"

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
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://community-scripts.org' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Umbrel OS VM</h2>

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
qm set $VMID -description "$DESCRIPTION" >/dev/null

if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Image Cache" \
  --yesno "Keep downloaded Umbrel OS image for future VMs?\n\nFile: $CACHE_FILE" 10 70; then
  msg_ok "Keeping cached image"
else
  rm -f "$CACHE_FILE"
  msg_ok "Deleted cached image"
fi
rm -f "$FILE_IMG"

msg_ok "Created a Umbrel OS VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Umbrel OS VM"
  qm start $VMID
  msg_ok "Started Umbrel OS VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

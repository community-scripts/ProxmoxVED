#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
VERSIONS=(stable beta dev)
METHOD=""
APP="Home Assistant OS"
APP_TYPE="vm"
NSAPP="haos-vm"
var_os="homeassistant"
DISK_SIZE="32G"

for version in "${VERSIONS[@]}"; do
  eval "$version=$(curl -fsSL https://raw.githubusercontent.com/home-assistant/version/master/stable.json | grep '"ova"' | cut -d '"' -f 4)"
done
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
if vm_confirm_new_vm "$APP" "This will create a new Homeassistant OS VM.\n\nProceed?"; then
  :
else
  header_info && exit_script
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
  BRANCH="$stable"
  var_version="${BRANCH}"
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="32G"
  DISK_CACHE=""
  HN="haos${BRANCH}"
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
  if vm_dialog radiolist "Homeassistant OS Version" --cancel-button Exit-Script "Choose Version" 10 58 3 \n    "$stable" "Stable  " ON \n    "$beta" "Beta  " OFF \n    "$dev" "Dev  " OFF; then
    BRANCH="$VM_DIALOG_RESULT"
    var_version="${BRANCH}"
    echo -e "${DGN}Using HAOS Version: ${BGN}$BRANCH${CL}"
  else
    exit_script
  fi

  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "$DISK_SIZE" "Set Disk Size in GiB (e.g., 10, 20)"
  vm_prompt_disk_cache "writethrough"
  vm_prompt_hostname "haos${BRANCH}"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create Homeassistant OS ${BRANCH} VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Homeassistant OS VM using the above advanced settings${CL}"
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

var_version="${BRANCH}"
msg_info "Retrieving the URL for Home Assistant ${BRANCH} Disk Image"
if [ "$BRANCH" == "$dev" ]; then
  URL="https://os-artifacts.home-assistant.io/${BRANCH}/haos_ova-${BRANCH}.qcow2.xz"
else
  URL="https://github.com/home-assistant/operating-system/releases/download/${BRANCH}/haos_ova-${BRANCH}.qcow2.xz"
fi

CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="$CACHE_DIR/$(basename "$URL")"
FILE_IMG="/var/lib/vz/template/tmp/${CACHE_FILE##*/%.xz}" # .qcow2

mkdir -p "$CACHE_DIR" "$(dirname "$FILE_IMG")"
msg_ok "${CL}${BL}${URL}${CL}"

vm_fetch_image "$URL" "$CACHE_FILE" --cache --verify-xz || exit 115

msg_info "Creating Home Assistant OS VM shell"
qm create $VMID${MACHINE} -bios ovmf -agent 1 -tablet 0 -localtime 1 ${CPU_TYPE} \
  -cores "$CORE_COUNT" -memory "$RAM_SIZE" -name "$HN" -tags community-script \
  -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
msg_ok "Created VM shell"

extract_xz_with_pv "$CACHE_FILE" "$FILE_IMG"

msg_info "Importing disk into storage ($STORAGE)"
if qm disk import --help >/dev/null 2>&1; then
  IMPORT_CMD=(qm disk import)
else
  IMPORT_CMD=(qm importdisk)
fi
IMPORT_OUT="$("${IMPORT_CMD[@]}" "$VMID" "$FILE_IMG" "$STORAGE" --format raw 2>&1 || true)"
DISK_REF="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p" | tr -d "\r\"'")"
[[ -z "$DISK_REF" ]] && DISK_REF="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"
[[ -z "$DISK_REF" ]] && {
  msg_error "Unable to determine imported disk reference."
  echo "$IMPORT_OUT"
  exit 226
}
msg_ok "Imported disk (${CL}${BL}${DISK_REF}${CL})"

rm -f "$FILE_IMG"

msg_info "Attaching EFI and root disk"
qm set $VMID \
  --efidisk0 ${STORAGE}:0,efitype=4m \
  --scsi0 ${DISK_REF},ssd=1,discard=on \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
qm set $VMID --agent enabled=1 >/dev/null
msg_ok "Attached EFI and root disk"

msg_info "Resizing disk to $DISK_SIZE"
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
msg_ok "Resized disk"

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://community-scripts.org' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Homeassistant OS VM</h2>

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
msg_ok "Created Homeassistant OS VM ${CL}${BL}(${HN})"

if vm_dialog yesno "Image Cache" \
  "Keep downloaded Home Assistant OS image for future VMs?\n\nFile: $CACHE_FILE" 10 70; then
  msg_ok "Keeping cached image"
else
  rm -f "$CACHE_FILE"
  msg_ok "Deleted cached image"
fi

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Home Assistant OS VM"
  $STD qm start $VMID
  msg_ok "Started Home Assistant OS VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

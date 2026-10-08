#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://waydro.id/

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="Waydroid"
APP_TYPE="vm"
NSAPP="waydroid-vm"
var_os="ubuntu"
var_version="24.04"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"
OS_CHOICE="ubuntu2404"
OS_LABEL="Ubuntu 24.04 LTS (Noble Numbat)"
OS_CODENAME="noble"
WAYDROID_PREINSTALLED="no"
WAYDROID_FIRSTBOOT_MARKER=""

header_info
echo -e "\n Loading..."

set -Eeo pipefail
shopt -s inherit_errexit
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

vm_require_arch amd64

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

vm_preflight
vm_require_tools virt-customize jq

function select_os() {
  if [[ -n "${1:-}" ]]; then
    OS_CHOICE="$1"
  elif [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
    OS_CHOICE="${VM_OS_VERSION:-ubuntu2404}"
  elif vm_dialog radiolist "OS SELECTION" \
    "Choose the base operating system:" --cancel-button Exit-Script 12 68 2 \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble Numbat)" ON \
    "debian13" "Debian 13 (Trixie)" OFF; then
    OS_CHOICE="$VM_DIALOG_RESULT"
  else
    exit_script
  fi

  case "$OS_CHOICE" in
  ubuntu2404)
    OS_LABEL="Ubuntu 24.04 LTS (Noble Numbat)"
    OS_CODENAME="noble"
    var_os="ubuntu"
    var_version="24.04"
    ;;
  debian13)
    OS_LABEL="Debian 13 (Trixie)"
    OS_CODENAME="trixie"
    var_os="debian"
    var_version="13"
    ;;
  *)
    msg_error "Unsupported OS '${OS_CHOICE}' (expected ubuntu2404 or debian13)"
    exit 1
    ;;
  esac
  echo -e "${OS}${BOLD}${DGN}Base OS: ${BGN}${OS_LABEL}${CL}"
}

function default_settings() {
  select_os "${VM_OS_VERSION:-}"
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="20G"
  DISK_CACHE=""
  HN="waydroid"
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
  select_os
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "20G" "Set Disk Size in GiB (min. 20 recommended)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "waydroid"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_keyboard
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a ${OS_LABEL} Waydroid VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a ${OS_LABEL} Waydroid VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 4 CPU Cores\n• 4 GB RAM\n• 20 GB Disk" 13 58
CLOUDINIT_REQUIRED=1
if [[ "$OS_CHOICE" == "debian13" ]]; then
  vm_prompt_cloud_init "debian"
else
  vm_prompt_cloud_init "ubuntu"
fi
if [[ "$USE_CLOUD_INIT" != "yes" ]]; then
  msg_error "Waydroid cloud images require Cloud-Init credentials."
  exit 1
fi
post_to_api_vm

vm_select_storage "$HN"
vm_define_disk_references 2

case "$OS_CHOICE" in
ubuntu2404) URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" ;;
debian13) URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64.qcow2" ;;
esac

msg_info "Retrieving the URL for the ${OS_LABEL} Cloud Image"
msg_ok "${CL}${BL}${URL}${CL}"

CACHE_FILE="$(vm_image_cache_path "$URL")"
MIN_IMAGE_BYTES=$((100 * 1024 * 1024))
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes "$MIN_IMAGE_BYTES" || exit 115

WORK_FILE="$TEMP_DIR/waydroid.qcow2"
cp "$CACHE_FILE" "$WORK_FILE"

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1
BASE_PREINSTALLED="no"
BASE_PKGS="curl,ca-certificates,qemu-guest-agent,weston"
[[ "$OS_CHOICE" == "ubuntu2404" ]] && BASE_PKGS="${BASE_PKGS},linux-modules-extra-generic"

msg_info "Installing prerequisites in image"
if vm_customize "Waydroid prerequisites" "$WORK_FILE" --install "$BASE_PKGS"; then
  BASE_PREINSTALLED="yes"
  msg_ok "Installed prerequisites"
else
  msg_warn "Package pre-install failed; Waydroid installation is pending on first boot."
fi

msg_info "Installing Waydroid in image"
if [[ "$BASE_PREINSTALLED" == "yes" ]] &&
  vm_customize "Waydroid" "$WORK_FILE" \
    --run-command "bash -o pipefail -c 'curl -fsSL https://repo.waydro.id | bash -s ${OS_CODENAME}'" \
    --run-command "apt-get install -y waydroid" \
    --run-command "systemctl enable waydroid-container"; then
  WAYDROID_PREINSTALLED="yes"
  msg_ok "Installed Waydroid"
else
  msg_warn "Waydroid pre-install failed; installation is pending on first boot."
fi

vm_customize "Waydroid binder module" "$WORK_FILE" \
  --run-command "grep -qxF binder_linux /etc/modules || echo 'binder_linux' >> /etc/modules" \
  --run-command "echo 'options binder_linux devices=binder,hwbinder,vndbinder' > /etc/modprobe.d/waydroid.conf" || exit 1

# `weston` on the VM console opens Android full-screen and returns to the
# console when it is closed; without an initialized Waydroid it opens a terminal.
WESTON_INI_TMP="$TEMP_DIR/weston.ini"
cat >"$WESTON_INI_TMP" <<'INI'
[core]
idle-time=0

[autolaunch]
path=/usr/local/bin/waydroid-ui
watch=true
INI
WAYDROID_UI_TMP="$TEMP_DIR/waydroid-ui"
cat >"$WAYDROID_UI_TMP" <<'UI'
#!/bin/sh
if waydroid status >/dev/null 2>&1; then
  exec waydroid show-full-ui
fi
exec weston-terminal
UI
vm_customize "Waydroid UI launcher" "$WORK_FILE" \
  --mkdir /etc/xdg/weston \
  --upload "${WESTON_INI_TMP}:/etc/xdg/weston/weston.ini" \
  --upload "${WAYDROID_UI_TMP}:/usr/local/bin/waydroid-ui" \
  --chmod "0755:/usr/local/bin/waydroid-ui" || exit 1

vm_prepare_cloud_image "$WORK_FILE" "$HN" || true

if [[ "$WAYDROID_PREINSTALLED" == "no" ]]; then
  WAYDROID_FIRSTBOOT_TMP="$TEMP_DIR/waydroid-firstboot.sh"
  cat >"$WAYDROID_FIRSTBOOT_TMP" <<FIRSTBOOT
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
exec >> /var/log/waydroid-install.log 2>&1

echo "[\$(date)] Starting Waydroid installation"
for _ in {1..30}; do
  ping -c1 8.8.8.8 >/dev/null 2>&1 && break
  sleep 2
done

apt-get update
apt-get install -y curl ca-certificates qemu-guest-agent weston
if grep -qi ubuntu /etc/os-release; then
  apt-get install -y "linux-modules-extra-\$(uname -r)" || apt-get install -y linux-modules-extra-generic
fi
bash -o pipefail -c "curl -fsSL https://repo.waydro.id | bash -s ${OS_CODENAME}"
apt-get install -y waydroid
grep -qxF binder_linux /etc/modules || echo 'binder_linux' >> /etc/modules
echo 'options binder_linux devices=binder,hwbinder,vndbinder' > /etc/modprobe.d/waydroid.conf
systemctl enable --now waydroid-container
echo "[\$(date)] Waydroid installation complete"
FIRSTBOOT

  vm_firstboot_unit "$WORK_FILE" waydroid-firstboot "$WAYDROID_FIRSTBOOT_TMP" \
    --description "Waydroid first boot installation" \
    --cloud-init yes || exit 1
  WAYDROID_FIRSTBOOT_MARKER="$VM_FIRSTBOOT_MARKER"
fi

vm_claim_vmid
msg_info "Creating a ${OS_LABEL} Waydroid VM"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script,waydroid -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
vm_mark_created

vm_alloc_efi_disk "$DISK0"
vm_import_disk "$VMID" "$WORK_FILE" "$STORAGE"

DISK_OPTIONS="${DISK_CACHE}${THIN}"
DISK_OPTIONS="${DISK_OPTIONS%,}"
ROOT_DISK="$VM_IMPORTED_DISK"
[[ -n "$DISK_OPTIONS" ]] && ROOT_DISK="${ROOT_DISK},${DISK_OPTIONS}"

qm set "$VMID" \
  --efidisk0 "${DISK0_REF}${FORMAT}" \
  --scsi0 "$ROOT_DISK" \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
vm_resize_disk "scsi0" "$DISK_SIZE"
set_description

vm_provision "$VMID"
if [[ -n "${CLOUDINIT_SSH_KEYS:-}" ]]; then
  $STD qm set "$VMID" --sshkeys "$CLOUDINIT_SSH_KEYS"
fi

msg_ok "Created a ${OS_LABEL} Waydroid VM ${CL}${BL}(${HN})"
vm_start_vm "Waydroid VM"
vm_wait_for_ip 120 || true

display_cloud_init_info "$VMID" "$HN"

if [[ "$WAYDROID_PREINSTALLED" == "yes" ]]; then
  INSTALL_STATUS="Pre-installed"
  FIRSTBOOT_STEP="Waydroid is pre-installed."
else
  INSTALL_STATUS="First-boot unit waydroid-firstboot.service${WAYDROID_FIRSTBOOT_MARKER:+ (${WAYDROID_FIRSTBOOT_MARKER})}"
  FIRSTBOOT_STEP="Waydroid installation continues in the VM; follow it with tail -f /var/log/waydroid-install.log (unit status: systemctl status waydroid-firstboot)"
fi

vm_print_summary \
  "OS=${OS_LABEL}" \
  "Waydroid=${INSTALL_STATUS}" \
  "Documentation=https://docs.waydro.id/"
vm_next_steps \
  "$FIRSTBOOT_STEP" \
  "Download Android once: sudo waydroid init && sudo systemctl restart waydroid-container" \
  "On the VM console (noVNC, not the serial console) log in and run: weston -- Android opens full-screen; closing it returns to the console." \
  "Plain 'waydroid' opens a GTK settings window and needs that Weston session; use 'waydroid show-full-ui' inside it."

FINISH_MESSAGE="VM created. Waydroid installation continues in the VM on first boot."
if [[ "$WAYDROID_PREINSTALLED" == "yes" ]]; then
  FINISH_MESSAGE="VM created. Waydroid is pre-installed; initialize it after first boot."
fi
vm_finish "$FINISH_MESSAGE"

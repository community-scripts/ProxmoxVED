#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}/misc/vm-core.func")
load_functions

APP="Nextcloud VM"
APP_TYPE="vm"
NSAPP="nextcloud-vm"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
var_os="debian"
var_version="12"

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

if vm_confirm_new_vm "$APP" "This will create a New $APP. Proceed?"; then
  :
else
  header_info && exit_script
fi

check_root
arch_check
pve_check
ssh_check

if [[ "$(pveversion | awk -F'/' '{print $2}' | awk -F'.' '{print $1}')" -lt 9 ]]; then
  msg_error "Nextcloud VM requires Proxmox VE 9.0 or later (Q35 + UEFI / QEMU 10.x)."
  exit 105
fi

function default_settings() {
  VMID=$(get_valid_nextid)
  DISK_SIZE="100G"
  HN="nextcloud"
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Nextcloud VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  DISK_SIZE="100G"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_hostname "nextcloud"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Nextcloud VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Nextcloud VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if vm_choose_settings_mode; then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

start_script
post_to_api_vm

vm_select_storage "$HN"

msg_info "Retrieving the URL for the Nextcloud Pre-installed Disk Image"
URL="https://download.kafit.se/public.php/dav/files/8w43PHG3cKoz5ZK/vzdump-qemu-999-2026_07_07-11_56_12.tar.zst"
FILE="vzdump-qemu-999-2026_07_07-11_56_12.tar.zst"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$FILE" "$URL"
echo -en "\e[1A\e[0K"
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

msg_info "Extracting Nextcloud VM Image (Patience)"
tar --use-compress-program=unzstd -xf "$FILE"
msg_ok "Extracted Nextcloud VM Image"

msg_info "Preparing VM Configuration"
ORIG_STORAGE=$(grep -m1 '^scsi0:' qemu-server.conf | sed 's/^scsi0: \([^:]*\):.*/\1/')
PATCHED_CONF=$(mktemp /tmp/nextcloud-vm-XXXX.conf)
sed "s|${ORIG_STORAGE}:vm-999-|${STORAGE}:vm-${VMID}-|g" qemu-server.conf >"$PATCHED_CONF"
msg_ok "Prepared VM Configuration"

msg_info "Creating Nextcloud VM"
qm create "${VMID}" --name "nextcloud" >/dev/null
msg_ok "Created Nextcloud VM"

msg_info "Importing Disks (Patience)"
qm importdisk "${VMID}" vm-999-disk-0.qcow2 "${STORAGE}" 1>&/dev/null
qm importdisk "${VMID}" vm-999-disk-1.qcow2 "${STORAGE}" 1>&/dev/null
qm importdisk "${VMID}" vm-999-disk-2.raw "${STORAGE}" 1>&/dev/null
msg_ok "Imported Disks"

msg_info "Applying VM Configuration"
cp "$PATCHED_CONF" /etc/pve/qemu-server/${VMID}.conf
rm -f "$PATCHED_CONF"
msg_ok "Applied VM Configuration"

msg_info "Configuring Nextcloud VM"
qm set "$VMID" \
  -name "$HN" \
  -cores "$CORE_COUNT" \
  -memory "$RAM_SIZE" \
  -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" \
  -onboot 1 \
  -tags community-script >/dev/null
msg_ok "Configured Nextcloud VM"

set_description

msg_ok "Created a Nextcloud VM ${CL}${BL}(${HN})"
if [ "$START_VM" = "yes" ]; then
  msg_info "Starting Nextcloud VM"
  qm start "$VMID"
  msg_ok "Started Nextcloud VM"
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"
echo -e "${INFO}${YW}Default login credentials:${CL}"
echo -e "${GATEWAY}${BGN}Username: ncadmin  |  Password: nextcloud${CL}"
echo -e "${INFO}${YW}After first boot, log in and run ${BGN}sudo bash${YW} to launch the interactive setup wizard.${CL}\n"

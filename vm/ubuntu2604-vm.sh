#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}/misc/vm-core.func")
load_functions

function header_info {
  clear
  cat <<"EOF"
   __  ____                __           ___   ______ ____  __ __     _    ____  ___
  / / / / /_  __  ______  / /___  __   |__ \ / ____// __ \/ // /    | |  / /  |/  /
 / / / / __ \/ / / / __ \/ __/ / / /   __/ //___ \ / / / / // /_    | | / / /|_/ / 
/ /_/ / /_/ / /_/ / / / / /_/ /_/ /   / __/____/ // /_/ /__  __/    | |/ / /  / /  
\____/_.___/\__,_/_/ /_/\__/\__,_/   /____/_____(_)____/  /_/       |___/_/  /_/ (Plucky Puffin)
                                                                                   
EOF
}

APP="Ubuntu 26.04 VM"
APP_TYPE="vm"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="ubuntu2604-vm"
var_os="ubuntu"
var_version="2604"
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"

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
vm_prompt_cloud_init "ubuntu"

function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="7G"
  DISK_CACHE=""
  HN="ubuntu"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$(vm_machine_type_label "$MACHINE_TYPE")${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 26.04 VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "${DISK_SIZE:-7G}" "Set Disk Size in GiB (e.g., 10, 20)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "ubuntu"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Ubuntu 26.04 VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 26.04 VM using the above advanced settings${CL}"
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
vm_define_disk_references 2
DISK_IMPORT="-format ${DISK_IMPORT_FORMAT}"

msg_info "Retrieving the URL for the Ubuntu 26.04 Disk Image"
URL="https://cloud-images.ubuntu.com/releases/server/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE="$(basename "$URL")"
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

msg_info "Creating a Ubuntu 26.04 VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID $FILE $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
set_description

msg_info "Resizing disk to $DISK_SIZE"
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f setup_cloud_init >/dev/null 2>&1; then
  setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "${CLOUDINIT_USER:-ubuntu}" "${CLOUDINIT_NETWORK_MODE:-dhcp}" "${CLOUDINIT_IP:-}" "${CLOUDINIT_GW:-}" "${CLOUDINIT_DNS:-${CLOUDINIT_DNS_SERVERS:-1.1.1.1 8.8.8.8}}"
fi

msg_ok "Created a Ubuntu 26.04 VM ${CL}${BL}(${HN})"
if [ "$START_VM" = "yes" ]; then
  msg_info "Starting Ubuntu 26.04 VM"
  qm start $VMID
  msg_ok "Started Ubuntu 26.04 VM"
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"
if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f display_cloud_init_info >/dev/null 2>&1; then
  display_cloud_init_info "$VMID" "$HN"
else
  echo -e "Cloud-Init is disabled. The VM disk was resized on the Proxmox side only.\nIf the guest does not auto-expand its root filesystem after first boot, expand it manually inside the VM.\n\nMore info at https://github.com/community-scripts/ProxmoxVED/discussions/272 \n"
fi

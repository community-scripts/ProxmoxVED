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
APP="Ubuntu 24.10 VM"
APP_TYPE="vm"
NSAPP="ubuntu-2410-vm"
var_os="ubuntu"
var_version="2410"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "$APP" --yesno "This will create a New $APP. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function init_settings() {
  VMID="$(get_valid_nextid)"
  HN="ubuntu"
  DISK_SIZE="8G"
  DISK_CACHE=""
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  MACHINE_TYPE="i440fx"
  MACHINE=""
  FORMAT=",efitype=4m"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
}

function default_settings() {
  vm_apply_machine_type "i440fx"
  METHOD="default"
  vm_echo_default_settings
}

function apply_env_overrides() {
  METHOD="env"
  [ -n "$var_vmid" ] && VMID="$var_vmid"
  HN=$(echo "${var_hostname,,}" | tr -cd '[:alnum:]-')
  [[ -z "$HN" ]] && HN="ubuntu"
  [[ ! "$HN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && {
    msg_error "Invalid hostname: $HN"
    exit 1
  }

  case "$var_machine" in
  q35)
    MACHINE_TYPE="q35"
    FORMAT=""
    MACHINE=" -machine q35"
    ;;
  *)
    MACHINE_TYPE="i440fx"
    FORMAT=",efitype=4m"
    MACHINE=""
    ;;
  esac

  case "$var_cpu_type" in
  1) CPU_TYPE=" -cpu host" ;;
  *) CPU_TYPE="" ;;
  esac

  case "$var_disk_cache" in
  1) DISK_CACHE="cache=writethrough," ;;
  *) DISK_CACHE="" ;;
  esac

  [[ "$var_cpu" =~ ^[1-9][0-9]*$ ]] && CORE_COUNT="$var_cpu" || CORE_COUNT="2"
  [[ "$var_ram" =~ ^[1-9][0-9]*$ ]] && RAM_SIZE="$var_ram" || RAM_SIZE="2048"
  [[ -n "$var_disk" ]] && DISK_SIZE="$var_disk" || DISK_SIZE="8G"
  [ -n "$var_bridge" ] && BRG="$var_bridge"
  [ -z "$BRG" ] && BRG="vmbr0"

  [ -n "$var_mac" ] && MAC="$var_mac"
  [ -z "$MAC" ] && MAC="$GEN_MAC"
  VLAN=${var_vlan:+",tag=$var_vlan"}
  MTU=${var_mtu:+",mtu=$var_mtu"}
  START_VM="$var_start_vm"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}${MACHINE_TYPE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}${DISK_CACHE:-None}${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}${CPU_TYPE:+Host}${CPU_TYPE:-KVM64}${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}${var_vlan:-Default}${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}${var_mtu:-Default}${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a $APP using environment settings${CL}"
}

function validate_env_settings() {
  [[ -n "$var_hostname" ]] && {
    HN_CLEANED=$(echo "$var_hostname" | tr -cd '[:alnum:]-')
    if [[ ! "$HN_CLEANED" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
      msg_error "Invalid hostname: $var_hostname"
      exit 1
    fi
  }

  [[ -n "$var_vmid" && ! "$var_vmid" =~ ^[1-9][0-9]{2,}$ ]] && {
    msg_error "Invalid VMID: must be a number >= 100"
    exit 1
  }

  [[ -n "$var_cpu" && ! "$var_cpu" =~ ^[1-9][0-9]*$ ]] && {
    msg_error "Invalid CPU core count: must be > 0"
    exit 1
  }

  [[ -n "$var_ram" && ! "$var_ram" =~ ^[1-9][0-9]*$ ]] && {
    msg_error "Invalid RAM size: must be > 0"
    exit 1
  }

  [[ -n "$var_disk" && ! "$var_disk" =~ ^[1-9][0-9]*G$ ]] && {
    msg_error "Invalid disk size: must be like 10G"
    exit 1
  }

  [[ -n "$var_mac" && ! "$var_mac" =~ ^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$ ]] && {
    msg_error "Invalid MAC address: $var_mac"
    exit 1
  }

  [[ -n "$var_mtu" && ! "$var_mtu" =~ ^[1-9][0-9]{2,4}$ ]] && {
    msg_error "Invalid MTU value: $var_mtu"
    exit 1
  }

  [[ -n "$var_vlan" && ! "$var_vlan" =~ ^[0-9]{1,4}$ ]] && {
    msg_error "Invalid VLAN tag: must be numeric"
    exit 1
  }

  [[ -n "$var_start_vm" && ! "$var_start_vm" =~ ^(yes|no)$ ]] && {
    msg_error "var_start_vm must be 'yes' or 'no'"
    exit 1
  }
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "i440fx"
  vm_prompt_disk_size "8G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "ubuntu2410"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu

  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Ubuntu 24.10 VM VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 24.10 VM VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function has_env_overrides() {
  env | grep -qE "^var_(bridge|cpu|cpu_type|disk|disk_cache|hostname|mac|machine|mtu|ram|start_vm|vlan|vmid)="
}


check_root
arch_check
pve_check
ssh_check
vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

vm_select_storage "$HN"
msg_info "Retrieving the URL for the Ubuntu 24.10 Disk Image"
URL=https://cloud-images.ubuntu.com/oracular/current/oracular-server-cloudimg-amd64.img
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# Console, guest agent, machine-id and root login -- the image was
# imported untouched before, so it had none of them.
vm_prepare_cloud_image "$FILE" "$HN" || true

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir | cifs)
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
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

msg_info "Creating a $APP"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags "community-script;ubuntu" -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
if [[ "$STORAGE_TYPE" != "lvmthin" ]]; then
  pvesm alloc $STORAGE $VMID $DISK0 4M >/dev/null
fi
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -ide2 ${STORAGE}:cloudinit \
  -boot order=scsi0 \
  -serial0 socket \
  -smbios1 type=1 \
  --ciuser "ubuntu" -cipassword "ubuntu" >/dev/null
DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>$APP</h2>

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
qm set "$VMID" -description "$DESCRIPTION" >/dev/null
if [ -n "$DISK_SIZE" ]; then
  msg_info "Resizing disk to $DISK_SIZE GB"
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
  msg_ok "Resized disk to ${CL}${BL}${DISK_SIZE}${CL} GB"
else
  msg_info "Using default disk size of $DEFAULT_DISK_SIZE GB"
  qm resize $VMID scsi0 ${DEFAULT_DISK_SIZE} >/dev/null
  msg_ok "Resized disk to ${CL}${BL}${DEFAULT_DISK_SIZE}${CL} GB"
fi

msg_ok "Created a $APP ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting $APP"
  qm start $VMID
  msg_ok "Started $APP"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"
echo -e "Setup Cloud-Init before starting \n
More info at https://github.com/community-scripts/ProxmoxVE/discussions/272 \n"

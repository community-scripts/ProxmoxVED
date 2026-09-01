#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Don Locke (DonLocke)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/AllStarLink

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
NEXTID=$(pvesh get /cluster/nextid)
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
APP="AllStarLink"
APP_TYPE="vm"
NSAPP="debian12vm"
var_os="debian"
var_version="12"
DISK_SIZE="8G"

HA=$(echo "\033[1;34m")
THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "AllStarLink VM" --yesno "This will create a New AllStarLink VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "⚠ User exited script \n" && exit
fi

function default_settings() {
  vm_apply_machine_type "i440fx"
  VMID="$NEXTID"
  DISK_CACHE=""
  HN="allstarlink"
  CPU_TYPE=""
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
  vm_prompt_machine_type "i440fx"
  vm_prompt_disk_size "8G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "allstarlink"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a AllStarLink VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a AllStarLink VM using the above advanced settings${CL}"
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
vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

vm_select_storage "$HN"
msg_info "Retrieving the URL for the Debian 12 Qcow2 Disk Image"
URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-$(dpkg --print-architecture).qcow2"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -fsSL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# qm resize only grows the block device. Without cloud-init nothing grows the
# guest partition, so expand it offline first.
if [ "${CLOUD_INIT:-no}" != "yes" ]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$FILE" "$DISK_SIZE" || true
fi

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
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
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

msg_info "Installing Pre-Requisite libguestfs-tools onto Host"
apt-get -qq update && apt-get -qq install libguestfs-tools lsb-release -y >/dev/null
msg_ok "Installed libguestfs-tools successfully"

msg_info "Adding ASL Package Repository"
virt-customize -q -a "${FILE}" \
  --run-command "curl -fsSL https://repo.allstarlink.org/public/asl-apt-repos.deb12_all.deb -o /tmp/asl-apt-repos.deb12_all.deb" \
  --run-command "dpkg -i /tmp/asl-apt-repos.deb12_all.deb" \
  --update \
  --run-command "rm -f /tmp/asl-apt-repos.deb12_all.deb" >/dev/null
msg_ok "Added ASL Package Repository"

msg_info "Installing AllStarLink (patience)"
virt-customize -q -a "${FILE}" \
  --install asl3 \
  --run-command "sed -i \"/secret /s/= .*/= $(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)/\" /etc/asterisk/manager.conf" >/dev/null
msg_ok "Installed AllStarLink"

if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Would you like to add Allmon3?" 10 58); then
  msg_info "Installing Allmon3"
  virt-customize -q -a "${FILE}" \
  # Cloud images run no getty on tty1, which is why the Proxmox console
  # stays black even though the VM is running.
  vm_enable_consoles "$FILE"
  # -agent 1 is set below, so the agent has to actually be there.
  vm_install_guest_agent "$FILE" || true
    --install allmon3 \
    --run-command "sed -i \"s/;pass=.*/;pass=\$(sed -ne 's/^secret = //p' /etc/asterisk/manager.conf)/\" /etc/allmon3/allmon3.ini" >/dev/null
  msg_ok "Installed Allmon3"
fi

msg_info "Creating a AllStarLink VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script,debian12,radio -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=2G \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
qm resize $VMID scsi0 8G >/dev/null
qm set $VMID --agent enabled=1 >/dev/null

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>AllStarLink VM</h2>

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

msg_ok "Created a AllStarLink VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting AllStarLink VM"
  qm start $VMID
  msg_ok "Started AllStarLink VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

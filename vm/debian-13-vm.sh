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
APP="Debian 13"
APP_TYPE="vm"
NSAPP="debian-13-vm"
var_os="debian"
var_version="13"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Debian 13 VM" --yesno "This will create a New Debian 13 VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x, 9.0 and 9.2

function select_cloud_init() {
  # The core prompt, not a local yes/no: it collects the user, password,
  # network mode and SSH keys into CLOUDINIT_*, which vm_provision needs later.
  # Answering "yes" to a bare dialog attached an empty drive and configured
  # nothing, so the VM came up with no login and no address.
  vm_prompt_cloud_init "root"
  CLOUD_INIT="${USE_CLOUD_INIT:-no}"
}

function default_settings() {
  vm_apply_machine_type "i440fx"
  VMID=$(get_valid_nextid)
  DISK_SIZE="8G"
  DISK_CACHE=""
  HN="debian"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  select_cloud_init
  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "i440fx"
  vm_prompt_disk_size "8G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "debian"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu

  # select_cloud_init is richer than a yes/no and default_settings uses it too.
  select_cloud_init

  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Debian 13 VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Debian 13 VM using the above advanced settings${CL}"
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

# ==============================================================================
# PREREQUISITES
# ==============================================================================
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  apt-get update >/dev/null 2>&1
  apt-get install -y libguestfs-tools >/dev/null 2>&1
  msg_ok "Installed libguestfs-tools"
fi

msg_info "Retrieving the URL for the Debian 13 Qcow2 Disk Image"
if [ "$CLOUD_INIT" == "yes" ]; then
  URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
else
  URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
fi
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# ==============================================================================
# IMAGE CUSTOMIZATION
# ==============================================================================
msg_info "Customizing ${FILE} image"

WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$FILE" "$WORK_FILE"

# Set hostname
virt-customize -q -a "$WORK_FILE" --hostname "${HN}" >/dev/null 2>&1

# Prepare for unique machine-id on first boot
virt-customize -q -a "$WORK_FILE" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1
virt-customize -q -a "$WORK_FILE" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1

# Disable systemd-firstboot to prevent interactive prompts blocking the console
virt-customize -q -a "$WORK_FILE" --run-command "systemctl disable systemd-firstboot.service 2>/dev/null; rm -f /etc/systemd/system/sysinit.target.wants/systemd-firstboot.service; ln -sf /dev/null /etc/systemd/system/systemd-firstboot.service" >/dev/null 2>&1 || true

# Pre-seed firstboot settings so it won't prompt even if triggered
virt-customize -q -a "$WORK_FILE" --run-command "echo 'Etc/UTC' > /etc/timezone && ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "touch /etc/locale.conf" >/dev/null 2>&1 || true

if [ "$CLOUD_INIT" == "yes" ]; then
  # Cloud-Init handles SSH and login
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
else
  # Configure auto-login on serial console (ttyS0) and virtual console (tty1)
  virt-customize -q -a "$WORK_FILE" --run-command "mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF' >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command "mkdir -p /etc/systemd/system/getty@tty1.service.d" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF' >/dev/null 2>&1 || true
fi

# Cloud images run no getty on tty1, which is why the Proxmox console
# stays black even though the VM is running.
vm_enable_consoles "$WORK_FILE"
# -agent 1 is set below, so the agent has to actually be there.
vm_install_guest_agent "$WORK_FILE" || true
msg_ok "Customized image"

# qm resize only grows the block device. Without cloud-init nothing grows the
# guest partition, so expand it offline first.
if [ "${CLOUD_INIT:-no}" != "yes" ]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$WORK_FILE" "$DISK_SIZE" || true
fi

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
for i in {0,1}; do
  disk="DISK$i"
  eval DISK"${i}"=vm-"${VMID}"-disk-"${i}"${DISK_EXT:-}
  eval DISK"${i}"_REF="${STORAGE}":"${DISK_REF:-}"${!disk}
done

msg_info "Creating a Debian 13 VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags "community-script;vm;${var_os}" -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${WORK_FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
if [ "$CLOUD_INIT" == "yes" ]; then
  qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -boot order=scsi0 \
    -serial0 socket >/dev/null
else
  qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -boot order=scsi0 \
    -serial0 socket >/dev/null
fi

# Attaches the Cloud-Init drive and sets ciuser, cipassword, sshkeys and
# ipconfig0, then reports the credentials it generated.
vm_provision "$VMID"

# Clean up work file
rm -f "$WORK_FILE"

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://community-scripts.org' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Debian VM</h2>

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
if [ -n "$DISK_SIZE" ]; then
  msg_info "Resizing disk to $DISK_SIZE GB"
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
else
  msg_info "Using default disk size of $DEFAULT_DISK_SIZE GB"
  qm resize $VMID scsi0 ${DEFAULT_DISK_SIZE} >/dev/null
fi

msg_ok "Created a Debian 13 VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Debian 13 VM"
  qm start $VMID >/dev/null 2>&1
  msg_ok "Started Debian 13 VM"
fi

msg_ok "Completed successfully!\n"
echo "More Info at https://github.com/community-scripts/ProxmoxVE/discussions/836"

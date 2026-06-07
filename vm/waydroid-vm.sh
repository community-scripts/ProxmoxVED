#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://waydro.id/

source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}/misc/vm-core.func")
load_functions

function header_info {
  clear
  cat <<"EOF"
 __          __             _         _     _
 \ \        / /            | |       (_)   | |
  \ \  /\  / /__ _ _  _  __| |_ __ ___  __| |
   \ \/  \/ / _` | | | |/ _` | '__/ _ \/ _` |
    \  /\  / (_| | |_| | (_| | | | (_) | (_| |
     \/  \/ \__,_|\__, |\__,_|_|  \___/ \__,_|
                   __/ |
                  |___/   Android Container on Linux
EOF
}

APP="Waydroid VM"
APP_TYPE="vm"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="waydroid-vm"
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"

# OS selection defaults
OS_CHOICE="ubuntu2404"
OS_LABEL="Ubuntu 24.04 LTS (Noble Numbat)"
OS_CODENAME="noble"

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

# ---------------------------------------------------------------------------
# OS Selection
# ---------------------------------------------------------------------------
function select_os() {
  local choice
  if choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "OS SELECTION" \
    --radiolist "Choose the base operating system:" --cancel-button Exit-Script 12 68 2 \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble Numbat)" ON \
    "debian13" "Debian 13 (Trixie)" OFF \
    3>&1 1>&2 2>&3); then
    OS_CHOICE="$choice"
    case "$OS_CHOICE" in
    ubuntu2404)
      OS_LABEL="Ubuntu 24.04 LTS (Noble Numbat)"
      OS_CODENAME="noble"
      ;;
    debian13)
      OS_LABEL="Debian 13 (Trixie)"
      OS_CODENAME="trixie"
      ;;
    esac
    echo -e "${OS}${BOLD}${DGN}Base OS: ${BGN}${OS_LABEL}${CL}"
  else
    exit_script
  fi
}

select_os
vm_prompt_cloud_init "ubuntu"

function default_settings() {
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

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$(vm_machine_type_label "$MACHINE_TYPE")${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a ${OS_LABEL} Waydroid VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "${DISK_SIZE:-20G}" "Set Disk Size in GiB (min. 20 recommended)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "waydroid"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a ${OS_LABEL} Waydroid VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a ${OS_LABEL} Waydroid VM using the above advanced settings${CL}"
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

# ---------------------------------------------------------------------------
# Prerequisites: libguestfs-tools for virt-customize
# ---------------------------------------------------------------------------
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  $STD apt update
  $STD apt install -y libguestfs-tools lsb-release
  msg_ok "Installed libguestfs-tools"
fi

# ---------------------------------------------------------------------------
# Download cloud image (cached)
# ---------------------------------------------------------------------------
case "$OS_CHOICE" in
ubuntu2404) URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" ;;
debian13) URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64.qcow2" ;;
esac

msg_info "Retrieving the URL for the ${OS_LABEL} Cloud Image"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"

CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="${CACHE_DIR}/$(basename "$URL")"
mkdir -p "$CACHE_DIR"

if [[ ! -s "$CACHE_FILE" ]]; then
  curl -f#SL -o "$CACHE_FILE" "$URL"
  echo -en "\e[1A\e[0K"
  msg_ok "Downloaded ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
else
  msg_ok "Using cached image ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
fi

# ---------------------------------------------------------------------------
# Customize disk image with Waydroid pre-installed (offline via virt-customize)
# ---------------------------------------------------------------------------
WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$CACHE_FILE" "$WORK_FILE"

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1
WAYDROID_PREINSTALLED="no"

# Ubuntu ships binder_linux only in linux-modules-extra-generic
BASE_PKGS="curl,ca-certificates,qemu-guest-agent,weston"
[[ "$OS_CHOICE" == "ubuntu2404" ]] && BASE_PKGS="${BASE_PKGS},linux-modules-extra-generic"

msg_info "Installing prerequisites in image"
if virt-customize -q -a "$WORK_FILE" \
  --install "$BASE_PKGS" >/dev/null 2>&1; then
  msg_ok "Installed prerequisites"
else
  msg_warn "Package pre-install failed — will retry on first boot"
fi

msg_info "Installing Waydroid in image (Patience)"
if virt-customize -q -a "$WORK_FILE" \
  --run-command "curl -fsSL https://repo.waydro.id | bash -s ${OS_CODENAME}" >/dev/null 2>&1 &&
  virt-customize -q -a "$WORK_FILE" \
    --run-command "apt-get install -y waydroid" >/dev/null 2>&1 &&
  virt-customize -q -a "$WORK_FILE" \
    --run-command "systemctl enable waydroid-container" >/dev/null 2>&1; then
  WAYDROID_PREINSTALLED="yes"
  msg_ok "Installed Waydroid"
else
  msg_warn "Waydroid pre-install failed — will install on first boot via systemd service"
fi

msg_info "Configuring binder kernel module"
virt-customize -q -a "$WORK_FILE" \
  --run-command "echo 'binder_linux' >> /etc/modules" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" \
  --run-command "echo 'options binder_linux devices=binder,hwbinder,vndbinder' > /etc/modprobe.d/waydroid.conf" >/dev/null 2>&1 || true
msg_ok "Configured binder kernel module"

msg_info "Finalizing image"
virt-customize -q -a "$WORK_FILE" --hostname "${HN}" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1 || true
if [ "$USE_CLOUD_INIT" = "yes" ]; then
  virt-customize -q -a "$WORK_FILE" \
    --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" \
    --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
fi
msg_ok "Finalized image"

# Fallback: write a first-boot systemd service in case virt-customize failed
if [ "$WAYDROID_PREINSTALLED" = "no" ]; then
  msg_info "Writing first-boot Waydroid install service (fallback)"
  virt-customize -q -a "$WORK_FILE" --run-command "cat > /usr/local/bin/waydroid-firstboot.sh << 'FSCRIPT'
#!/bin/bash
exec >> /var/log/waydroid-install.log 2>&1
echo \"[\$(date)] Starting Waydroid installation\"
for i in \$(seq 1 30); do ping -c1 8.8.8.8 >/dev/null 2>&1 && break; sleep 2; done
apt-get update
apt-get install -y curl ca-certificates qemu-guest-agent weston
# Install binder_linux kernel module for Ubuntu
if grep -qi ubuntu /etc/os-release; then
  apt-get install -y linux-modules-extra-\$(uname -r) || apt-get install -y linux-modules-extra-generic
fi
curl -fsSL https://repo.waydro.id | bash -s ${OS_CODENAME}
apt-get install -y waydroid
echo 'binder_linux' >> /etc/modules
echo 'options binder_linux devices=binder,hwbinder,vndbinder' > /etc/modprobe.d/waydroid.conf
systemctl enable --now waydroid-container
systemctl disable waydroid-firstboot.service
echo \"[\$(date)] Waydroid installation complete\"
FSCRIPT
chmod +x /usr/local/bin/waydroid-firstboot.sh" >/dev/null 2>&1 || true

  virt-customize -q -a "$WORK_FILE" --run-command "cat > /etc/systemd/system/waydroid-firstboot.service << 'FSVC'
[Unit]
Description=Waydroid First Boot Installation
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/log/waydroid-install.log

[Service]
Type=oneshot
ExecStart=/usr/local/bin/waydroid-firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FSVC
systemctl enable waydroid-firstboot.service" >/dev/null 2>&1 || true
  msg_ok "Wrote first-boot fallback service"
fi

FILE="$WORK_FILE"

msg_info "Creating a ${OS_LABEL} Waydroid VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script,waydroid -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
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

rm -f "$WORK_FILE"

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f setup_cloud_init >/dev/null 2>&1; then
  case "$OS_CHOICE" in
  ubuntu2404) setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "${CLOUDINIT_USER:-ubuntu}" "${CLOUDINIT_NETWORK_MODE:-dhcp}" "${CLOUDINIT_IP:-}" "${CLOUDINIT_GW:-}" "${CLOUDINIT_DNS:-${CLOUDINIT_DNS_SERVERS:-1.1.1.1 8.8.8.8}}" ;;
  debian13) setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "${CLOUDINIT_USER:-debian}" "${CLOUDINIT_NETWORK_MODE:-dhcp}" "${CLOUDINIT_IP:-}" "${CLOUDINIT_GW:-}" "${CLOUDINIT_DNS:-${CLOUDINIT_DNS_SERVERS:-1.1.1.1 8.8.8.8}}" ;;
  esac
else
  # Attach cloud-init drive for basic DHCP networking even without interactive CI config
  qm set $VMID --ide2 "${STORAGE}:cloudinit" >/dev/null 2>&1 ||
    qm set $VMID --scsi1 "${STORAGE}:cloudinit" >/dev/null 2>&1 || true
  qm set $VMID --ipconfig0 "ip=dhcp" >/dev/null 2>&1 || true
fi

msg_ok "Created a ${OS_LABEL} Waydroid VM ${CL}${BL}(${HN})"
if [ "$START_VM" = "yes" ]; then
  msg_info "Starting Waydroid VM"
  qm start $VMID
  msg_ok "Started Waydroid VM"
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

if [ "$WAYDROID_PREINSTALLED" = "yes" ]; then
  cat <<INSTRUCTIONS

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    WAYDROID IS PRE-INSTALLED                            │
  ├─────────────────────────────────────────────────────────────────────────┤
  │  Waydroid + Weston are already installed in the VM image.               │
  │  After first boot, connect to the VM and run:                           │
  │                                                                         │
  │    1. Initialize (once):                                                │
  │         sudo waydroid init                                              │
  │         sudo systemctl start waydroid-container                         │
  │                                                                         │
  │    2. Start Wayland compositor + Android UI (each session):             │
  │         weston --backend=headless &                                     │
  │         WAYLAND_DISPLAY=wayland-0 waydroid show-full-ui                 │
  │                                                                         │
  │  NOTE: GPU acceleration requires VirtIO GPU or passthrough setup.       │
  │  More info: https://docs.waydro.id/                                     │
  └─────────────────────────────────────────────────────────────────────────┘

INSTRUCTIONS
else
  cat <<INSTRUCTIONS

  ┌─────────────────────────────────────────────────────────────────────────┐
  │               WAYDROID FIRST-BOOT INSTALL ACTIVE                        │
  ├─────────────────────────────────────────────────────────────────────────┤
  │  Waydroid + Weston will be installed automatically on first boot.       │
  │  Monitor progress inside the VM with:                                   │
  │       sudo journalctl -u waydroid-firstboot -f                         │
  │       sudo tail -f /var/log/waydroid-install.log                       │
  │                                                                         │
  │  After the service completes:                                           │
  │    1. Initialize (once):                                                │
  │         sudo waydroid init                                              │
  │         sudo systemctl start waydroid-container                         │
  │                                                                         │
  │    2. Start Wayland compositor + Android UI (each session):             │
  │         weston --backend=headless &                                     │
  │         WAYLAND_DISPLAY=wayland-0 waydroid show-full-ui                 │
  │                                                                         │
  │  NOTE: GPU acceleration requires VirtIO GPU or passthrough setup.       │
  │  More info: https://docs.waydro.id/                                     │
  └─────────────────────────────────────────────────────────────────────────┘

INSTRUCTIONS
fi

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f display_cloud_init_info >/dev/null 2>&1; then
  display_cloud_init_info "$VMID" "$HN"
fi

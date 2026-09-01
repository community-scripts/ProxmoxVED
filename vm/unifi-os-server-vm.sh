#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions
# Load Cloud-Init library for VM configuration
source /dev/stdin <<<$(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/vm/cloud-init.func") 2>/dev/null || true

header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
APP="Unifi OS Server VM"
APP_TYPE="vm"
NSAPP="UniFi OS Server"
var_os="-"
var_version="-"
USE_CLOUD_INIT="yes" # Always use Cloud-Init for UniFi OS (required for automated setup)
OS_TYPE=""
OS_VERSION=""
OS_CODENAME=""
OS_DISPLAY=""

HA=$(echo "\033[1;34m")

THIN="discard=on,ssd=1,"

set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Unifi OS VM" --yesno "This will create a New Unifi OS VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x and 9.0 – 9.2

function select_os() {
  if OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SELECT OS" --radiolist \
    "Choose Operating System for UniFi OS VM" 12 68 2 \
    "debian13" "Debian 13 (Trixie) - Latest" ON \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF \
    3>&1 1>&2 2>&3); then
    case $OS_CHOICE in
    debian13)
      OS_TYPE="debian"
      OS_VERSION="13"
      OS_CODENAME="trixie"
      OS_DISPLAY="Debian 13 (Trixie)"
      ;;
    ubuntu2404)
      OS_TYPE="ubuntu"
      OS_VERSION="24.04"
      OS_CODENAME="noble"
      OS_DISPLAY="Ubuntu 24.04 LTS"
      ;;
    esac
    #echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}${OS_DISPLAY}${CL}"
  else
    exit_script
  fi
}

function select_cloud_init() {
  # UniFi OS Server ALWAYS requires Cloud-Init for automated installation
  USE_CLOUD_INIT="yes"
  #echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}yes (required for UniFi OS)${CL}"
}

function set_root_password() {
  while true; do
    if PW1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Set root password for the VM" 8 58 --title "ROOT PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$PW1" ]; then
        msg_error "Password cannot be empty"
        continue
      fi
      if PW2=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Confirm root password" 8 58 --title "CONFIRM PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ "$PW1" = "$PW2" ]; then
          USER_PASSWORD="$PW1"
          echo -e "${INFO}${BOLD}${DGN}Root Password: ${BGN}(set)${CL}"
          break
        else
          msg_error "Passwords do not match"
        fi
      else
        exit_script
      fi
    else
      exit_script
    fi
  done
}

function set_ssh_keys() {
  SSH_KEYS_FILE=""
  SSH_KEY_COUNT=0

  while true; do
    if PASTED_KEY=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
      "Paste an SSH public key (${SSH_KEY_COUNT} added so far)" 8 74 \
      --title "SSH PUBLIC KEYS" --ok-button Add --cancel-button Done 3>&1 1>&2 2>&3); then
      if [ -n "$PASTED_KEY" ]; then
        if [[ "$PASTED_KEY" == ssh-* || "$PASTED_KEY" == ecdsa-* ]]; then
          [ -z "$SSH_KEYS_FILE" ] && SSH_KEYS_FILE=$(mktemp)
          echo "$PASTED_KEY" >>"$SSH_KEYS_FILE"
          SSH_KEY_COUNT=$((SSH_KEY_COUNT + 1))
        else
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID KEY" --msgbox "Key must start with ssh-rsa, ssh-ed25519, ecdsa-, etc." 8 58
        fi
      fi
    else
      break
    fi
  done

  if [ $SSH_KEY_COUNT -gt 0 ]; then
    echo -e "${INFO}${BOLD}${DGN}SSH Keys: ${BGN}${SSH_KEY_COUNT} key(s) added${CL}"
  else
    echo -e "${INFO}${BOLD}${DGN}SSH Keys: ${BGN}none (password auth only)${CL}"
  fi
}

function get_image_url() {
  local arch
  arch=$(dpkg --print-architecture)
  case $OS_TYPE in
  debian)
    # Always use Cloud-Init variant for UniFi OS
    echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-generic-${arch}.qcow2"
    ;;
  ubuntu)
    # Ubuntu only has cloudimg variant (always with Cloud-Init support)
    echo "https://cloud-images.ubuntu.com/${OS_CODENAME}/current/${OS_CODENAME}-server-cloudimg-${arch}.img"
    ;;
  esac
}

function default_settings() {
  vm_apply_machine_type "q35"
  # OS Selection - ALWAYS ask
  select_os

  # Cloud-Init Selection - ALWAYS ask
  select_cloud_init

  # Root password and SSH keys
  set_root_password
  set_ssh_keys

  # Set defaults for other settings
  VMID=$(get_valid_nextid)
  DISK_CACHE=""
  DISK_SIZE="32G"
  HN="unifi-server-os"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="2"
  RAM_SIZE="6144"
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
  select_cloud_init
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "32G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "unifi-server-os"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "6144"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  set_root_password
  set_ssh_keys
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Unifi OS Server VM VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Unifi OS Server VM VM using the above advanced settings${CL}"
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

msg_info "Checking system resources"
SYSTEM_RAM_GB=$(grep MemTotal /proc/meminfo | awk '{printf "%.0f", $2 / 1024 / 1024}')
SYSTEM_SWAP_GB=$(grep SwapTotal /proc/meminfo | awk '{printf "%.0f", $2 / 1024 / 1024}')
SYSTEM_FREE_DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ ${SYSTEM_RAM_GB} -lt 4 ]]; then
  msg_error "Warning: Less than 4GB RAM detected (${SYSTEM_RAM_GB}GB). Install may be slow."
  sleep 3
fi
if [[ ${SYSTEM_FREE_DISK_GB} -lt 10 ]]; then
  msg_error "Warning: Less than 10GB free disk detected. Install may fail."
  sleep 3
fi
msg_ok "System resources: ${SYSTEM_RAM_GB}GB RAM, ${SYSTEM_FREE_DISK_GB}GB free disk"

if command -v ufw &>/dev/null; then
  if ufw status verbose | grep -q "Status: active"; then
    msg_info "Setting up firewall rules for UniFi OS Server ports"
    ufw allow 11443/tcp 2>/dev/null
    ufw allow 8080/tcp 2>/dev/null
    ufw allow 3478/tcp 2>/dev/null
    ufw allow 3478/udp 2>/dev/null
    msg_ok "Firewall rules configured"
  fi
fi

vm_select_storage "$HN"

# Fetch latest UniFi OS Server version and download URL
msg_info "Fetching latest UniFi OS Server version"

# Install jq if not available
if ! command -v jq &>/dev/null; then
  msg_info "Installing jq for JSON parsing"
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y jq -qq >/dev/null 2>&1
fi

# Download firmware list from Ubiquiti API
API_URL="https://fw-update.ui.com/api/firmware-latest"
TEMP_JSON=$(mktemp)

if ! curl -fsSL "$API_URL" -o "$TEMP_JSON"; then
  rm -f "$TEMP_JSON"
  msg_error "Failed to fetch data from Ubiquiti API"
  exit 1
fi

# Parse JSON to find latest unifi-os-server linux-x64 version
LATEST=$(jq -r '
  ._embedded.firmware
  | map(select(.product == "unifi-os-server"))
  | map(select(.platform == "linux-x64"))
  | sort_by(.version_major, .version_minor, .version_patch)
  | last
' "$TEMP_JSON")

UOS_VERSION=$(echo "$LATEST" | jq -r '.version' | sed 's/^v//')
UOS_URL=$(echo "$LATEST" | jq -r '._links.data.href')

# Cleanup temp file
rm -f "$TEMP_JSON"

if [ -z "$UOS_URL" ] || [ -z "$UOS_VERSION" ]; then
  msg_error "Failed to parse UniFi OS Server version or download URL"
  exit 1
fi

UOS_INSTALLER="unifi-os-server-${UOS_VERSION}.bin"
msg_ok "Found UniFi OS Server ${UOS_VERSION}"

# --- Download Cloud Image ---
msg_info "Downloading ${OS_DISPLAY} Cloud Image"
URL=$(get_image_url)
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

msg_ok "Downloaded ${OS_DISPLAY} Cloud Image"

# Expand root partition to use full disk space
msg_info "Expanding disk image to ${DISK_SIZE}"

# Install virt-resize if not available
if ! command -v virt-resize &>/dev/null; then
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools -y >/dev/null
fi

qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE} >/dev/null 2>&1

# Detect partition device (sda1 for Ubuntu, vda1 for Debian)
PARTITION_DEV=$(virt-filesystems --long -h --all -a "${FILE}" | grep -oP '/dev/\K(s|v)da1' | head -1)
if [ -z "$PARTITION_DEV" ]; then
  PARTITION_DEV="sda1" # fallback
fi

virt-resize --quiet --expand /dev/${PARTITION_DEV} ${FILE} expanded.qcow2 >/dev/null 2>&1
mv expanded.qcow2 ${FILE}
msg_ok "Expanded disk image to ${DISK_SIZE}"

# --- Download UniFi OS installer on the host ---
msg_info "Downloading UniFi OS Server ${UOS_VERSION} installer"
curl -fsSL "${UOS_URL}" -o "unifi-os-server.bin"
chmod +x "unifi-os-server.bin"
msg_ok "Downloaded UniFi OS Server installer"

# --- Pre-install packages and setup first-boot installer via virt-customize ---
msg_info "Customizing disk image (installing packages, staging installer)"

# Create the first-boot installer script
FIRSTBOOT_SCRIPT=$(mktemp)
cat >"$FIRSTBOOT_SCRIPT" <<'FBEOF'
#!/bin/bash
set -e
LOG="/var/log/unifi-os-install.log"
exec > >(tee -a "$LOG") 2>&1
echo "[$(date)] Starting UniFi OS Server first-boot setup..."

# Sync clock before apt (fresh VMs have clock skew that breaks GPG signature validation)
echo "[$(date)] Syncing system clock..."
timedatectl set-ntp true 2>/dev/null || true
# Try NTP first
for attempt in {1..6}; do
  if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q "yes"; then
    echo "[$(date)] Clock synchronized via NTP"
    break
  fi
  sleep 5
done
# Fallback: sync from HTTP header if NTP didn't work
if ! timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q "yes"; then
  HTTP_DATE=$(curl -sI https://deb.debian.org 2>/dev/null | grep -i "^date:" | sed 's/^[Dd]ate: //')
  if [ -n "$HTTP_DATE" ]; then
    date -s "$HTTP_DATE" >/dev/null 2>&1 || true
    echo "[$(date)] Clock synchronized via HTTP"
  fi
fi

# Install required packages
export DEBIAN_FRONTEND=noninteractive
echo "[$(date)] Installing packages..."
for attempt in {1..3}; do
  if apt-get update -qq 2>&1; then
    break
  fi
  echo "[$(date)] apt-get update failed (attempt $attempt/3), retrying in 10s..."
  sleep 10
done
for attempt in {1..3}; do
  if apt-get install -y -qq qemu-guest-agent podman uidmap slirp4netns curl wget; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    echo "[$(date)] apt-get install failed after 3 attempts"
    exit 1
  fi
  echo "[$(date)] apt-get install failed (attempt $attempt/3), retrying in 10s..."
  sleep 10
done
systemctl enable --now qemu-guest-agent
echo "[$(date)] Packages installed"

# Setup swap (2GB)
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "[$(date)] Swap file created"
fi

# Run UniFi OS installer
if [ -f /opt/unifi-os-server.bin ]; then
  cd /opt
  echo y | ./unifi-os-server.bin
  rm -f /opt/unifi-os-server.bin
  echo "[$(date)] UniFi OS Server installed successfully"
else
  echo "[$(date)] ERROR: /opt/unifi-os-server.bin not found"
  exit 1
fi

# Disable this service after successful run
systemctl disable unifi-os-firstboot.service
echo "[$(date)] First-boot setup complete"
FBEOF

# Create the systemd service unit file
FIRSTBOOT_SVC=$(mktemp)
cat >"$FIRSTBOOT_SVC" <<'SVCEOF'
[Unit]
Description=UniFi OS Server First Boot Installer
After=network-online.target
Wants=network-online.target
ConditionPathExists=/opt/unifi-os-server.bin

[Service]
Type=oneshot
ExecStart=/opt/unifi-os-firstboot.sh
RemainAfterExit=yes
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
SVCEOF

virt-customize -a "${FILE}" \
# Cloud images run no getty on tty1, which is why the Proxmox console
# stays black even though the VM is running.
vm_enable_consoles "$FILE"
  --upload "unifi-os-server.bin:/opt/unifi-os-server.bin" \
  --chmod 0755:/opt/unifi-os-server.bin \
  --upload "$FIRSTBOOT_SCRIPT:/opt/unifi-os-firstboot.sh" \
  --chmod 0755:/opt/unifi-os-firstboot.sh \
  --upload "$FIRSTBOOT_SVC:/etc/systemd/system/unifi-os-firstboot.service" \
  --run-command "systemctl enable unifi-os-firstboot.service" \
  --run-command "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" \
  --run-command "sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" \
  --run-command "systemctl enable ssh" \
  2>&1 | while read -r line; do echo -ne "${BFR}${TAB}${YW}${HOLD}${line}${HOLD}"; done

rm -f "$FIRSTBOOT_SCRIPT" "$FIRSTBOOT_SVC" "unifi-os-server.bin"
msg_ok "Disk image customized (UniFi OS ${UOS_VERSION} staged for first-boot install)"

msg_info "Creating UniFi OS VM"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf \
  ${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script \
  -net0 virtio,bridge="$BRG",macaddr="$MAC""$VLAN""$MTU" \
  -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

pvesm alloc "$STORAGE" "$VMID" "vm-$VMID-disk-0" 4M >/dev/null
IMPORT_OUT="$(qm importdisk "$VMID" "$FILE" "$STORAGE" --format qcow2 2>&1 || true)"
DISK_REF="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p")"

if [[ -z "$DISK_REF" ]]; then
  DISK_REF="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$1 ~ ("vm-"id"-disk-") {print $1}' | sort | tail -n1)"
fi

qm set "$VMID" \
  -efidisk0 "${STORAGE}:0${FORMAT},size=4M" \
  -scsi0 "${DISK_REF},${DISK_CACHE}size=${DISK_SIZE}" \
  -boot order=scsi0 -serial0 socket >/dev/null
qm resize "$VMID" scsi0 "$DISK_SIZE" >/dev/null
qm set "$VMID" --agent enabled=1 >/dev/null

# Whole block guarded: --cipassword and --sshkeys need the drive too.
if load_cloud_init_functions; then
  msg_info "Configuring Cloud-Init"
  setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" >/dev/null 2>&1
  # Override with user-set password
  qm set "$VMID" --cipassword "$USER_PASSWORD" >/dev/null
  # Add SSH keys if provided
  if [ -n "${SSH_KEYS_FILE:-}" ] && [ -f "${SSH_KEYS_FILE:-}" ]; then
    qm set "$VMID" --sshkeys "$SSH_KEYS_FILE" >/dev/null
    rm -f "$SSH_KEYS_FILE"
  fi
  msg_ok "Cloud-Init configured"
else
  msg_warn "Cloud-Init helpers unavailable -- VM created, but no Cloud-Init drive, password or SSH keys were set"
fi

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Unifi OS VM</h2>

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

msg_ok "Created a UniFi OS VM ${CL}${BL}(${HN})"
msg_info "Operating System: ${OS_DISPLAY}"
msg_info "Cloud-Init: ${USE_CLOUD_INIT}"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting UniFi OS VM"
  qm start $VMID
  msg_ok "Started UniFi OS VM"

  # Wait for guest agent (installed by first-boot service)
  msg_info "Waiting for guest agent (first-boot installs packages, ~5-6 min)"
  VM_IP=""
  for i in {1..180}; do
    VM_IP=$(qm guest cmd $VMID network-get-interfaces 2>/dev/null | jq -r '.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4") | .["ip-address"]' 2>/dev/null | grep -v "^127\." | head -1 || echo "")
    if [ -n "$VM_IP" ]; then
      break
    fi
    # Show elapsed time so it doesn't look stuck
    printf "\r${TAB}${YW}${HOLD}Waiting for guest agent (first-boot installs packages, ~5-6 min) [%ds]${HOLD}" "$((i * 2))"
    sleep 2
  done

  if [ -n "$VM_IP" ]; then
    msg_ok "Guest agent responding — VM IP: ${VM_IP}"
  else
    msg_ok "VM started (could not detect IP — check VM console)"
  fi

  # Wait for UniFi OS to be ready on port 11443
  if [ -n "$VM_IP" ]; then
    msg_info "Waiting for UniFi OS to start on https://${VM_IP}:11443 (may take several minutes)"
    UNIFI_READY=""
    for i in {1..60}; do
      if curl -skI --max-time 3 "https://${VM_IP}:11443" &>/dev/null; then
        UNIFI_READY="yes"
        break
      fi
      printf "\r${TAB}${YW}${HOLD}Waiting for UniFi OS to start on https://${VM_IP}:11443 (may take several minutes) [%ds]${HOLD}" "$((i * 5))"
      sleep 5
    done

    if [ -n "$UNIFI_READY" ]; then
      msg_ok "UniFi OS is up at https://${VM_IP}:11443"
    else
      msg_ok "UniFi OS not yet responding (first-boot may still be running)"
    fi
  fi

  echo ""
  echo -e "${TAB}${GATEWAY}${BOLD}${GN}UniFi OS Server VM created successfully!${CL}"
  if [ -n "$VM_IP" ]; then
    echo -e "${TAB}${GATEWAY}${BOLD}${GN}Access at: ${BGN}https://${VM_IP}:11443${CL}"
  else
    echo -e "${TAB}${INFO}${YW}Access via: ${BGN}https://<VM-IP>:11443${CL}"
  fi
  echo -e "${TAB}${INFO}${DGN}Console login: ${BGN}root${CL} ${DGN}(password set during setup)${CL}"
  echo ""
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

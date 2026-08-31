#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://netbird.io

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/vm/cloud-init.func") 2>/dev/null || true
load_functions

function header_info {
  clear
  cat <<"EOF"
  _   _      _   ____  _         _   ____
 | \ | | ___| |_| __ )(_)_ __ __| | / ___|  ___ _ ____   _____ _ __
 |  \| |/ _ \ __|  _ \| | '__/ _` | \___ \ / _ \ '__\ \ / / _ \ '__|
 | |\  |  __/ |_| |_) | | | | (_| |  ___) |  __/ |   \ V /  __/ |
 |_| \_|\___|\__|____/|_|_|  \__,_| |____/ \___|_|    \_/ \___|_|

EOF
}

APP="NetBird Server"
APP_TYPE="vm"
NSAPP="netbird-server"
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
DISK_SIZE="10G"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
USE_CLOUD_INIT="no"
OS_TYPE=""
OS_VERSION=""
OS_CODENAME=""
OS_DISPLAY=""
THIN="discard=on,ssd=1,"
NETBIRD_DOMAIN_INPUT=""
NETBIRD_PROXY_TYPE_INPUT="0"
NETBIRD_EMAIL_INPUT=""

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

if vm_confirm_new_vm "$APP" "This will create a New $APP VM. Proceed?"; then
  :
else
  header_info && exit_script
fi

check_root
arch_check
pve_check

# ==============================================================================
# NETBIRD CONFIGURATION PROMPTS
# ==============================================================================
function configure_netbird_setup() {
  while true; do
    if NETBIRD_DOMAIN_INPUT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "NETBIRD DOMAIN" \
      --inputbox "Enter the public domain for your NetBird server.\n(DNS A record must point to this VM's public IP)\n\ne.g. netbird.my-domain.com" 11 65 "" \
      --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [[ -z "$NETBIRD_DOMAIN_INPUT" ]] || [[ "$NETBIRD_DOMAIN_INPUT" == "netbird.example.com" ]]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID DOMAIN" \
          --msgbox "Please enter a valid domain name." 8 50
        continue
      fi
      echo -e "${INFO}${BOLD}${DGN}NetBird Domain: ${BGN}${NETBIRD_DOMAIN_INPUT}${CL}"
      break
    else
      exit_script
    fi
  done

  if NETBIRD_PROXY_TYPE_INPUT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "REVERSE PROXY" --radiolist \
    "Select the reverse proxy for NetBird" 14 70 4 \
    "0" "Traefik (recommended, built-in with auto TLS)" ON \
    "2" "Nginx (generates config template)" OFF \
    "3" "Nginx Proxy Manager" OFF \
    "5" "Other/Manual" OFF \
    3>&1 1>&2 2>&3); then
    echo -e "${INFO}${BOLD}${DGN}Reverse Proxy: ${BGN}${NETBIRD_PROXY_TYPE_INPUT}${CL}"
  else
    exit_script
  fi

  if [[ "$NETBIRD_PROXY_TYPE_INPUT" == "0" ]]; then
    while true; do
      if NETBIRD_EMAIL_INPUT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "LETSENCRYPT EMAIL" \
        --inputbox "Enter your email for Let's Encrypt certificates:" 8 65 "" \
        --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [[ -z "$NETBIRD_EMAIL_INPUT" ]]; then
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID EMAIL" \
            --msgbox "Email is required for Let's Encrypt." 8 50
          continue
        fi
        echo -e "${INFO}${BOLD}${DGN}Let's Encrypt Email: ${BGN}${NETBIRD_EMAIL_INPUT}${CL}"
        break
      else
        exit_script
      fi
    done
  fi
}

# ==============================================================================
# OS SELECTION
# ==============================================================================
function select_os() {
  if OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SELECT OS" --radiolist \
    "Choose Operating System for NetBird Server VM" 14 68 3 \
    "debian13" "Debian 13 (Trixie) - Latest" ON \
    "debian12" "Debian 12 (Bookworm) - Stable" OFF \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF \
    3>&1 1>&2 2>&3); then
    case $OS_CHOICE in
    debian13)
      OS_TYPE="debian"
      OS_VERSION="13"
      OS_CODENAME="trixie"
      OS_DISPLAY="Debian 13 (Trixie)"
      ;;
    debian12)
      OS_TYPE="debian"
      OS_VERSION="12"
      OS_CODENAME="bookworm"
      OS_DISPLAY="Debian 12 (Bookworm)"
      ;;
    ubuntu2404)
      OS_TYPE="ubuntu"
      OS_VERSION="24.04"
      OS_CODENAME="noble"
      OS_DISPLAY="Ubuntu 24.04 LTS"
      ;;
    esac
    echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}${OS_DISPLAY}${CL}"
  else
    exit_script
  fi
}

function select_cloud_init() {
  if [ "$OS_TYPE" = "ubuntu" ]; then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-  }${BOLD}${DGN}Cloud-Init: ${BGN}yes (Ubuntu requires Cloud-Init)${CL}"
    return
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?\n\nAllows automatic configuration of user accounts, SSH keys, and network settings.\n\nDebian without Cloud-Init uses nocloud image with console auto-login." 14 68); then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-  }${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  else
    USE_CLOUD_INIT="no"
    echo -e "${CLOUD:-  }${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
  fi
}

function get_image_url() {
  local arch
  arch=$(dpkg --print-architecture)
  case $OS_TYPE in
  debian)
    if [ "$USE_CLOUD_INIT" = "yes" ]; then
      echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-generic-${arch}.qcow2"
    else
      echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-nocloud-${arch}.qcow2"
    fi
    ;;
  ubuntu)
    echo "https://cloud-images.ubuntu.com/${OS_CODENAME}/current/${OS_CODENAME}-server-cloudimg-${arch}.img"
    ;;
  esac
}

# ==============================================================================
# SETTINGS
# ==============================================================================
function default_settings() {
  vm_apply_machine_type "q35"
  configure_netbird_setup
  select_os
  select_cloud_init

  VMID=$(get_valid_nextid)
  DISK_CACHE=""
  DISK_SIZE="10G"
  HN="netbird"
  CPU_TYPE=" -cpu host"
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
  configure_netbird_setup
  select_os
  select_cloud_init
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "10G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "netbird"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a NetBird Server VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a NetBird Server VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}


# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

# ==============================================================================
# STORAGE SELECTION
# ==============================================================================
vm_select_storage "$HN"

# ==============================================================================
# PREREQUISITES
# ==============================================================================
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools -y >/dev/null
  msg_ok "Installed libguestfs-tools"
fi

# ==============================================================================
# IMAGE DOWNLOAD
# ==============================================================================
msg_info "Retrieving the URL for the ${OS_DISPLAY} Disk Image"
URL=$(get_image_url)
CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="$CACHE_DIR/$(basename "$URL")"
mkdir -p "$CACHE_DIR"
msg_ok "${CL}${BL}${URL}${CL}"

if [[ ! -s "$CACHE_FILE" ]]; then
  curl -f#SL -o "$CACHE_FILE" "$URL"
  echo -en "\e[1A\e[0K"
  msg_ok "Downloaded ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
else
  msg_ok "Using cached image ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
fi

# ==============================================================================
# STORAGE TYPE DETECTION
# ==============================================================================
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
  DISK_IMPORT="--format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="--format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="--format raw"
  ;;
esac

# ==============================================================================
# IMAGE CUSTOMIZATION
# ==============================================================================
msg_info "Preparing ${OS_DISPLAY} image with Docker & prerequisites"

WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$CACHE_FILE" "$WORK_FILE"

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

DOCKER_PREINSTALLED="no"

msg_info "Installing base packages (qemu-guest-agent, curl, ca-certificates, jq)"
if virt-customize -a "$WORK_FILE" --install qemu-guest-agent,curl,ca-certificates,jq >/dev/null 2>&1; then
  msg_ok "Installed base packages"

  msg_info "Installing Docker (this may take 2-5 minutes)"
  if virt-customize -q -a "$WORK_FILE" --run-command "curl -fsSL https://get.docker.com | sh" >/dev/null 2>&1 &&
    virt-customize -q -a "$WORK_FILE" --run-command "systemctl enable docker" >/dev/null 2>&1; then
    msg_ok "Installed Docker"

    msg_info "Configuring Docker daemon"
    virt-customize -q -a "$WORK_FILE" --run-command "mkdir -p /etc/docker" >/dev/null 2>&1
    virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF' >/dev/null 2>&1
    DOCKER_PREINSTALLED="yes"
    msg_ok "Configured Docker daemon"
  else
    msg_ok "Docker will be installed on first boot"
  fi
else
  msg_ok "Packages will be installed on first boot"
fi

# Write NetBird env file (host variables expanded into the image)
msg_info "Writing NetBird configuration"
NETBIRD_ENV_TMP=$(mktemp)
cat >"$NETBIRD_ENV_TMP" <<ENVEOF
NETBIRD_DOMAIN="${NETBIRD_DOMAIN_INPUT}"
NETBIRD_AUTO_PROXY_TYPE="${NETBIRD_PROXY_TYPE_INPUT}"
NETBIRD_AUTO_EMAIL="${NETBIRD_EMAIL_INPUT}"
NETBIRD_AUTO_ENABLE_PROXY="false"
NETBIRD_AUTO_ENABLE_CROWDSEC="false"
ENVEOF
virt-customize -q -a "$WORK_FILE" --upload "${NETBIRD_ENV_TMP}:/root/netbird.env" >/dev/null 2>&1
rm -f "$NETBIRD_ENV_TMP"

# Write first-boot setup script (no host variable expansion needed — single-quoted heredoc)
NETBIRD_SETUP_TMP=$(mktemp)
cat >"$NETBIRD_SETUP_TMP" <<'SETUPEOF'
#!/bin/bash
exec > /var/log/netbird-setup.log 2>&1
set -e

echo "[$(date)] Starting NetBird automated setup"

# Wait for Docker (up to 5 minutes)
for i in {1..60}; do
  docker info >/dev/null 2>&1 && break
  sleep 5
done
docker info >/dev/null 2>&1 || { echo "[$(date)] ERROR: Docker not ready after 5 min"; exit 1; }

# Load pre-configured values
set -a
source /root/netbird.env
set +a

# Download getting-started.sh
curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh \
  -o /root/getting-started.sh

# Patch interactive reads: use NETBIRD_AUTO_* env vars (never overwritten by initialize_default_values)
sed -i \
  -e 's/REVERSE_PROXY_TYPE=$(read_reverse_proxy_type)/REVERSE_PROXY_TYPE="${NETBIRD_AUTO_PROXY_TYPE:-$(read_reverse_proxy_type)}"/'\
  -e 's/TRAEFIK_ACME_EMAIL=$(read_traefik_acme_email)/TRAEFIK_ACME_EMAIL="${NETBIRD_AUTO_EMAIL:-$(read_traefik_acme_email)}"/'\
  -e 's/ENABLE_PROXY=$(read_enable_proxy)/ENABLE_PROXY="${NETBIRD_AUTO_ENABLE_PROXY:-$(read_enable_proxy)}"/'\
  -e 's/ENABLE_CROWDSEC=$(read_enable_crowdsec)/ENABLE_CROWDSEC="${NETBIRD_AUTO_ENABLE_CROWDSEC:-$(read_enable_crowdsec)}"/'\
  /root/getting-started.sh

echo "[$(date)] Running NetBird getting-started.sh"
bash /root/getting-started.sh

touch /root/.netbird-setup-done
echo "[$(date)] NetBird setup completed"
SETUPEOF
virt-customize -q -a "$WORK_FILE" \
  --upload "${NETBIRD_SETUP_TMP}:/root/netbird-setup.sh" \
  --run-command "chmod +x /root/netbird-setup.sh" >/dev/null 2>&1
rm -f "$NETBIRD_SETUP_TMP"

# Write first-boot systemd service
NETBIRD_SVC_TMP=$(mktemp)
cat >"$NETBIRD_SVC_TMP" <<'SVCEOF'
[Unit]
Description=NetBird Initial Setup
After=network-online.target docker.service
Wants=network-online.target
ConditionPathExists=!/root/.netbird-setup-done

[Service]
Type=oneshot
ExecStart=/root/netbird-setup.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
SVCEOF
virt-customize -q -a "$WORK_FILE" \
  --upload "${NETBIRD_SVC_TMP}:/etc/systemd/system/netbird-setup.service" \
  --run-command "systemctl enable netbird-setup.service" >/dev/null 2>&1
rm -f "$NETBIRD_SVC_TMP"
msg_ok "Configured NetBird first-boot automation"

msg_info "Finalizing image"
virt-customize -q -a "$WORK_FILE" --hostname "${HN}" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1 || true

if [ "$USE_CLOUD_INIT" = "yes" ]; then
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
else
  virt-customize -q -a "$WORK_FILE" --run-command "mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF' >/dev/null 2>&1 || true
fi
msg_ok "Finalized image"

if [ "$DOCKER_PREINSTALLED" = "no" ]; then
  DOCKER_INSTALL_TMP=$(mktemp)
  cat >"$DOCKER_INSTALL_TMP" <<'DOCKEREOF'
#!/bin/bash
exec > /var/log/install-docker.log 2>&1
echo "[$(date)] Starting Docker installation"
for i in {1..30}; do
  ping -c 1 8.8.8.8 >/dev/null 2>&1 && break
  sleep 2
done
apt-get update
apt-get install -y qemu-guest-agent curl ca-certificates jq
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
touch /root/.docker-installed
echo "[$(date)] Docker installation completed"
DOCKEREOF
  DOCKER_SVC_TMP=$(mktemp)
  cat >"$DOCKER_SVC_TMP" <<'DOCKERSVCEOF'
[Unit]
Description=Install Docker on First Boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/root/.docker-installed

[Service]
Type=oneshot
ExecStart=/root/install-docker.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
DOCKERSVCEOF
  virt-customize -q -a "$WORK_FILE" \
    --upload "${DOCKER_INSTALL_TMP}:/root/install-docker.sh" \
    --upload "${DOCKER_SVC_TMP}:/etc/systemd/system/install-docker.service" \
    --run-command "chmod +x /root/install-docker.sh" \
    --run-command "systemctl enable install-docker.service" >/dev/null 2>&1 || true
  rm -f "$DOCKER_INSTALL_TMP" "$DOCKER_SVC_TMP"
fi

msg_info "Resizing disk image to ${DISK_SIZE}"
qemu-img resize "$WORK_FILE" "${DISK_SIZE}" >/dev/null 2>&1
msg_ok "Resized disk image"

# ==============================================================================
# VM CREATION
# ==============================================================================
msg_info "Creating NetBird Server VM shell"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
msg_ok "Created VM shell"

# ==============================================================================
# DISK IMPORT
# ==============================================================================
msg_info "Importing disk into storage ($STORAGE)"
if qm disk import --help >/dev/null 2>&1; then
  IMPORT_CMD=(qm disk import)
else
  IMPORT_CMD=(qm importdisk)
fi

IMPORT_OUT="$("${IMPORT_CMD[@]}" "$VMID" "$WORK_FILE" "$STORAGE" ${DISK_IMPORT:-} 2>&1 || true)"
DISK_REF_IMPORTED="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p" | tr -d "\r\"'")"
[[ -z "$DISK_REF_IMPORTED" ]] && DISK_REF_IMPORTED="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"
[[ -z "$DISK_REF_IMPORTED" ]] && {
  msg_error "Unable to determine imported disk reference."
  echo "$IMPORT_OUT"
  exit 226
}
msg_ok "Imported disk (${CL}${BL}${DISK_REF_IMPORTED}${CL})"

rm -f "$WORK_FILE"

# ==============================================================================
# VM CONFIGURATION
# ==============================================================================
msg_info "Attaching EFI and root disk"
qm set "$VMID" \
  --efidisk0 "${STORAGE}:0,efitype=4m" \
  --scsi0 "${DISK_REF_IMPORTED},${DISK_CACHE}${THIN%,}" \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
qm set $VMID --agent enabled=1 >/dev/null
msg_ok "Attached EFI and root disk"

set_description

msg_info "Configuring Cloud-Init"
if vm_provision "$VMID"; then
  msg_ok "Cloud-Init configured"
else
  msg_warn "VM created, but not provisioned"
fi

# ==============================================================================
# START VM
# ==============================================================================
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting NetBird Server VM"
  qm start $VMID >/dev/null 2>&1
  msg_ok "Started NetBird Server VM"
fi

# ==============================================================================
# FINAL OUTPUT
# ==============================================================================
VM_IP=""
if [ "$START_VM" == "yes" ]; then
  set +e
  for i in {1..10}; do
    VM_IP=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null |
      jq -r '.[] | select(.name != "lo") | ."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address"' 2>/dev/null |
      grep -v "^127\." | head -1) || true
    [ -n "$VM_IP" ] && break
    sleep 3
  done
  set -e
fi

echo -e "\n${INFO}${BOLD}${GN}NetBird Server VM Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}OS: ${BGN}${OS_DISPLAY}${CL}"
[ -n "$VM_IP" ] && echo -e "${TAB}${DGN}IP Address: ${BGN}${VM_IP}${CL}"

if [ "$DOCKER_PREINSTALLED" = "yes" ]; then
  echo -e "${TAB}${DGN}Docker: ${BGN}Pre-installed${CL}"
else
  echo -e "${TAB}${DGN}Docker: ${BGN}Installing on first boot — check: ${BL}journalctl -u netbird-setup${CL}"
fi

echo -e ""
echo -e "${INFO}${BOLD}${GN}NetBird is being configured automatically on first boot!${CL}"
echo -e "${TAB}${DGN}Domain: ${BGN}https://${NETBIRD_DOMAIN_INPUT}${CL}"
echo -e "${TAB}${DGN}Setup log: ${BGN}journalctl -u netbird-setup -f${CL}"
echo -e "${TAB}${DGN}Required open ports: ${BGN}80/tcp, 443/tcp, 3478/udp${CL}"

if [ "$USE_CLOUD_INIT" = "yes" ]; then
  display_cloud_init_info "$VMID" "$HN" 2>/dev/null || true
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

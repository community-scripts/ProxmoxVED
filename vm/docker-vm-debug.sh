#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: thost96 (thost96) | Co-Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions
# Load Cloud-Init library for VM configuration

header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="docker-vm"
var_os="debian"
var_version="13"
DISK_SIZE="10G"
USE_CLOUD_INIT="no"
INSTALL_PORTAINER="no"
OS_TYPE=""
OS_VERSION=""

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker VM" --yesno "This will create a New Docker VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function spinner() {
  local pid=$1
  local msg="$2"
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0

  echo -ne "${TAB}${YW}${msg} "
  while kill -0 $pid; do
    i=$(((i + 1) % 10))
    echo -ne "\b${spin:$i:1}"
    sleep 0.1
  done
  echo -ne "\b"
}

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x and 9.0 – 9.2

function select_os() {
  if OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SELECT OS" --radiolist \
    "Choose Operating System for Docker VM" 14 68 4 \
    "debian13" "Debian 13 (Trixie) - Latest" ON \
    "debian12" "Debian 12 (Bookworm) - Stable" OFF \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF \
    "ubuntu2204" "Ubuntu 22.04 LTS (Jammy)" OFF \
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
    ubuntu2204)
      OS_TYPE="ubuntu"
      OS_VERSION="22.04"
      OS_CODENAME="jammy"
      OS_DISPLAY="Ubuntu 22.04 LTS"
      ;;
    esac
    echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}${OS_DISPLAY}${CL}"
  else
    exit_script
  fi
}

function select_cloud_init() {
  # Ubuntu only has cloudimg variant (always Cloud-Init), so no choice needed
  if [ "$OS_TYPE" = "ubuntu" ]; then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}yes (Ubuntu requires Cloud-Init)${CL}"
    return
  fi

  # Debian has two image variants, so user can choose
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?\n\nCloud-Init allows automatic configuration of:\n• User accounts and passwords\n• SSH keys\n• Network settings (DHCP/Static)\n• DNS configuration\n\nYou can also configure these settings later in Proxmox UI.\n\nNote: Debian without Cloud-Init will use nocloud image with console auto-login." 18 68); then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  else
    USE_CLOUD_INIT="no"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
  fi
}

function select_portainer() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "PORTAINER" \
    --yesno "Install Portainer for Docker management?\n\nPortainer is a lightweight management UI for Docker.\n\nAccess after installation:\n• HTTP:  http://<VM-IP>:9000\n• HTTPS: https://<VM-IP>:9443" 14 68); then
    INSTALL_PORTAINER="yes"
    echo -e "${ADVANCED}${BOLD}${DGN}Portainer: ${BGN}yes${CL}"
  else
    INSTALL_PORTAINER="no"
    echo -e "${ADVANCED}${BOLD}${DGN}Portainer: ${BGN}no${CL}"
  fi
}

function get_image_url() {
  local arch=$(dpkg --print-architecture)
  case $OS_TYPE in
  debian)
    # Debian has two variants:
    # - generic: For Cloud-Init enabled VMs
    # - nocloud: For VMs without Cloud-Init (has console auto-login)
    if [ "$USE_CLOUD_INIT" = "yes" ]; then
      echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-generic-${arch}.qcow2"
    else
      echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-nocloud-${arch}.qcow2"
    fi
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

  # Portainer Selection - ALWAYS ask
  select_portainer

  # Set defaults for other settings
  VMID=$(get_valid_nextid)
  DISK_CACHE=""
  DISK_SIZE="10G"
  HN="docker"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="2"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  # Display summary
  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  select_os
  select_cloud_init
  select_portainer
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "10G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "docker"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a docker-vm-debug VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a docker-vm-debug VM using the above advanced settings${CL}"
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

if ! command -v virt-customize; then
  msg_info "Installing Pre-Requisite libguestfs-tools onto Host"
  apt-get update
  apt-get install libguestfs-tools lsb-release -y
  # Workaround for Proxmox VE 9.0 libguestfs issue
  apt-get install dhcpcd-base -y || true
  msg_ok "Installed libguestfs-tools successfully"
fi

msg_info "Retrieving the URL for the ${OS_DISPLAY} Qcow2 Disk Image"
URL=$(get_image_url)
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# qm resize only grows the block device. Without cloud-init nothing grows the
# guest partition, so expand it offline first.
if [ "${CLOUD_INIT:-no}" != "yes" ]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$FILE" "$DISK_SIZE" || true
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
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

echo -e "${INFO}${BOLD}${GN}Preparing ${OS_DISPLAY} Qcow2 Disk Image${CL}"

# Set DNS for libguestfs appliance environment (not the guest)
export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

# Always create first-boot installation script as fallback
virt-customize -a "${FILE}" --run-command "cat > /root/install-docker.sh << 'INSTALLEOF'
#!/bin/bash
# Debug mode - output to stdout/stderr (no log file redirection)
set -x
echo \"[\\$(date)] Starting Docker installation on first boot\"

# Check if Docker is already installed
if command -v docker; then
  echo \"[\\$(date)] Docker already installed, checking if running\"
  systemctl start docker || true
  if docker info; then
    echo \"[\\$(date)] Docker is already working, exiting\"
    exit 0
  fi
fi

# Wait for network to be fully available
for i in {1..30}; do
  if ping -c 1 8.8.8.8; then
    echo \"[\\$(date)] Network is available\"
    break
  fi
  echo \"[\\$(date)] Waiting for network... attempt \\$i/30\"
  sleep 2
done

# Configure DNS
echo \"[\\$(date)] Configuring DNS\"
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/dns.conf << DNSEOF
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=8.8.4.4 1.0.0.1
DNSEOF
systemctl restart systemd-resolved || true

# Update package lists
echo \"[\\$(date)] Updating package lists\"
apt-get update

# Install base packages if not already installed
echo \"[\\$(date)] Installing base packages\"
apt-get install -y qemu-guest-agent curl ca-certificates || true

# Install Docker
echo \"[\\$(date)] Installing Docker\"
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
for i in {1..10}; do
  if docker info; then
    echo \"[\\$(date)] Docker is ready\"
    break
  fi
  sleep 1
done

# Install Portainer if requested
INSTALL_PORTAINER_PLACEHOLDER

# Create completion flag
echo \"[\\$(date)] Docker installation completed successfully\"
touch /root/.docker-installed
INSTALLEOF"

# Add Portainer installation script if requested
if [ "$INSTALL_PORTAINER" = "yes" ]; then
  virt-customize -a "${FILE}" --run-command "cat > /root/install-portainer.sh << 'PORTAINEREOF'
#!/bin/bash
# Debug mode - output to stdout/stderr
set -x
echo \"[\\$(date)] Installing Portainer\"
docker volume create portainer_data
docker run -d -p 9000:9000 -p 9443:9443 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
echo \"[\\$(date)] Portainer installed and started\"
PORTAINEREOF"
  virt-customize -a "${FILE}" --run-command "chmod +x /root/install-portainer.sh"
  virt-customize -a "${FILE}" --run-command "sed -i 's|INSTALL_PORTAINER_PLACEHOLDER|/root/install-portainer.sh|' /root/install-docker.sh"
else
  virt-customize -a "${FILE}" --run-command "sed -i 's|INSTALL_PORTAINER_PLACEHOLDER|echo \"[\\\\\\$(date)] Skipping Portainer installation\"|' /root/install-docker.sh"
fi

virt-customize -a "${FILE}" --run-command "chmod +x /root/install-docker.sh"

virt-customize -a "${FILE}" --run-command "cat > /etc/systemd/system/install-docker.service << 'SERVICEEOF'
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
SERVICEEOF"

virt-customize -a "${FILE}" --run-command "systemctl enable install-docker.service"

# Try to install packages and Docker during image customization
DOCKER_INSTALLED_ON_FIRST_BOOT="yes" # Assume first-boot by default

msg_info "Installing base packages (qemu-guest-agent, curl, ca-certificates)"
if virt-customize -a "${FILE}" --install qemu-guest-agent,curl,ca-certificates; then
  msg_ok "Installed base packages"

  msg_info "Installing Docker via get.docker.com"
  if virt-customize -a "${FILE}" --run-command "curl -fsSL https://get.docker.com | sh" &&
    virt-customize -a "${FILE}" --run-command "systemctl enable docker"; then
    msg_ok "Installed Docker"

    # Optimize Docker daemon configuration
    virt-customize -a "${FILE}" --run-command "mkdir -p /etc/docker"
    virt-customize -a "${FILE}" --run-command "cat > /etc/docker/daemon.json << 'DOCKEREOF'
{
  \"storage-driver\": \"overlay2\",
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"10m\",
    \"max-file\": \"3\"
  }
}
DOCKEREOF"

    # Create completion flag to prevent first-boot script from running
    virt-customize -a "${FILE}" --run-command "touch /root/.docker-installed"

    DOCKER_INSTALLED_ON_FIRST_BOOT="no"
  else
    msg_ok "Docker will be installed on first boot (installation failed during image preparation)"
  fi
else
  msg_ok "Packages will be installed on first boot (network not available during image preparation)"
fi

# Set hostname and clean machine-id
virt-customize -a "${FILE}" --hostname "${HN}"
vm_prepare_cloud_image "$FILE" "$HN" || true

# Configure SSH to allow root login with password when Cloud-Init is enabled
# (Cloud-Init will set the password, but SSH needs to accept password authentication)
if [ "$USE_CLOUD_INIT" = "yes" ]; then
  virt-customize -a "${FILE}" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" || true
  virt-customize -a "${FILE}" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" || true
fi

msg_info "Expanding root partition to use full disk space"
qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE}
virt-resize --expand /dev/sda1 ${FILE} expanded.qcow2
mv expanded.qcow2 ${FILE}
msg_ok "Expanded image to full size"

msg_info "Creating a Docker VM"

qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-}
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket
qm set $VMID --agent enabled=1

# Proxmox 9: Enable I/O Thread for better disk performance
if [ "${PVE_MAJOR:-8}" = "9" ]; then
  qm set $VMID -iothread 1 || true
fi

msg_ok "Created a Docker VM ${CL}${BL}(${HN})${CL}"

# Add Cloud-Init drive if requested
msg_info "Configuring Cloud-Init"
if vm_provision "$VMID"; then
  msg_ok "Cloud-Init configured"
else
  msg_warn "VM created, but not provisioned"
fi

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Docker VM</h2>

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
qm set "$VMID" -description "$DESCRIPTION"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Docker VM"
  qm start $VMID
  msg_ok "Started Docker VM"
fi

# Try to get VM IP address silently in background (max 10 seconds)
VM_IP=""
if [ "$START_VM" == "yes" ]; then
  for i in {1..5}; do
    VM_IP=$(qm guest cmd "$VMID" network-get-interfaces |
      jq -r '.[] | select(.name != "lo") | ."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address"' |
      grep -v "^127\." | head -1)

    if [ -n "$VM_IP" ]; then
      break
    fi
    sleep 2
  done
fi

# Display information about installed components
echo -e "\n${INFO}${BOLD}${GN}VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}OS: ${BGN}${OS_DISPLAY}${CL}"

if [ -n "$VM_IP" ]; then
  echo -e "${TAB}${DGN}IP Address: ${BGN}${VM_IP}${CL}"
fi

if [ "$DOCKER_INSTALLED_ON_FIRST_BOOT" = "yes" ]; then
  echo -e "${TAB}${DGN}Docker: ${BGN}Will be installed on first boot${CL}"
  echo -e "${TAB}${YW}⚠️  Docker installation will happen automatically after VM starts${CL}"
  echo -e "${TAB}${YW}⚠️  Wait 2-3 minutes after boot for installation to complete${CL}"
  echo -e "${TAB}${YW}⚠️  Check installation progress: ${BL}cat /var/log/install-docker.log${CL}"
else
  echo -e "${TAB}${DGN}Docker: ${BGN}Latest (via get.docker.com)${CL}"
fi

if [ "$INSTALL_PORTAINER" = "yes" ]; then
  if [ -n "$VM_IP" ]; then
    echo -e "${TAB}${DGN}Portainer: ${BGN}https://${VM_IP}:9443${CL}"
  else
    echo -e "${TAB}${DGN}Portainer: ${BGN}Will be accessible at https://<VM-IP>:9443${CL}"
    echo -e "${TAB}${YW}⚠️  Wait 2-3 minutes after boot for installation to complete${CL}"
    echo -e "${TAB}${YW}⚠️  Get IP with: ${BL}qm guest cmd ${VMID} network-get-interfaces${CL}"
  fi
fi
if [ "$USE_CLOUD_INIT" = "yes" ]; then
  display_cloud_init_info "$VMID" "$HN"
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: thost96 (thost96) | Co-Author: michelroegl-brunner | Refactored: MickLesk
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE

# ==============================================================================
# Docker VM - Creates a Docker-ready Virtual Machine with optional Portainer
# ==============================================================================

source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/api.func)
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/vm-core.func)
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/cloud-init.func) 2>/dev/null || true
load_functions

# ==============================================================================
# SCRIPT VARIABLES
# ==============================================================================
APP="Docker"
APP_TYPE="vm"
NSAPP="docker-vm"
var_os="debian"
var_version="13"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
DISK_SIZE="10G"
USE_CLOUD_INIT="no"
INSTALL_PORTAINER="no"
OS_TYPE=""
OS_VERSION=""
THIN="discard=on,ssd=1,"

# ==============================================================================
# ERROR HANDLING & CLEANUP
# ==============================================================================
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  post_update_to_api "failed" "${command}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

# ==============================================================================
# OS SELECTION FUNCTIONS
# ==============================================================================
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
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}yes (Ubuntu requires Cloud-Init)${CL}"
    return
  fi

  # Debian has two image variants, so user can choose
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?\n\nCloud-Init allows automatic configuration of:\n- User accounts and passwords\n- SSH keys\n- Network settings (DHCP/Static)\n- DNS configuration\n\nYou can also configure these settings later in Proxmox UI.\n\nNote: Debian without Cloud-Init will use nocloud image with console auto-login." 18 68); then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  else
    USE_CLOUD_INIT="no"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
  fi
}

function select_portainer() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "PORTAINER" \
    --yesno "Install Portainer for Docker management?\n\nPortainer is a lightweight management UI for Docker.\n\nAccess after installation:\n- HTTP:  http://<VM-IP>:9000\n- HTTPS: https://<VM-IP>:9443" 14 68); then
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
# SETTINGS FUNCTIONS
# ==============================================================================
function default_settings() {
  # OS Selection - ALWAYS ask
  select_os
  select_cloud_init
  select_portainer

  # Set defaults
  VMID=$(get_valid_nextid)
  FORMAT=""
  MACHINE=" -machine q35"
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
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}Q35 (Modern)${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above settings${CL}"
}

function advanced_settings() {
  # OS Selection - ALWAYS ask first
  select_os
  select_cloud_init
  select_portainer

  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)

  # VM ID
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID=$(get_valid_nextid)
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit_script
    fi
  done

  # Machine Type
  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "q35" "Q35 (Modern, PCIe)" ON \
    "i440fx" "i440fx (Legacy, PCI)" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}Q35 (Modern)${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx (Legacy)${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit_script
  fi

  # Disk Size
  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 10 or 10G).${CL}"
      exit_script
    fi
  else
    exit_script
  fi

  # Disk Cache
  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ $DISK_CACHE = "1" ]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit_script
  fi

  # Hostname
  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 docker --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="docker"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
    fi
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
  else
    exit_script
  fi

  # CPU Model
  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "1" "Host (Recommended)" ON \
    "0" "KVM64" OFF \
    3>&1 1>&2 2>&3); then
    if [ $CPU_TYPE1 = "1" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit_script
  fi

  # CPU Cores
  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $CORE_COUNT ]; then
      CORE_COUNT="2"
    fi
    echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
  else
    exit_script
  fi

  # RAM Size
  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 4096 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $RAM_SIZE ]; then
      RAM_SIZE="4096"
    fi
    echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
  else
    exit_script
  fi

  # Bridge
  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then
      BRG="vmbr0"
    fi
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
  else
    exit_script
  fi

  # MAC Address
  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      MAC="$GEN_MAC"
    else
      MAC="$MAC1"
    fi
    echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
  else
    exit_script
  fi

  # VLAN
  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan (leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VLAN1 ]; then
      VLAN1="Default"
      VLAN=""
    else
      VLAN=",tag=$VLAN1"
    fi
    echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
  else
    exit_script
  fi

  # MTU
  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MTU1 ]; then
      MTU1="Default"
      MTU=""
    else
      MTU=",mtu=$MTU1"
    fi
    echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
  else
    exit_script
  fi

  # Start VM
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  # Confirm
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Docker VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

# ==============================================================================
# DOCKER INSTALLATION SCRIPTS
# ==============================================================================
function create_docker_install_script() {
  local file="$1"
  local with_portainer="$2"

  local portainer_section=""
  if [ "$with_portainer" = "yes" ]; then
    portainer_section='
# Install Portainer
/root/portainer-install.sh'
  else
    portainer_section='
# Portainer not requested - skip installation'
  fi

  virt-customize -q -a "${file}" --run-command "cat > /root/install-docker.sh << 'INSTALLEOF'
#!/bin/bash
# Log output to file
exec > /var/log/install-docker.log 2>&1
echo \"[\$(date)] Starting Docker installation on first boot\"

# Check if Docker is already installed
if command -v docker >/dev/null 2>&1; then
  echo \"[\$(date)] Docker already installed, checking if running\"
  systemctl start docker 2>/dev/null || true
  if docker info >/dev/null 2>&1; then
    echo \"[\$(date)] Docker is already working, exiting\"
    exit 0
  fi
fi

# Wait for network to be fully available
for i in {1..30}; do
  if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo \"[\$(date)] Network is available\"
    break
  fi
  echo \"[\$(date)] Waiting for network... attempt \$i/30\"
  sleep 2
done

# Configure DNS
echo \"[\$(date)] Configuring DNS\"
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/dns.conf << DNSEOF
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=8.8.4.4 1.0.0.1
DNSEOF
systemctl restart systemd-resolved 2>/dev/null || true

# Update package lists
echo \"[\$(date)] Updating package lists\"
apt-get update

# Install base packages if not already installed
echo \"[\$(date)] Installing base packages\"
apt-get install -y qemu-guest-agent curl ca-certificates 2>/dev/null || true

# Install Docker
echo \"[\$(date)] Installing Docker\"
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
for i in {1..10}; do
  if docker info >/dev/null 2>&1; then
    echo \"[\$(date)] Docker is ready\"
    break
  fi
  sleep 1
done
${portainer_section}

# Create completion flag
echo \"[\$(date)] Docker installation completed successfully\"
touch /root/.docker-installed
INSTALLEOF" >/dev/null

  virt-customize -q -a "${file}" --run-command "chmod +x /root/install-docker.sh" >/dev/null
}

function create_portainer_script() {
  local file="$1"

  virt-customize -q -a "${file}" --run-command 'cat > /root/portainer-install.sh << '"'"'PORTAINEREOF'"'"'
#!/bin/bash
exec >> /var/log/install-docker.log 2>&1
echo "[$(date)] Installing Portainer"
docker volume create portainer_data 2>/dev/null || true
docker run -d \
  -p 9000:9000 \
  -p 9443:9443 \
  --name=portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
echo "[$(date)] Portainer installed"
PORTAINEREOF' >/dev/null

  virt-customize -q -a "${file}" --run-command 'chmod +x /root/portainer-install.sh' >/dev/null
}

function create_docker_service() {
  local file="$1"

  virt-customize -q -a "${file}" --run-command 'cat > /etc/systemd/system/install-docker.service << "SERVICEEOF"
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
SERVICEEOF
' >/dev/null

  virt-customize -q -a "${file}" --run-command "systemctl enable install-docker.service" >/dev/null
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
header_info
echo -e "\n Loading..."

check_root
arch_check
pve_check

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker VM" --yesno "This will create a New Docker VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

start_script
post_to_api_vm

# ==============================================================================
# STORAGE SELECTION
# ==============================================================================
echo ""
msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')

VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

# ==============================================================================
# PREREQUISITES
# ==============================================================================
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools lsb-release -y >/dev/null
  apt-get -qq install dhcpcd-base -y >/dev/null 2>&1 || true
  msg_ok "Installed libguestfs-tools"
fi

# ==============================================================================
# IMAGE DOWNLOAD
# ==============================================================================
msg_info "Retrieving the URL for the ${OS_DISPLAY} Qcow2 Disk Image"
URL=$(get_image_url)
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# ==============================================================================
# STORAGE TYPE DETECTION
# ==============================================================================
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

# ==============================================================================
# IMAGE CUSTOMIZATION
# ==============================================================================
echo -e "${INFO}${BOLD}${GN}Preparing ${OS_DISPLAY} Qcow2 Disk Image${CL}"

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

# Create Docker installation scripts
create_docker_install_script "${FILE}" "$INSTALL_PORTAINER"

if [ "$INSTALL_PORTAINER" = "yes" ]; then
  create_portainer_script "${FILE}"
fi

create_docker_service "${FILE}"

# Try to install packages during image customization
DOCKER_INSTALLED_ON_FIRST_BOOT="yes"

msg_info "Installing base packages (qemu-guest-agent, curl, ca-certificates)"
if virt-customize -a "${FILE}" --install qemu-guest-agent,curl,ca-certificates >/dev/null 2>&1; then
  msg_ok "Installed base packages"

  msg_info "Installing Docker via get.docker.com"
  if virt-customize -q -a "${FILE}" --run-command "curl -fsSL https://get.docker.com | sh" >/dev/null 2>&1 &&
    virt-customize -q -a "${FILE}" --run-command "systemctl enable docker" >/dev/null 2>&1; then
    msg_ok "Installed Docker"

    # Optimize Docker daemon configuration
    virt-customize -q -a "${FILE}" --run-command "mkdir -p /etc/docker" >/dev/null 2>&1
    virt-customize -q -a "${FILE}" --run-command "cat > /etc/docker/daemon.json << 'DOCKEREOF'
{
  \"storage-driver\": \"overlay2\",
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"10m\",
    \"max-file\": \"3\"
  }
}
DOCKEREOF" >/dev/null 2>&1

    virt-customize -q -a "${FILE}" --run-command "touch /root/.docker-installed" >/dev/null 2>&1
    DOCKER_INSTALLED_ON_FIRST_BOOT="no"
  else
    msg_ok "Docker will be installed on first boot"
  fi
else
  msg_ok "Packages will be installed on first boot"
fi

# Set hostname and clean machine-id
virt-customize -q -a "${FILE}" --hostname "${HN}" >/dev/null 2>&1
virt-customize -q -a "${FILE}" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1
virt-customize -q -a "${FILE}" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1

# Configure SSH for Cloud-Init
if [ "$USE_CLOUD_INIT" = "yes" ]; then
  virt-customize -q -a "${FILE}" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
  virt-customize -q -a "${FILE}" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
fi

# Expand disk
msg_info "Expanding root partition to use full disk space"
qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE} >/dev/null 2>&1
virt-resize --quiet --expand /dev/sda1 ${FILE} expanded.qcow2 >/dev/null 2>&1
mv expanded.qcow2 ${FILE} >/dev/null 2>&1
msg_ok "Expanded image to full size"

# ==============================================================================
# VM CREATION
# ==============================================================================
msg_info "Creating Docker VM"

qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
qm set $VMID --agent enabled=1 >/dev/null

# Proxmox 9: Enable I/O Thread
if [ "${PVE_MAJOR:-8}" = "9" ]; then
  qm set $VMID -iothread 1 >/dev/null 2>&1 || true
fi

msg_ok "Created Docker VM ${CL}${BL}(${HN})${CL}"

# Cloud-Init configuration
if [ "$USE_CLOUD_INIT" = "yes" ]; then
  msg_info "Configuring Cloud-Init"
  setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" >/dev/null 2>&1
  msg_ok "Cloud-Init configured"
fi

# Set description
set_description

# Start VM
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Docker VM"
  qm start $VMID >/dev/null 2>&1
  msg_ok "Started Docker VM"
fi

# ==============================================================================
# FINAL OUTPUT
# ==============================================================================
VM_IP=""
if [ "$START_VM" == "yes" ]; then
  # Disable error exit for optional IP retrieval
  set +e
  for i in {1..5}; do
    VM_IP=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null |
      jq -r '.[] | select(.name != "lo") | ."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address"' 2>/dev/null |
      grep -v "^127\." | head -1) || true
    [ -n "$VM_IP" ] && break
    sleep 2
  done
  set -e
fi

echo -e "\n${INFO}${BOLD}${GN}VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}OS: ${BGN}${OS_DISPLAY}${CL}"

[ -n "$VM_IP" ] && echo -e "${TAB}${DGN}IP Address: ${BGN}${VM_IP}${CL}"

if [ "$DOCKER_INSTALLED_ON_FIRST_BOOT" = "yes" ]; then
  echo -e "${TAB}${DGN}Docker: ${BGN}Will be installed on first boot${CL}"
  echo -e "${TAB}${YW}⚠️  Wait 2-3 minutes after boot for installation to complete${CL}"
  echo -e "${TAB}${YW}⚠️  Check progress: ${BL}cat /var/log/install-docker.log${CL}"
else
  echo -e "${TAB}${DGN}Docker: ${BGN}Latest (via get.docker.com)${CL}"
fi

if [ "$INSTALL_PORTAINER" = "yes" ]; then
  if [ -n "$VM_IP" ]; then
    echo -e "${TAB}${DGN}Portainer: ${BGN}https://${VM_IP}:9443${CL}"
  else
    echo -e "${TAB}${DGN}Portainer: ${BGN}https://<VM-IP>:9443${CL}"
    echo -e "${TAB}${YW}⚠️  Get IP: ${BL}qm guest cmd ${VMID} network-get-interfaces${CL}"
  fi
fi

if [ "$USE_CLOUD_INIT" = "yes" ]; then
  display_cloud_init_info "$VMID" "$HN" 2>/dev/null || true
fi

post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"

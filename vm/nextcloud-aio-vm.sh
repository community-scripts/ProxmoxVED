#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/nextcloud/all-in-one

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="Nextcloud AIO"
APP_TYPE="vm"
NSAPP="nextcloud-aio-vm"
var_os="debian"
var_version="13"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
USE_CLOUD_INIT="no"
OS_TYPE="debian"
OS_VERSION="13"
OS_CODENAME="trixie"
OS_DISPLAY="Debian 13 (Trixie)"
THIN="discard=on,ssd=1,"
AIO_IMAGE="ghcr.io/nextcloud-releases/all-in-one:latest"
DOCKER_PREINSTALLED="no"
DOCKER_INSTALL_MARKER=""
AIO_SETUP_MARKER=""

header_info
echo -e "\n Loading..."

set -Eeo pipefail
shopt -s inherit_errexit
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

vm_preflight
vm_require_tools virt-customize jq

function select_os() {
  if [[ -n "${1:-}" ]]; then
    OS_CHOICE="$1"
  elif [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
    OS_CHOICE="${VM_OS_VERSION:-debian13}"
  elif vm_dialog radiolist "SELECT OS" \
    "Choose Operating System for the Nextcloud AIO VM" 15 68 4 \
    "debian13" "Debian 13 (Trixie) - Latest" ON \
    "debian12" "Debian 12 (Bookworm) - Stable" OFF \
    "ubuntu2604" "Ubuntu 26.04 LTS (Resolute)" OFF \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF; then
    OS_CHOICE="$VM_DIALOG_RESULT"
  else
    exit_script
  fi

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
  ubuntu2604)
    OS_TYPE="ubuntu"
    OS_VERSION="26.04"
    OS_CODENAME="resolute"
    OS_DISPLAY="Ubuntu 26.04 LTS"
    ;;
  ubuntu2404)
    OS_TYPE="ubuntu"
    OS_VERSION="24.04"
    OS_CODENAME="noble"
    OS_DISPLAY="Ubuntu 24.04 LTS"
    ;;
  *)
    msg_error "Unsupported OS '${OS_CHOICE}' (expected debian13, debian12, ubuntu2604 or ubuntu2404)"
    exit 1
    ;;
  esac
  var_os="$OS_TYPE"
  var_version="$OS_VERSION"
  echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}${OS_DISPLAY}${CL}"
}

function select_cloud_init() {
  VM_CLOUD_INIT="${VM_CLOUD_INIT:-yes}"
  CLOUDINIT_REQUIRED=0
  if [[ "$OS_TYPE" == "ubuntu" ]]; then
    CLOUDINIT_REQUIRED=1
  fi
  vm_prompt_cloud_init "$OS_TYPE"
}

function get_image_url() {
  local arch
  arch=$(vm_arch_resolve amd64 arm64)
  case $OS_TYPE in
  debian)
    if [[ "$USE_CLOUD_INIT" == "yes" ]]; then
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

function default_settings() {
  select_os "${VM_OS_VERSION:-}"
  vm_apply_machine_type "q35"
  VMID=$(get_valid_nextid)
  DISK_SIZE="32G"
  DISK_CACHE=""
  HN="nextcloud-aio"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="2"
  RAM_SIZE="4096"
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
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "32G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "nextcloud-aio"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_keyboard
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Nextcloud AIO VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Nextcloud AIO VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 2 CPU Cores\n• 4 GB RAM\n• 32 GB Disk\n• Cloud-Init enabled" 14 58
select_cloud_init
post_to_api_vm

vm_select_storage "$HN"
vm_define_disk_references 2

msg_info "Retrieving the URL for the ${OS_DISPLAY} Disk Image"
URL=$(get_image_url)
CACHE_FILE="$(vm_image_cache_path "$URL")"
msg_ok "${CL}${BL}${URL}${CL}"

MIN_IMAGE_BYTES=$((100 * 1024 * 1024))
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes "$MIN_IMAGE_BYTES" || exit 115

WORK_FILE="$TEMP_DIR/nextcloud-aio.qcow2"
cp "$CACHE_FILE" "$WORK_FILE"

if [[ "${USE_CLOUD_INIT:-no}" != "yes" ]]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$WORK_FILE" "$DISK_SIZE" || true
fi

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

msg_info "Installing base packages"
if vm_customize "Nextcloud AIO base packages" "$WORK_FILE" --install qemu-guest-agent,curl,ca-certificates,jq; then
  msg_ok "Installed base packages"

  msg_info "Installing Docker"
  if vm_customize "Docker" "$WORK_FILE" \
    --run-command 'bash -o pipefail -c "curl -fsSL https://get.docker.com | sh"' \
    --run-command 'systemctl enable docker'; then
    DOCKER_PREINSTALLED="yes"
    msg_ok "Installed Docker"

    DOCKER_DAEMON_TMP="$TEMP_DIR/docker-daemon.json"
    cat >"$DOCKER_DAEMON_TMP" <<'JSON'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
JSON
    vm_customize "Docker daemon" "$WORK_FILE" \
      --mkdir /etc/docker \
      --upload "${DOCKER_DAEMON_TMP}:/etc/docker/daemon.json" || msg_warn "Docker daemon tuning failed; continuing with Docker defaults"
  else
    msg_warn "Docker pre-install failed; installation is pending on first boot."
  fi
else
  msg_warn "Package pre-install failed; Docker installation is pending on first boot."
fi

AIO_SETUP_TMP="$TEMP_DIR/nextcloud-aio.sh"
cat >"$AIO_SETUP_TMP" <<SETUPEOF
#!/usr/bin/env bash
set -Eeuo pipefail
exec >> /var/log/nextcloud-aio.log 2>&1

echo "[\$(date)] Starting the Nextcloud AIO master container"

for _ in {1..60}; do
  docker info >/dev/null 2>&1 && break
  sleep 5
done
docker info >/dev/null 2>&1 || {
  echo "[\$(date)] ERROR: Docker not ready after 5 min"
  exit 1
}

if docker inspect nextcloud-aio-mastercontainer >/dev/null 2>&1; then
  docker start nextcloud-aio-mastercontainer >/dev/null 2>&1 || true
  echo "[\$(date)] Master container already exists"
  exit 0
fi

# The command from https://github.com/nextcloud/all-in-one, detached for a unit.
docker run --detach --init \\
  --name nextcloud-aio-mastercontainer \\
  --restart always \\
  --publish 80:80 \\
  --publish 8080:8080 \\
  --publish 8443:8443 \\
  --volume nextcloud_aio_mastercontainer:/var/lib/docker/volumes/ \\
  --volume /var/run/docker.sock:/var/run/docker.sock:ro \\
  ${AIO_IMAGE}
echo "[\$(date)] Nextcloud AIO master container started"
SETUPEOF

vm_prepare_cloud_image "$WORK_FILE" "$HN" || true

if [[ "$DOCKER_PREINSTALLED" == "no" ]]; then
  DOCKER_INSTALL_TMP="$TEMP_DIR/install-docker.sh"
  cat >"$DOCKER_INSTALL_TMP" <<'DOCKEREOF'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
exec > /var/log/install-docker.log 2>&1

echo "[$(date)] Starting Docker installation"
for _ in {1..30}; do
  ping -c 1 8.8.8.8 >/dev/null 2>&1 && break
  sleep 2
done

apt-get update
apt-get install -y qemu-guest-agent curl ca-certificates jq
bash -o pipefail -c "curl -fsSL https://get.docker.com | sh"
systemctl enable docker
install -d /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
JSON
systemctl start docker
echo "[$(date)] Docker installation completed"
DOCKEREOF

  vm_firstboot_unit "$WORK_FILE" install-docker "$DOCKER_INSTALL_TMP" \
    --description "Install Docker on first boot" \
    --cloud-init "$USE_CLOUD_INIT" || exit 1
  DOCKER_INSTALL_MARKER="$VM_FIRSTBOOT_MARKER"
fi

AIO_AFTER=(--after docker.service)
if [[ "$DOCKER_PREINSTALLED" == "no" ]]; then
  AIO_AFTER+=(--after install-docker.service)
fi
vm_firstboot_unit "$WORK_FILE" nextcloud-aio "$AIO_SETUP_TMP" \
  --description "Nextcloud AIO master container" \
  "${AIO_AFTER[@]}" \
  --cloud-init "$USE_CLOUD_INIT" || exit 1
AIO_SETUP_MARKER="$VM_FIRSTBOOT_MARKER"

vm_claim_vmid
msg_info "Creating Nextcloud AIO VM shell"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
vm_mark_created
msg_ok "Created VM shell"

vm_alloc_efi_disk "$DISK0"
vm_import_disk "$VMID" "$WORK_FILE" "$STORAGE"

DISK_OPTIONS="${DISK_CACHE}${THIN}"
DISK_OPTIONS="${DISK_OPTIONS%,}"
ROOT_DISK="$VM_IMPORTED_DISK"
[[ -n "$DISK_OPTIONS" ]] && ROOT_DISK="${ROOT_DISK},${DISK_OPTIONS}"

msg_info "Attaching EFI and root disk"
qm set "$VMID" \
  --efidisk0 "${DISK0_REF}${FORMAT}" \
  --scsi0 "$ROOT_DISK" \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
msg_ok "Attached EFI and root disk"

vm_resize_disk "scsi0" "$DISK_SIZE"
set_description

vm_provision "$VMID"
if [[ "$USE_CLOUD_INIT" == "yes" && -n "${CLOUDINIT_SSH_KEYS:-}" ]]; then
  $STD qm set "$VMID" --sshkeys "$CLOUDINIT_SSH_KEYS"
fi

vm_start_vm "Nextcloud AIO VM"
vm_wait_for_ip 180 || true

if [[ "$USE_CLOUD_INIT" == "yes" ]]; then
  display_cloud_init_info "$VMID" "$HN"
else
  msg_warn "Debian nocloud console login: root, no password. Set one before exposing the VM."
fi

AIO_READY="no"
if [[ -n "${VM_IP:-}" ]]; then
  msg_info "Waiting for the AIO interface on https://${VM_IP}:8080"
  if vm_wait_http "https://${VM_IP}:8080" 300 --insecure; then
    AIO_READY="yes"
    msg_ok "AIO interface answers on https://${VM_IP}:8080"
  else
    msg_warn "The AIO interface is not up yet; the first boot may still be pulling the image"
  fi
fi

DOCKER_STATUS="Pre-installed"
if [[ "$DOCKER_PREINSTALLED" == "no" ]]; then
  DOCKER_STATUS="First-boot unit install-docker.service${DOCKER_INSTALL_MARKER:+ (${DOCKER_INSTALL_MARKER})}"
fi

vm_print_summary \
  "OS=${OS_DISPLAY}" \
  "Docker=${DOCKER_STATUS}" \
  "AIO interface=https://${VM_IP:-<VM-IP>}:8080" \
  "AIO unit=nextcloud-aio.service" \
  "Setup marker=${AIO_SETUP_MARKER}"
vm_next_steps \
  "Open https://${VM_IP:-<VM-IP>}:8080 (self-signed certificate) and log in with the AIO password." \
  "Print that password in the VM: sudo docker exec nextcloud-aio-mastercontainer grep password /mnt/docker-aio-config/data/configuration.json" \
  "AIO needs a domain with a valid certificate; a bare IP is not supported. Point the domain at this VM and open 80/tcp and 443/tcp, or see https://github.com/nextcloud/all-in-one/blob/main/local-instance.md for a LAN-only setup." \
  "Follow the first boot with: tail -f /var/log/nextcloud-aio.log (Docker install: /var/log/install-docker.log)"

FINISH_MESSAGE="VM created. Nextcloud AIO starts in the VM on first boot."
[[ "$AIO_READY" == "yes" ]] && FINISH_MESSAGE="VM created. Nextcloud AIO is waiting for you at https://${VM_IP}:8080."
vm_finish "$FINISH_MESSAGE"

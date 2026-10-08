#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/owncloud/ocis

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="ownCloud Infinite Scale"
APP_TYPE="vm"
NSAPP="owncloud-ocis-vm"
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
OCIS_IMAGE="owncloud/ocis:latest"
OCIS_PORT="9200"
OCIS_ADMIN_PASSWORD="${VM_OCIS_ADMIN_PASSWORD:-$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | cut -c1-16)}"
DOCKER_PREINSTALLED="no"
DOCKER_INSTALL_MARKER=""
OCIS_SETUP_MARKER=""

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
    "Choose Operating System for the ownCloud Infinite Scale VM" 15 68 4 \
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
  HN="owncloud-ocis"
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
  vm_prompt_hostname "owncloud-ocis"
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

  if vm_confirm_advanced_settings "Ready to create an ownCloud Infinite Scale VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating an ownCloud Infinite Scale VM using the above advanced settings${CL}"
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

WORK_FILE="$TEMP_DIR/owncloud-ocis.qcow2"
cp "$CACHE_FILE" "$WORK_FILE"

if [[ "${USE_CLOUD_INIT:-no}" != "yes" ]]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$WORK_FILE" "$DISK_SIZE" || true
fi

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

msg_info "Installing base packages"
if vm_customize "ownCloud base packages" "$WORK_FILE" --install qemu-guest-agent,curl,ca-certificates,jq; then
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

# The unit script is world-readable, so the password travels in a root-only env file.
OCIS_ENV_TMP="$TEMP_DIR/ocis.env"
printf 'IDM_ADMIN_PASSWORD=%q\n' "$OCIS_ADMIN_PASSWORD" >"$OCIS_ENV_TMP"
vm_customize "ownCloud admin password" "$WORK_FILE" \
  --upload "${OCIS_ENV_TMP}:/root/ocis.env" \
  --chmod "0600:/root/ocis.env" || exit 1

OCIS_SETUP_TMP="$TEMP_DIR/owncloud-ocis.sh"
cat >"$OCIS_SETUP_TMP" <<SETUPEOF
#!/usr/bin/env bash
set -Eeuo pipefail
exec >> /var/log/owncloud-ocis.log 2>&1

echo "[\$(date)] Starting ownCloud Infinite Scale"

for _ in {1..60}; do
  docker info >/dev/null 2>&1 && break
  sleep 5
done
docker info >/dev/null 2>&1 || {
  echo "[\$(date)] ERROR: Docker not ready after 5 min"
  exit 1
}

if docker inspect ocis >/dev/null 2>&1; then
  docker start ocis >/dev/null 2>&1 || true
  echo "[\$(date)] ocis container already exists"
  exit 0
fi

# Every link oCIS hands out carries this address, so it has to be the VM's own.
OCIS_IP="\$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \\([0-9.]*\\).*/\\1/p' | head -n1)"
[ -n "\$OCIS_IP" ] || OCIS_IP="\$(hostname -I | awk '{print \$1}')"

set -a
. /root/ocis.env
set +a

if ! docker volume inspect ocis-config >/dev/null 2>&1; then
  docker run --rm \\
    -v ocis-config:/etc/ocis \\
    -v ocis-data:/var/lib/ocis \\
    -e IDM_ADMIN_PASSWORD="\$IDM_ADMIN_PASSWORD" \\
    ${OCIS_IMAGE} init --insecure yes
fi

docker run --detach \\
  --name ocis \\
  --restart always \\
  --publish ${OCIS_PORT}:9200 \\
  -v ocis-config:/etc/ocis \\
  -v ocis-data:/var/lib/ocis \\
  -e OCIS_INSECURE=true \\
  -e PROXY_HTTP_ADDR=0.0.0.0:9200 \\
  -e OCIS_URL="https://\${OCIS_IP}:${OCIS_PORT}" \\
  ${OCIS_IMAGE}
echo "[\$(date)] ownCloud Infinite Scale started at https://\${OCIS_IP}:${OCIS_PORT}"
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

OCIS_AFTER=(--after docker.service)
if [[ "$DOCKER_PREINSTALLED" == "no" ]]; then
  OCIS_AFTER+=(--after install-docker.service)
fi
vm_firstboot_unit "$WORK_FILE" owncloud-ocis "$OCIS_SETUP_TMP" \
  --description "ownCloud Infinite Scale container" \
  "${OCIS_AFTER[@]}" \
  --cloud-init "$USE_CLOUD_INIT" || exit 1
OCIS_SETUP_MARKER="$VM_FIRSTBOOT_MARKER"

vm_claim_vmid
msg_info "Creating ownCloud Infinite Scale VM shell"
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

OCIS_CRED_FILE="/tmp/${HN}-${VMID}-ocis-credentials.txt"
printf 'ownCloud Infinite Scale admin\nuser: admin\npassword: %s\n' "$OCIS_ADMIN_PASSWORD" >"$OCIS_CRED_FILE"
chmod 600 "$OCIS_CRED_FILE"

vm_start_vm "ownCloud Infinite Scale VM"
vm_wait_for_ip 180 || true

if [[ "$USE_CLOUD_INIT" == "yes" ]]; then
  display_cloud_init_info "$VMID" "$HN"
else
  msg_warn "Debian nocloud console login: root, no password. Set one before exposing the VM."
fi

OCIS_READY="no"
if [[ -n "${VM_IP:-}" ]]; then
  msg_info "Waiting for ownCloud on https://${VM_IP}:${OCIS_PORT}"
  if vm_wait_http "https://${VM_IP}:${OCIS_PORT}" 300 --insecure; then
    OCIS_READY="yes"
    msg_ok "ownCloud answers on https://${VM_IP}:${OCIS_PORT}"
  else
    msg_warn "ownCloud is not up yet; the first boot may still be pulling the image"
  fi
fi

DOCKER_STATUS="Pre-installed"
if [[ "$DOCKER_PREINSTALLED" == "no" ]]; then
  DOCKER_STATUS="First-boot unit install-docker.service${DOCKER_INSTALL_MARKER:+ (${DOCKER_INSTALL_MARKER})}"
fi

vm_print_summary \
  "OS=${OS_DISPLAY}" \
  "Docker=${DOCKER_STATUS}" \
  "Web UI=https://${VM_IP:-<VM-IP>}:${OCIS_PORT}" \
  "Admin user=admin" \
  "Admin password=${OCIS_ADMIN_PASSWORD}" \
  "Credentials file=${OCIS_CRED_FILE}" \
  "oCIS unit=owncloud-ocis.service" \
  "Setup marker=${OCIS_SETUP_MARKER}"
vm_next_steps \
  "Open https://${VM_IP:-<VM-IP>}:${OCIS_PORT} (self-signed certificate) and log in as admin; change the password in the account settings." \
  "Delete the credentials file after noting the password: ${OCIS_CRED_FILE}" \
  "The links oCIS hands out use the VM's current IP; reserve the DHCP lease, or put a reverse proxy with a domain in front and set OCIS_URL accordingly." \
  "Follow the first boot with: tail -f /var/log/owncloud-ocis.log (Docker install: /var/log/install-docker.log)"

FINISH_MESSAGE="VM created. ownCloud Infinite Scale starts in the VM on first boot."
[[ "$OCIS_READY" == "yes" ]] && FINISH_MESSAGE="VM created. ownCloud Infinite Scale is waiting for you at https://${VM_IP}:${OCIS_PORT}."
vm_finish "$FINISH_MESSAGE"

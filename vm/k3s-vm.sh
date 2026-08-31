#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source /dev/stdin <<<$(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/vm/cloud-init.func") 2>/dev/null || true
load_functions

function header_info {
  clear
  cat <<"EOF"
K3s
EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
APP="K3s"
APP_TYPE="vm"
NSAPP="k3s-vm"
var_os="debian"
var_version="13"
INSTALL_ARGOCD_BOOTSTRAP="${INSTALL_ARGOCD_BOOTSTRAP:-1}"
DISK_SIZE="10G"
USE_CLOUD_INIT="no"
OS_TYPE=""
OS_VERSION=""
OS_CODENAME=""
OS_DISPLAY=""

THIN="discard=on,ssd=1,"
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

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:-}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        :
      else
        clear
        exit
      fi
    fi
  fi
}

function select_os() {
  if OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SELECT OS" --radiolist \
    "Choose Operating System for K3s VM" 14 68 4 \
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
  if [ "$OS_TYPE" = "ubuntu" ]; then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}yes (Ubuntu requires Cloud-Init)${CL}"
    return
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?\n\nCloud-Init allows automatic configuration of:\n- User accounts and passwords\n- SSH keys\n- Network settings (DHCP/Static)\n- DNS configuration\n\nYou can also configure these settings later in Proxmox UI." 16 68); then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  else
    USE_CLOUD_INIT="no"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
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

get_valid_nextid
cleanup_vmid
cleanup
post_update_to_api "done" "none"
[[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
check_root
pve_check
arch_check
ssh_check

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "K3s VM" --yesno "This will create a New K3s VM. Proceed?" 10 58; then
  :
else
  header_info && exit_script
fi

function default_settings() {
  vm_apply_machine_type "q35"
  select_os
  select_cloud_init

  VMID=$(get_valid_nextid)
  DISK_SIZE="10G"
  DISK_CACHE=""
  HN="k3s"
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
  select_cloud_init
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "10G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "k3s"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a K3s VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a K3s VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}


vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

vm_select_storage "$HN"
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the ${OS_DISPLAY} image"
URL=$(get_image_url)
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL "$URL" -O
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

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

msg_info "Creating a ${OS_DISPLAY} VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null

if [ -n "$DISK_SIZE" ]; then
  msg_info "Resizing disk to $DISK_SIZE GB"
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
else
  msg_info "Using default disk size of $DEFAULT_DISK_SIZE GB"
  qm resize $VMID scsi0 ${DEFAULT_DISK_SIZE} >/dev/null
fi

case "$(dpkg --print-architecture)" in
amd64)
  K9S_ARCH="amd64"
  ;;
arm64)
  K9S_ARCH="arm64"
  ;;
*)
  K9S_ARCH="amd64"
  ;;
esac
K9S_URL="https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${K9S_ARCH}.tar.gz"
msg_info "Add in Image K3s & Helm"
virt-customize -q -a "${FILE}" \
  --hostname "${HN}" \
  --install curl,wget,tar,ca-certificates,gnupg,iptables \
  --run-command 'curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644' \
  --run-command 'ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl' \
  --run-command 'wget -q https://get.helm.sh/helm-v3.18.1-linux-amd64.tar.gz -O /tmp/helm.tar.gz' \
  --run-command 'tar -xzf /tmp/helm.tar.gz -C /tmp' \
  --run-command 'mv /tmp/linux-amd64/helm /usr/local/bin/helm' \
  --run-command 'chmod +x /usr/local/bin/helm' \
  --run-command 'echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /root/.bashrc' >/dev/null

msg_ok "Added in Image K3s & Helm"

msg_info "Adding k9s (${K9S_ARCH})"
if curl -fsSL "$K9S_URL" -o /tmp/k9s.tar.gz; then
  if virt-customize -q -a "${FILE}" \
    --upload /tmp/k9s.tar.gz:/tmp/k9s.tar.gz \
    --run-command 'tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s' \
    --run-command 'chmod +x /usr/local/bin/k9s' \
    --run-command 'rm -f /tmp/k9s.tar.gz' >/dev/null; then
    msg_ok "Added k9s to image"
  else
    msg_warn "Could not add k9s to image. VM creation continues without k9s."
  fi
else
  msg_warn "Could not download k9s archive. VM creation continues without k9s."
fi
rm -f /tmp/k9s.tar.gz

if [[ "$INSTALL_ARGOCD_BOOTSTRAP" == "1" ]]; then
  msg_info "Add in Image ArgoCD Bootstrap"
  virt-customize -q -a "${FILE}" \
    --run-command 'mkdir -p /usr/local/sbin /etc/systemd/system /var/lib' \
    --run-command 'cat <<"EOF" >/usr/local/sbin/bootstrap-argocd.sh
#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

for _ in $(seq 1 120); do
  if kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready "; then
    break
  fi
  sleep 2
done

if ! kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready "; then
  echo "K3s is not ready yet"
  exit 1
fi

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=10m

touch /var/lib/argocd-bootstrap.done
EOF' \
    --run-command 'chmod +x /usr/local/sbin/bootstrap-argocd.sh' \
    --run-command 'cat <<"EOF" >/etc/systemd/system/argocd-bootstrap.service
[Unit]
Description=ArgoCD Bootstrap
After=network-online.target k3s.service
Wants=network-online.target
ConditionPathExists=!/var/lib/argocd-bootstrap.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bootstrap-argocd.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF' \
    --run-command 'systemctl enable argocd-bootstrap.service' >/dev/null

  msg_ok "Added in Image ArgoCD Bootstrap"
else
  msg_info "Skipping ArgoCD Bootstrap (INSTALL_ARGOCD_BOOTSTRAP=$INSTALL_ARGOCD_BOOTSTRAP)"
fi

msg_ok "Created a K3s VM ${CL}${BL}(${HN})"

if [ "$USE_CLOUD_INIT" = "yes" ] && command -v setup_cloud_init >/dev/null 2>&1; then
  msg_info "Configuring Cloud-Init"
  setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes"
  msg_ok "Configured Cloud-Init"
fi

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting K3s VM"
  qm start $VMID
  msg_ok "Started K3s VM"
fi

msg_ok "Completed successfully!\n"
msg_custom "More Info at https://github.com/community-scripts/ProxmoxVED/discussions/836"

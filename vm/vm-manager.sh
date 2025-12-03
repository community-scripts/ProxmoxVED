#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Universal VM Template Manager - Create, Deploy, List Templates with optional Cloud-Init

set -euo pipefail

# ============================================================================
# OS IMAGE CATALOG
# ============================================================================

declare -A OS_IMAGES=(
  # Debian - Cloud-Init enabled
  ["debian-13"]="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  ["debian-12"]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"

  # Debian - NoCloud variants (without cloud-init pre-installed)
  ["debian-13-nocloud"]="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2"
  ["debian-12-nocloud"]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2"

  # Ubuntu - Cloud-Init enabled
  ["ubuntu-24.04"]="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  ["ubuntu-22.04"]="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
  ["ubuntu-20.04"]="https://cloud-images.ubuntu.com/releases/20.04/release/ubuntu-20.04-server-cloudimg-amd64.img"

  # AlmaLinux
  ["alma-9"]="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
  ["alma-8"]="https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2"

  # Rocky Linux
  ["rocky-9"]="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  ["rocky-8"]="https://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"

  # Fedora
  ["fedora-41"]="https://download.fedoraproject.org/pub/fedora/linux/releases/41/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-41-1.4.x86_64.qcow2"
  ["fedora-40"]="https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-40-1.14.x86_64.qcow2"

  # Arch Linux
  ["arch"]="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"

  # CentOS Stream
  ["centos-9"]="https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"

  # Alpine Linux
  ["alpine-3.20"]="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/cloud/generic_alpine-3.20.0-x86_64-bios-cloudinit-r0.qcow2"
)

# ============================================================================
# CONFIGURATION
# ============================================================================

# Defaults
MODE=""
TEMPLATE_PREFIX="template"
TEMPLATE_ID_START=900
VMID=""
OS_KEY=""
HOSTNAME=""
CORES=2
MEMORY=2048
DISK_SIZE=30
STORAGE=""
BRIDGE="vmbr0"
START_VM="no"
MACHINE_TYPE="q35"

# Cloud-Init Options
ENABLE_CLOUDINIT="yes" # yes|no - Enable/disable cloud-init drive
CI_USER=""
CI_PASSWORD=""
CI_SSH_KEY=""
CI_FILE=""

# Post-Install Scripts
POST_INSTALL=""          # none|docker|podman|portainer
POST_INSTALL_TIMEOUT=300 # Timeout in seconds for post-install completion

# Interactive Mode
INTERACTIVE_MODE="no" # yes|no - Enable whiptail interactive mode

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

info() { echo -e "${BLUE}ℹ${NC} $*"; }
ok() { echo -e "${GREEN}✓${NC} $*"; }
error() {
  echo -e "${RED}✗${NC} $*" >&2
  exit 1
}
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

get_next_vmid() {
  local start_id=${1:-100}
  local id=$start_id
  while [ -f "/etc/pve/qemu-server/${id}.conf" ] || [ -f "/etc/pve/lxc/${id}.conf" ]; do
    id=$((id + 1))
  done
  echo "$id"
}

get_default_storage() {
  pvesm status -content images 2>/dev/null | awk 'NR==2 {print $1}' || echo "local-lvm"
}

list_storage_pools() {
  pvesm status -content images 2>/dev/null | awk 'NR>1 {print $1}'
}

get_snippet_storage() {
  pvesm status -content snippets 2>/dev/null | awk 'NR==2 {print $1}' || echo "local"
}

find_template_by_name() {
  local name=$1
  qm list 2>/dev/null | awk -v n="$name" '$2 == n {print $1; exit}'
}

is_template() {
  local vmid=$1
  qm config "$vmid" 2>/dev/null | grep -q "^template: 1"
}

cleanup_vm() {
  if [ -n "${VMID:-}" ] && qm status "$VMID" &>/dev/null; then
    warn "Cleanup: Removing VM $VMID"
    qm destroy "$VMID" &>/dev/null || true
  fi
}

# ============================================================================
# INTERACTIVE WHIPTAIL MENUS
# ============================================================================

interactive_main_menu() {
  local choice
  choice=$(whiptail --title "VM Manager" --menu "Choose action:" 20 70 10 \
    "1" "Create VM Template" \
    "2" "Deploy VM from Template" \
    "3" "List Templates" \
    "4" "List Available OS Images" \
    "5" "Exit" \
    3>&1 1>&2 2>&3)
  
  case $choice in
    1) interactive_create_template ;;
    2) interactive_deploy_vm ;;
    3) list_templates; read -p "Press Enter to continue..."; interactive_main_menu ;;
    4) list_os_options; read -p "Press Enter to continue..."; interactive_main_menu ;;
    5) exit 0 ;;
    *) exit 0 ;;
  esac
}

interactive_select_os() {
  local menu_items=()
  local i=1
  
  for key in $(echo "${!OS_IMAGES[@]}" | tr ' ' '\n' | sort); do
    menu_items+=("$key" "${OS_IMAGES[$key]}")
  done
  
  OS_KEY=$(whiptail --title "Select OS" --menu "Choose operating system:" 25 80 15 \
    "${menu_items[@]}" 3>&1 1>&2 2>&3)
  
  [ -z "$OS_KEY" ] && return 1
  return 0
}

interactive_create_template() {
  clear
  info "Creating VM Template - Interactive Mode"
  echo ""
  
  # Select OS
  interactive_select_os || { warn "No OS selected"; interactive_main_menu; return; }
  
  # VM ID
  local input_vmid
  input_vmid=$(whiptail --title "VM ID" --inputbox "Enter VM ID (leave empty for auto):" 10 60 "" 3>&1 1>&2 2>&3)
  [ -n "$input_vmid" ] && VMID="$input_vmid"
  
  # CPU Cores
  CORES=$(whiptail --title "CPU Cores" --inputbox "Number of CPU cores:" 10 60 "$CORES" 3>&1 1>&2 2>&3) || CORES=2
  
  # Memory
  MEMORY=$(whiptail --title "Memory" --inputbox "Memory in MB:" 10 60 "$MEMORY" 3>&1 1>&2 2>&3) || MEMORY=2048
  
  # Disk Size
  DISK_SIZE=$(whiptail --title "Disk Size" --inputbox "Disk size in GB:" 10 60 "$DISK_SIZE" 3>&1 1>&2 2>&3) || DISK_SIZE=30
  
  # Storage
  local storage_list=()
  while IFS= read -r stor; do
    storage_list+=("$stor" "")
  done < <(list_storage_pools)
  
  if [ ${#storage_list[@]} -gt 0 ]; then
    STORAGE=$(whiptail --title "Storage Pool" --menu "Select storage:" 20 70 10 \
      "${storage_list[@]}" 3>&1 1>&2 2>&3) || STORAGE=""
  fi
  
  # Cloud-Init
  if whiptail --title "Cloud-Init" --yesno "Enable Cloud-Init?" 10 60; then
    ENABLE_CLOUDINIT="yes"
    
    # Optional credentials
    if whiptail --title "Cloud-Init Credentials" --yesno "Configure Cloud-Init credentials now?" 10 60; then
      CI_USER=$(whiptail --title "Cloud-Init User" --inputbox "Username:" 10 60 "root" 3>&1 1>&2 2>&3) || CI_USER=""
      CI_PASSWORD=$(whiptail --title "Cloud-Init Password" --passwordbox "Password (optional):" 10 60 3>&1 1>&2 2>&3) || CI_PASSWORD=""
      CI_SSH_KEY=$(whiptail --title "SSH Public Key" --inputbox "SSH Public Key (optional):" 10 60 "" 3>&1 1>&2 2>&3) || CI_SSH_KEY=""
    fi
  else
    ENABLE_CLOUDINIT="no"
  fi
  
  # Confirm
  if whiptail --title "Confirm" --yesno "Create template with these settings?\n\nOS: $OS_KEY\nCores: $CORES\nMemory: ${MEMORY}MB\nDisk: ${DISK_SIZE}GB\nCloud-Init: $ENABLE_CLOUDINIT" 15 60; then
    clear
    create_template
    echo ""
    read -p "Press Enter to continue..."
  fi
  
  interactive_main_menu
}

interactive_deploy_vm() {
  clear
  info "Deploy VM from Template - Interactive Mode"
  echo ""
  
  # Select OS (template must exist)
  interactive_select_os || { warn "No OS selected"; interactive_main_menu; return; }
  
  # Check if template exists
  local template_name="${TEMPLATE_PREFIX}-${OS_KEY}"
  local template_id=$(find_template_by_name "$template_name")
  
  if [ -z "$template_id" ]; then
    whiptail --title "Error" --msgbox "Template '$template_name' not found!\n\nCreate it first." 10 60
    interactive_main_menu
    return
  fi
  
  # Hostname
  HOSTNAME=$(whiptail --title "Hostname" --inputbox "Enter hostname:" 10 60 "${OS_KEY}-vm" 3>&1 1>&2 2>&3)
  [ -z "$HOSTNAME" ] && HOSTNAME="${OS_KEY}-vm"
  
  # VM ID
  local input_vmid
  input_vmid=$(whiptail --title "VM ID" --inputbox "Enter VM ID (leave empty for auto):" 10 60 "" 3>&1 1>&2 2>&3)
  [ -n "$input_vmid" ] && VMID="$input_vmid"
  
  # Disk Size
  local template_size=$(qm config "$template_id" | grep "scsi0:" | grep -oP '\d+G' | head -1 | sed 's/G//')
  DISK_SIZE=$(whiptail --title "Disk Size" --inputbox "Disk size in GB:" 10 60 "${template_size:-30}" 3>&1 1>&2 2>&3) || DISK_SIZE=30
  
  # Post-Install
  local post_choice
  post_choice=$(whiptail --title "Post-Install" --menu "Install additional software?" 20 70 10 \
    "none" "No additional software" \
    "docker" "Install Docker CE" \
    "podman" "Install Podman" \
    "portainer" "Install Docker + Portainer" \
    3>&1 1>&2 2>&3)
  
  POST_INSTALL="${post_choice:-none}"
  
  # Start VM
  if whiptail --title "Start VM" --yesno "Start VM after deployment?" 10 60; then
    START_VM="yes"
  else
    START_VM="no"
  fi
  
  # Confirm
  local confirm_msg="Deploy VM with these settings?\n\nTemplate: $template_name\nHostname: $HOSTNAME\nDisk: ${DISK_SIZE}GB"
  [ "$POST_INSTALL" != "none" ] && confirm_msg+="\nPost-Install: $POST_INSTALL"
  [ "$START_VM" = "yes" ] && confirm_msg+="\nAuto-start: Yes"
  
  if whiptail --title "Confirm" --yesno "$confirm_msg" 18 60; then
    clear
    deploy_from_template
    echo ""
    read -p "Press Enter to continue..."
  fi
  
  interactive_main_menu
}

wait_for_vm_ready() {
  local vmid=$1
  local timeout=${2:-120}
  local elapsed=0

  info "Waiting for VM $vmid to be ready..."

  while [ $elapsed -lt $timeout ]; do
    if qm guest exec $vmid -- test -f /usr/bin/systemctl &>/dev/null; then
      ok "VM is ready"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  warn "VM readiness timeout after ${timeout}s"
  return 1
}

run_post_install() {
  local vmid=$1
  local script_type=$2

  [ -z "$script_type" ] || [ "$script_type" = "none" ] && return 0

  info "Running post-install: $script_type"

  # Wait for VM to be ready
  wait_for_vm_ready "$vmid" 180 || {
    warn "VM not ready, skipping post-install"
    return 1
  }

  case "$script_type" in
  docker)
    info "Installing Docker..."
    qm guest exec "$vmid" -- bash -c '
        curl -fsSL https://get.docker.com | sh && \
        systemctl enable --now docker && \
        usermod -aG docker $(whoami) 2>/dev/null || true
      ' || {
      warn "Docker installation failed"
      return 1
    }
    ok "Docker installed successfully"
    ;;

  podman)
    info "Installing Podman..."
    qm guest exec "$vmid" -- bash -c '
        if command -v apt-get &>/dev/null; then
          apt-get update && apt-get install -y podman
        elif command -v dnf &>/dev/null; then
          dnf install -y podman
        elif command -v yum &>/dev/null; then
          yum install -y podman
        else
          echo "Package manager not supported"
          exit 1
        fi && \
        systemctl enable --now podman || true
      ' || {
      warn "Podman installation failed"
      return 1
    }
    ok "Podman installed successfully"
    ;;

  portainer)
    info "Installing Portainer (requires Docker)..."
    # First install Docker
    run_post_install "$vmid" "docker" || return 1

    info "Deploying Portainer container..."
    qm guest exec "$vmid" -- bash -c '
        docker volume create portainer_data && \
        docker run -d \
          -p 8000:8000 \
          -p 9443:9443 \
          --name portainer \
          --restart=always \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v portainer_data:/data \
          portainer/portainer-ce:latest
      ' || {
      warn "Portainer deployment failed"
      return 1
    }
    ok "Portainer deployed successfully"
    info "Access Portainer at: https://<vm-ip>:9443"
    ;;

  *)
    warn "Unknown post-install script: $script_type"
    return 1
    ;;
  esac

  return 0
}

# ============================================================================
# TEMPLATE OPERATIONS
# ============================================================================

list_templates() {
  echo -e "\n${BOLD}${CYAN}Available VM Templates:${NC}\n"
  echo "┌──────┬────────────────────────────┬─────────┬────────┬──────────┬────────────┐"
  echo "│ VMID │ Name                       │ Cores   │ Memory │ Disk     │ Cloud-Init │"
  echo "├──────┼────────────────────────────┼─────────┼────────┼──────────┼────────────┤"

  local found=0
  while IFS= read -r line; do
    local vmid=$(echo "$line" | awk '{print $1}')
    local name=$(echo "$line" | awk '{print $2}')

    if is_template "$vmid"; then
      local config=$(qm config "$vmid" 2>/dev/null)
      local cores=$(echo "$config" | grep "^cores:" | awk '{print $2}')
      local memory=$(echo "$config" | grep "^memory:" | awk '{print $2}')
      local disk=$(echo "$config" | grep "scsi0:" | grep -oP '\d+G' | head -1)
      local has_ci=$(echo "$config" | grep -q "ide2:.*cloudinit" && echo "Yes" || echo "No")

      printf "│ %-4s │ %-26s │ %-7s │ %-6s │ %-8s │ %-10s │\n" \
        "$vmid" "$name" "${cores:-N/A}" "${memory:-N/A}MB" "${disk:-N/A}" "$has_ci"
      found=$((found + 1))
    fi
  done < <(qm list 2>/dev/null | tail -n +2)

  echo "└──────┴────────────────────────────┴─────────┴────────┴──────────┴────────────┘"

  if [ $found -eq 0 ]; then
    echo -e "\n${YELLOW}No templates found.${NC}"
    echo -e "Create one with: $0 create --os <os-key>\n"
  else
    echo -e "\n${GREEN}Total: $found template(s)${NC}\n"
  fi
}

list_os_options() {
  echo -e "\n${BOLD}${CYAN}Available OS Images:${NC}\n"
  local i=1
  for key in $(echo "${!OS_IMAGES[@]}" | tr ' ' '\n' | sort); do
    printf "%2d) %-20s %s\n" $i "$key" "${OS_IMAGES[$key]}"
    i=$((i + 1))
  done
  echo ""
}

create_template() {
  # Validate OS
  [ -z "$OS_KEY" ] && error "OS not specified. Use --os <os-key>"
  [ -z "${OS_IMAGES[$OS_KEY]:-}" ] && error "Unknown OS: $OS_KEY (use --list-os)"

  local image_url="${OS_IMAGES[$OS_KEY]}"
  local template_name="${TEMPLATE_PREFIX}-${OS_KEY}"

  # Check if template already exists
  local existing_id=$(find_template_by_name "$template_name")
  if [ -n "$existing_id" ]; then
    warn "Template '$template_name' already exists (ID: $existing_id)"
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      info "Aborted"
      exit 0
    fi
    qm destroy "$existing_id" &>/dev/null || true
  fi

  # Get VM ID
  [ -z "$VMID" ] && VMID=$(get_next_vmid $TEMPLATE_ID_START)
  [ -z "$STORAGE" ] && STORAGE=$(get_default_storage)

  info "Creating template: $template_name (ID: $VMID)"
  [ "$ENABLE_CLOUDINIT" = "yes" ] && info "Cloud-Init: Enabled" || info "Cloud-Init: Disabled"

  # Download/cache image
  local cache_dir="/var/lib/vz/template/cache"
  local image_file="$cache_dir/$(basename "$image_url")"
  mkdir -p "$cache_dir"

  if [ ! -f "$image_file" ]; then
    info "Downloading image..."
    curl -fL --progress-bar -o "$image_file" "$image_url" || error "Download failed"
    ok "Image downloaded"
  else
    ok "Using cached image"
  fi

  # Create VM
  info "Creating VM shell"
  qm create "$VMID" \
    --name "$template_name" \
    --machine "$MACHINE_TYPE" \
    --bios ovmf \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --net0 "virtio,bridge=$BRIDGE" \
    --scsihw virtio-scsi-single \
    --ostype l26 \
    --agent enabled=1 \
    >/dev/null || error "VM creation failed"

  ok "VM shell created"

  # Import disk
  info "Importing disk"
  local import_out
  if command -v "qm" &>/dev/null && qm disk import --help &>/dev/null 2>&1; then
    import_out=$(qm disk import "$VMID" "$image_file" "$STORAGE" --format qcow2 2>&1 || true)
  else
    import_out=$(qm importdisk "$VMID" "$image_file" "$STORAGE" 2>&1 || true)
  fi

  local disk_ref=$(echo "$import_out" | grep -oP "vm-$VMID-disk-\d+" | head -1)
  [ -z "$disk_ref" ] && disk_ref=$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $5}' | sort | tail -n1)
  [ -z "$disk_ref" ] && error "Disk import failed"

  ok "Disk imported: $disk_ref"

  # Configure disks
  info "Configuring disks"
  if [ "$ENABLE_CLOUDINIT" = "yes" ]; then
    qm set "$VMID" \
      --scsi0 "${STORAGE}:${disk_ref},discard=on" \
      --boot order=scsi0 \
      --ide2 "${STORAGE}:cloudinit" \
      >/dev/null || error "Disk configuration failed"
  else
    qm set "$VMID" \
      --scsi0 "${STORAGE}:${disk_ref},discard=on" \
      --boot order=scsi0 \
      >/dev/null || error "Disk configuration failed"
  fi

  # Resize disk
  qm resize "$VMID" scsi0 "${DISK_SIZE}G" >/dev/null 2>&1 || warn "Disk resize failed"
  ok "Disk configured (${DISK_SIZE}G)"

  # Cloud-Init configuration
  if [ "$ENABLE_CLOUDINIT" = "yes" ]; then
    if [ -n "$CI_USER" ] && [ -n "$CI_SSH_KEY" ]; then
      info "Configuring Cloud-Init credentials"
      qm set "$VMID" --ciuser "$CI_USER" >/dev/null
      qm set "$VMID" --sshkeys <(echo "$CI_SSH_KEY") >/dev/null
      [ -n "$CI_PASSWORD" ] && qm set "$VMID" --cipassword "$CI_PASSWORD" >/dev/null
      ok "Cloud-Init configured"
    else
      info "Cloud-Init drive created (configure after deployment)"
    fi
  fi

  # Convert to template
  info "Converting to template"
  qm template "$VMID" >/dev/null || error "Template conversion failed"

  ok "Template created successfully!"
  echo ""
  echo "  Template ID:   $VMID"
  echo "  Template Name: $template_name"
  echo "  OS:            $OS_KEY"
  echo "  Cloud-Init:    $ENABLE_CLOUDINIT"
  echo ""
}

deploy_from_template() {
  local template_name="${TEMPLATE_PREFIX}-${OS_KEY}"
  local template_id=$(find_template_by_name "$template_name")

  [ -z "$template_id" ] && error "Template '$template_name' not found"

  if ! is_template "$template_id"; then
    error "VM $template_id is not a template"
  fi

  [ -z "$VMID" ] && VMID=$(get_next_vmid)
  [ -z "$HOSTNAME" ] && HOSTNAME="${OS_KEY}-vm-${VMID}"

  info "Cloning template $template_id -> VM $VMID ($HOSTNAME)"

  # Full clone
  qm clone "$template_id" "$VMID" --name "$HOSTNAME" --full 1 >/dev/null || error "Clone failed"
  ok "VM cloned"

  # Reconfigure network (remove MAC to get new one)
  qm set "$VMID" --delete net0 >/dev/null
  qm set "$VMID" --net0 "virtio,bridge=$BRIDGE" >/dev/null
  ok "Network reconfigured"

  # Resize if different from template
  local template_size=$(qm config "$template_id" | grep "scsi0:" | grep -oP '\d+G' | head -1)
  template_size=${template_size%G}
  if [ "$DISK_SIZE" -gt "$template_size" ]; then
    local diff=$((DISK_SIZE - template_size))
    info "Expanding disk by ${diff}G"
    qm resize "$VMID" scsi0 "+${diff}G" >/dev/null 2>&1 || warn "Resize failed"
  fi

  # Start VM if requested or if post-install is needed
  local need_start="no"
  [ "$START_VM" = "yes" ] && need_start="yes"
  [ -n "$POST_INSTALL" ] && [ "$POST_INSTALL" != "none" ] && need_start="yes"

  if [ "$need_start" = "yes" ]; then
    info "Starting VM"
    qm start "$VMID" || { warn "Start failed"; }
    ok "VM started"
  fi

  # Execute post-install scripts if specified
  if [ -n "$POST_INSTALL" ] && [ "$POST_INSTALL" != "none" ]; then
    if run_post_install "$VMID" "$POST_INSTALL"; then
      ok "Post-install completed: $POST_INSTALL"
    else
      warn "Post-install had issues, but VM is deployed"
    fi
  fi

  ok "VM deployed successfully!"
  echo ""
  echo "  VM ID:      $VMID"
  echo "  Hostname:   $HOSTNAME"
  echo "  Template:   $template_name (ID: $template_id)"
  [ -n "$POST_INSTALL" ] && [ "$POST_INSTALL" != "none" ] && echo "  Post-Install: $POST_INSTALL"
  echo ""
}

# ============================================================================
# USAGE
# ============================================================================

usage() {
  cat <<EOF
${BOLD}Usage:${NC} $0 [COMMAND] [OPTIONS]

${BOLD}Interactive Mode:${NC}
    $0                  Start interactive menu (whiptail)
    $0 --interactive    Start interactive menu
    $0 -i               Start interactive menu

${BOLD}CLI Commands:${NC}
    create              Create a new VM template
    deploy              Deploy VM from template
    list                List all templates
    list-os             Show available OS images

${BOLD}Options:${NC}
    --os KEY            OS from catalog (e.g. debian-12, ubuntu-24.04)
                        Use -nocloud suffix for images without cloud-init
    --vmid ID           VM/Template ID (auto-assigned if not specified)
    --hostname NAME     Hostname for deployed VM
    --cores NUM         CPU cores (default: $CORES)
    --memory MB         RAM in MB (default: $MEMORY)
    --disk GB           Disk size in GB (default: $DISK_SIZE)
    --storage NAME      Storage pool
    --bridge NAME       Network bridge (default: $BRIDGE)
    --start             Start VM after deployment
    --no-cloudinit      Disable cloud-init drive (default: enabled)

    ${BOLD}Cloud-Init:${NC}
    --ci-user USER      Cloud-Init username
    --ci-password PASS  Cloud-Init password
    --ci-ssh-key KEY    SSH public key

    ${BOLD}Post-Install:${NC}
    --post-install PKG  Install software after first boot
                        Options: docker, podman, portainer
                        Note: Requires cloud-init + SSH access

${BOLD}Examples:${NC}
    ${BOLD}# Create templates${NC}
    $0 create --os debian-12
    $0 create --os debian-12-nocloud --no-cloudinit
    $0 create --os ubuntu-24.04 --cores 4 --memory 4096
    $0 create --os debian-12 --ci-user admin --ci-ssh-key "ssh-rsa AAA..."

    ${BOLD}# Deploy VMs${NC}
    $0 deploy --os debian-12 --hostname webserver --start
    $0 deploy --os ubuntu-24.04 --hostname docker-host --post-install docker
    $0 deploy --os debian-12 --hostname portainer --post-install portainer --start
    $0 deploy --os rocky-9 --hostname podman-host --post-install podman --disk 100

    ${BOLD}# List resources${NC}
    $0 list
    $0 list-os

${BOLD}Post-Install Details:${NC}
    docker      - Installs Docker CE via get.docker.com
    podman      - Installs Podman via system package manager
    portainer   - Installs Docker + Portainer CE container
                  Access at https://<vm-ip>:9443

${BOLD}NoCloud Images:${NC}
    NoCloud variants (e.g., debian-12-nocloud) are minimal images
    without cloud-init pre-installed. Use --no-cloudinit with these.

EOF
  exit 0
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

# Check if run without arguments or with --interactive
if [ $# -eq 0 ] || [ "${1:-}" = "--interactive" ] || [ "${1:-}" = "-i" ]; then
  command -v whiptail >/dev/null 2>&1 || error "whiptail not found. Install it or use CLI mode."
  interactive_main_menu
  exit 0
fi

MODE="$1"
shift

while [ $# -gt 0 ]; do
  case "$1" in
  --os)
    OS_KEY="$2"
    shift 2
    ;;
  --vmid)
    VMID="$2"
    shift 2
    ;;
  --hostname)
    HOSTNAME="$2"
    shift 2
    ;;
  --cores)
    CORES="$2"
    shift 2
    ;;
  --memory)
    MEMORY="$2"
    shift 2
    ;;
  --disk)
    DISK_SIZE="$2"
    shift 2
    ;;
  --storage)
    STORAGE="$2"
    shift 2
    ;;
  --bridge)
    BRIDGE="$2"
    shift 2
    ;;
  --start)
    START_VM="yes"
    shift
    ;;
  --no-cloudinit)
    ENABLE_CLOUDINIT="no"
    shift
    ;;
  --ci-user)
    CI_USER="$2"
    shift 2
    ;;
  --ci-password)
    CI_PASSWORD="$2"
    shift 2
    ;;
  --ci-ssh-key)
    CI_SSH_KEY="$2"
    shift 2
    ;;
  --post-install)
    POST_INSTALL="$2"
    shift 2
    ;;
  -h | --help) usage ;;
  *) error "Unknown option: $1 (use --help)" ;;
  esac
done

# ============================================================================
# CHECKS
# ============================================================================

[ "$(id -u)" -ne 0 ] && error "Root privileges required"
command -v qm >/dev/null 2>&1 || error "qm not found - Is Proxmox VE installed?"
command -v pvesm >/dev/null 2>&1 || error "pvesm not found"

# ============================================================================
# MAIN
# ============================================================================

trap cleanup_vm EXIT

case "$MODE" in
create)
  create_template
  ;;
deploy)
  deploy_from_template
  ;;
list)
  list_templates
  ;;
list-os)
  list_os_options
  ;;
*)
  error "Unknown command: $MODE (use --help)"
  ;;
esac

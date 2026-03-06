#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://rocm.docs.amd.com

# ==============================================================================
# ROCm ADDON - AMD ROCm Installation for Debian/Ubuntu LXC Containers
# Supports: Debian 12, Debian 13, Ubuntu 22.04, Ubuntu 24.04
# ==============================================================================

function header_info {
  clear
  cat <<"EOF"
    ____  ____  ________  ___
   / __ \/ __ \/ ____/  |/  /
  / /_/ / / / / /   / /|_/ / 
 / _, _/ /_/ / /___/ /  / /  
/_/ |_|\____/\____/_/  /_/                       
             
ROCM Installer for Proxmox LXC Containers
                       
EOF
}

# ==============================================================================
# COLORS & FORMATTING
# ==============================================================================
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"
TAB="  "

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }
function msg_warn() { echo -e "⚠️  ${YW}${1}${CL}"; }

# ==============================================================================
# OS DETECTION
# ==============================================================================
function detect_os() {
  if [[ ! -f "/etc/os-release" ]]; then
    msg_error "Cannot detect OS. /etc/os-release not found."
    exit 1
  fi

  source /etc/os-release

  OS_ID="${ID}"
  OS_VERSION_ID="${VERSION_ID}"
  OS_VERSION_CODENAME="${VERSION_CODENAME:-unknown}"
  ROCM_VERSION="7.2"

  case "${OS_ID}" in
    debian)
      OS="Debian"
      case "${OS_VERSION_ID}" in
        12)
          OS_CODENAME="bookworm"
          ROCM_REPO_CODENAME="jammy"
          ;;
        13)
          OS_CODENAME="trixie"
          ROCM_REPO_CODENAME="noble"
          ;;
        *)
          msg_error "Unsupported Debian version: ${OS_VERSION_ID}"
          msg_info "Supported versions: Debian 12, Debian 13"
          exit 1
          ;;
      esac
      ;;
    ubuntu)
      OS="Ubuntu"
      case "${OS_VERSION_ID}" in
        22.04)
          OS_CODENAME="jammy"
          ROCM_REPO_CODENAME="jammy"
          ;;
        24.04)
          OS_CODENAME="noble"
          ROCM_REPO_CODENAME="noble"
          ;;
        *)
          msg_error "Unsupported Ubuntu version: ${OS_VERSION_ID}"
          msg_info "Supported versions: Ubuntu 22.04, Ubuntu 24.04"
          exit 1
          ;;
      esac
      ;;
    *)
      msg_error "Unsupported OS: ${OS_ID}"
      msg_info "Supported OS: Debian 12, Debian 13, Ubuntu 22.04, Ubuntu 24.04"
      exit 1
      ;;
  esac

  msg_ok "Detected: ${OS} ${OS_VERSION_ID} (${OS_CODENAME})"
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================
function get_local_ip() {
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$ip" ]] && ip="127.0.0.1"
  echo "$ip"
}

function check_lxc() {
  if [[ -f "/proc/1/cgroup" ]] && grep -q "lxc" /proc/1/cgroup 2>/dev/null; then
    return 0
  fi
  if grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
    return 0
  fi
  return 1
}

# ==============================================================================
# INSTALL FUNCTIONS
# ==============================================================================
function install_rocm_debian() {
  msg_info "Creating keyrings directory"
  mkdir -p /etc/apt/keyrings
  msg_ok "Created keyrings directory"

  msg_info "Adding ROCm repository GPG key"
  curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg
  msg_ok "Added ROCm GPG key"

  msg_info "Adding ROCm repository (using ${ROCM_REPO_CODENAME} for ${OS} ${OS_VERSION_ID})"
  cat <<EOF >/etc/apt/sources.list.d/rocm.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} ${ROCM_REPO_CODENAME} main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/${ROCM_VERSION}/ubuntu ${ROCM_REPO_CODENAME} main
EOF
  msg_ok "Added ROCm repository"

  msg_info "Setting package pin preferences"
  cat <<EOF >/etc/apt/preferences.d/rocm-pin-600
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF
  msg_ok "Set package pin preferences"

  msg_info "Updating package lists"
  $STD apt update
  msg_ok "Updated package lists"

  msg_info "Installing ROCm packages"
  $STD apt install -y rocm
  msg_ok "Installed ROCm packages"

  msg_info "Adding user to render and video groups"
  usermod -aG render,video root 2>/dev/null || true
  for user_home in /home/*/; do
    user=$(basename "$user_home")
    usermod -aG render,video "$user" 2>/dev/null || true
  done
  msg_ok "Added users to render and video groups"

  msg_info "Configuring environment"
  echo "export PATH=\$PATH:/opt/rocm/bin" >/etc/profile.d/rocm.sh
  echo "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/opt/rocm/lib" >>/etc/profile.d/rocm.sh
  chmod +x /etc/profile.d/rocm.sh
  msg_ok "Configured environment"
}

function install_rocm_ubuntu() {
  msg_info "Creating keyrings directory"
  mkdir -p /etc/apt/keyrings
  msg_ok "Created keyrings directory"

  msg_info "Adding ROCm repository GPG key"
  curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg
  msg_ok "Added ROCm GPG key"

  msg_info "Adding ROCm repository"
  cat <<EOF >/etc/apt/sources.list.d/rocm.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} ${ROCM_REPO_CODENAME} main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/${ROCM_VERSION}/ubuntu ${ROCM_REPO_CODENAME} main
EOF
  msg_ok "Added ROCm repository"

  msg_info "Setting package pin preferences"
  cat <<EOF >/etc/apt/preferences.d/rocm-pin-600
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF
  msg_ok "Set package pin preferences"

  msg_info "Updating package lists"
  $STD apt update
  msg_ok "Updated package lists"

  msg_info "Installing ROCm packages"
  $STD apt install -y rocm
  msg_ok "Installed ROCm packages"

  msg_info "Adding user to render and video groups"
  usermod -aG render,video root 2>/dev/null || true
  for user_home in /home/*/; do
    user=$(basename "$user_home")
    usermod -aG render,video "$user" 2>/dev/null || true
  done
  msg_ok "Added users to render and video groups"

  msg_info "Configuring environment"
  echo "export PATH=\$PATH:/opt/rocm/bin" >/etc/profile.d/rocm.sh
  echo "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/opt/rocm/lib" >>/etc/profile.d/rocm.sh
  chmod +x /etc/profile.d/rocm.sh
  msg_ok "Configured environment"
}

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall_rocm() {
  msg_info "Uninstalling ROCm"

  msg_info "Removing ROCm packages"
  $STD apt remove -y rocm 2>/dev/null || true
  $STD apt autoremove -y 2>/dev/null || true
  msg_ok "Removed ROCm packages"

  msg_info "Removing ROCm repository"
  rm -f /etc/apt/sources.list.d/rocm.list
  rm -f /etc/apt/keyrings/rocm.gpg
  rm -f /etc/apt/preferences.d/rocm-pin-600
  $STD apt update
  msg_ok "Removed ROCm repository"

  msg_info "Removing environment configuration"
  rm -f /etc/profile.d/rocm.sh
  msg_ok "Removed environment configuration"

  msg_ok "ROCm has been uninstalled"
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update_rocm() {
  if [[ ! -f /etc/apt/keyrings/rocm.gpg ]]; then
    msg_error "ROCm is not installed"
    exit 1
  fi

  msg_info "Checking for ROCm updates"
  $STD apt update

  local updates
  updates=$(apt list --upgradable 2>/dev/null | grep -c "rocm" || true)

  if [[ "$updates" -gt 0 ]]; then
    msg_ok "Found ${updates} ROCm package update(s)"
    msg_info "Upgrading ROCm packages"
    $STD apt upgrade -y rocm
    msg_ok "Updated ROCm packages"
  else
    msg_ok "ROCm is already up-to-date"
  fi
}

# ==============================================================================
# VERIFY INSTALLATION
# ==============================================================================
function verify_installation() {
  msg_info "Verifying ROCm installation"

  if [[ -x /opt/rocm/bin/rocminfo ]]; then
    msg_ok "ROCm installed successfully"
    echo ""
    echo -e "${TAB}${BL}ROCm Version:${CL} $(/opt/rocm/bin/rocminfo --version 2>/dev/null | head -1 || echo 'Installed')"
    echo -e "${TAB}${BL}Install Path:${CL} /opt/rocm"
    echo ""
    echo -e "${TAB}${YW}To use ROCm, either:${CL}"
    echo -e "${TAB}  1. Log out and back in, or"
    echo -e "${TAB}  2. Run: source /etc/profile.d/rocm.sh"
    echo ""
    echo -e "${TAB}${YW}Verify installation with:${CL}"
    echo -e "${TAB}  rocminfo"
    echo -e "${TAB}  rocm-smi"
  else
    msg_warn "ROCm installed but rocminfo not found. GPU may not be available."
  fi
}

# ==============================================================================
# MAIN
# ==============================================================================
header_info
detect_os

IP=$(get_local_ip)

# Check if running in LXC container
if ! check_lxc; then
  msg_warn "This script is designed for LXC containers."
  msg_warn "Running on bare metal may work but is not officially supported."
  echo ""
fi

# Check for existing installation
if [[ -f /etc/apt/keyrings/rocm.gpg ]]; then
  msg_warn "ROCm is already installed."
  echo ""

  echo -n "${TAB}Uninstall ROCm? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall_rocm
    exit 0
  fi

  echo -n "${TAB}Update ROCm? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    update_rocm
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

# Fresh installation
msg_warn "ROCm is not installed."
echo ""

echo -e "${TAB}${BL}This will install AMD ROCm on ${OS} ${OS_VERSION_ID}${CL}"
echo -e "${TAB}${BL}Supported GPUs: AMD Radeon Instinct, Radeon Pro, and some consumer GPUs${CL}"
echo ""

echo -n "${TAB}Install ROCm? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  case "${OS}" in
    Debian) install_rocm_debian ;;
    Ubuntu) install_rocm_ubuntu ;;
    *)
      msg_error "Unsupported OS: ${OS}"
      exit 1
      ;;
  esac

  verify_installation

  echo ""
  msg_ok "ROCm installation completed!"
  echo -e "${TAB}${GN}Documentation: ${BL}https://rocm.docs.amd.com${CL}"
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi
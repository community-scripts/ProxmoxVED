#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source /dev/stdin <<<$(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/vm/cloud-init.func")

function header_info {
  clear
  cat <<"EOF"
   __  ____                __           ___  __ __   ____  __ __     _    ____  ___
  / / / / /_  __  ______  / /___  __   |__ \/ // /  / __ \/ // /    | |  / /  |/  /
 / / / / __ \/ / / / __ \/ __/ / / /   __/ / // /_ / / / / // /_    | | / / /|_/ /
/ /_/ / /_/ / /_/ / / / / /_/ /_/ /   / __/__  __// /_/ /__  __/    | |/ / /  / /
\____/_.___/\__,_/_/ /_/\__/\__,_/   /____/ /_/ (_)____/  /_/       |___/_/  /_/

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="ubuntu-2404-vm"
var_os="ubuntu"
var_version="2404"
CLOUDINIT_ENABLE="no"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"
CLOUD="${TAB}☁️${TAB}${CL}"

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
  post_update_to_api "failed" "$command"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Ubuntu 24.04 VM" --yesno "This will create a New Ubuntu 24.04 VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

function pve_check() {
  if ! pveversion | grep -Eq "pve-manager/(8\.[1-4]|9\.[0-2])(\.[0-9]+)*"; then
    msg_error "${CROSS}${RD}This version of Proxmox Virtual Environment is not supported"
    echo -e "Requires Proxmox Virtual Environment Version 8.1 - 8.4 or 9.0 - 9.2."
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}${YWB}This script will not work with PiMox! \n"
    echo -e "\n ${YWB}Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

function ubuntu_validate_cloud_init_user() {
  local user="$1"
  [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] && [ "${#user}" -le 32 ]
}

function ubuntu_validate_ssh_key_file() {
  local key_file="$1"
  local key
  local key_count=0

  command -v ssh-keygen >/dev/null 2>&1 || return 1
  while IFS= read -r key || [ -n "$key" ]; do
    key="${key%$'\r'}"
    [ -z "${key//[[:space:]]/}" ] && continue
    [[ "$key" == \#* ]] && continue
    printf '%s\n' "$key" | ssh-keygen -lf - >/dev/null 2>&1 || return 1
    key_count=$((key_count + 1))
  done <"$key_file"
  [ "$key_count" -gt 0 ]
}

function ubuntu_normalize_ssh_key_file() {
  local key_file="$1"
  local normalized_file="${key_file}.normalized"
  local key

  : >"$normalized_file"
  while IFS= read -r key || [ -n "$key" ]; do
    key="${key%$'\r'}"
    [ -z "${key//[[:space:]]/}" ] && continue
    [[ "$key" == \#* ]] && continue
    printf '%s\n' "$key" >>"$normalized_file"
  done <"$key_file"
  mv -f "$normalized_file" "$key_file"
}

function ubuntu_discover_host_ssh_keys() {
  local discovered_file="$TEMP_DIR/cloud-init-host-sshkeys"
  local key_file
  local key

  : >"$discovered_file"
  for key_file in /root/.ssh/authorized_keys /root/.ssh/authorized_keys2 /root/.ssh/*.pub \
    /etc/ssh/authorized_keys /etc/ssh/authorized_keys.d/*; do
    [ -f "$key_file" ] || continue
    while IFS= read -r key || [ -n "$key" ]; do
      key="${key%$'\r'}"
      [ -z "${key//[[:space:]]/}" ] && continue
      [[ "$key" == \#* ]] && continue
      printf '%s\n' "$key" >>"$discovered_file"
    done <"$key_file"
  done

  if [ -s "$discovered_file" ] && ubuntu_validate_ssh_key_file "$discovered_file"; then
    ubuntu_normalize_ssh_key_file "$discovered_file"
    printf '%s\n' "$discovered_file"
    return 0
  fi
  rm -f "$discovered_file"
  return 1
}

function ubuntu_configure_ssh_keys() {
  local key_source
  local key_value
  local key_file="$TEMP_DIR/cloud-init-sshkeys"
  local host_key_file

  rm -f "$key_file"
  if key_source=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SSH KEY" --menu \
    "Choose how to configure an SSH public key." 16 76 5 \
    "host" "Copy public keys from the Proxmox host" \
    "paste" "Paste an OpenSSH public key" \
    "url" "Download keys from an HTTPS URL (e.g. https://github.com/user.keys)" \
    "folder" "Read keys from a file, folder, or glob" \
    "none" "Do not configure an SSH key" 3>&1 1>&2 2>&3); then
    case "$key_source" in
    host)
      if host_key_file=$(ubuntu_discover_host_ssh_keys); then
        cp "$host_key_file" "$key_file"
      else
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "NO HOST SSH KEYS" \
          --msgbox "No valid public SSH keys were found in /root/.ssh/." 8 58
        return 65
      fi
      ;;
    paste)
      if key_value=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
        "Paste an OpenSSH public key exactly as provided (ssh-ed25519, ssh-rsa, etc.)." \
        10 76 --title "PASTE SSH PUBLIC KEY" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [ -n "$key_value" ] || return 0
        printf '%s\n' "$key_value" >"$key_file"
      else
        return 1
      fi
      ;;
    url)
      if key_value=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
        "Enter an HTTPS URL returning one or more OpenSSH public keys." \
        10 76 --title "SSH KEY URL" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [[ "$key_value" =~ ^https://[^/[:space:]]+(/[^[:space:]]*)?$ ]] || {
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID URL" \
            --msgbox "Only HTTPS URLs are supported for SSH key downloads." 8 58
          return 65
        }
        if ! curl -f#L --proto '=https' --proto-redir '=https' --max-time 30 --max-filesize 1048576 \
          --retry 2 -o "$key_file" "$key_value"; then
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "SSH KEY DOWNLOAD FAILED" \
            --msgbox "Unable to download SSH keys from:\n\n$key_value" 10 70
          return 65
        fi
      else
        return 1
      fi
      ;;
    folder)
      if key_value=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
        "Enter a key file, folder, or glob (e.g. /root/.ssh/*.pub)." \
        10 72 --title "SSH KEY FILE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        local -a key_files=()
        local candidate
        shopt -s nullglob
        if [ -d "$key_value" ]; then
          key_files=("$key_value"/*.pub "$key_value"/authorized_keys "$key_value"/authorized_keys2)
        else
          key_files=($key_value)
        fi
        shopt -u nullglob
        for candidate in "${key_files[@]}"; do
          [ -f "$candidate" ] || continue
          while IFS= read -r key || [ -n "$key" ]; do
            key="${key%$'\r'}"
            [ -z "${key//[[:space:]]/}" ] && continue
            [[ "$key" == \#* ]] && continue
            printf '%s\n' "$key" >>"$key_file"
          done <"$candidate"
        done
      else
        return 1
      fi
      ;;
    none)
      return 0
      ;;
    esac
  else
    return 1
  fi

  if ! ubuntu_validate_ssh_key_file "$key_file"; then
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID SSH KEY" \
      --msgbox "The input did not contain valid OpenSSH public keys." 8 70
    rm -f "$key_file"
    return 65
  fi
  ubuntu_normalize_ssh_key_file "$key_file"
  CLOUDINIT_SSH_KEYS="$key_file"
  chmod 600 "$key_file"
  echo -e "${ROOTSSH:-${TAB}🔑${TAB}${CL}}${BOLD}${DGN}SSH Keys: ${BGN}configured${CL}"
  return 0
}

function ubuntu_configure_cloud_init_credentials() {
  local password_confirm
  local key_status

  while true; do
    if CLOUDINIT_PASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox \
      "Set a password for ${CLOUDINIT_USER}. A password is optional when an SSH key is configured in the next step." \
      10 70 --title "CLOUD-INIT PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -n "$CLOUDINIT_PASSWORD" ]; then
        if password_confirm=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox \
          "Confirm the Cloud-Init password." 8 70 --title "CONFIRM PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
          [ "$CLOUDINIT_PASSWORD" = "$password_confirm" ] || {
            whiptail --backtitle "Proxmox VE Helper Scripts" --title "PASSWORD MISMATCH" \
              --msgbox "The passwords do not match. Please try again." 8 58
            continue
          }
        else
          return 1
        fi
      fi
    else
      return 1
    fi

    CLOUDINIT_SSH_KEYS=""
    key_status=0
    ubuntu_configure_ssh_keys || key_status=$?
    [ "$key_status" -eq 65 ] && continue
    [ "$key_status" -eq 0 ] || return "$key_status"
    if [ -n "$CLOUDINIT_PASSWORD" ] || [ -n "${CLOUDINIT_SSH_KEYS:-}" ]; then
      break
    fi
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "LOGIN REQUIRED" \
      --msgbox "Configure a password or an SSH public key so the VM can be accessed after its first boot." 10 70
  done

  if [ -n "${CLOUDINIT_SSH_KEYS:-}" ]; then
    CLOUDINIT_SSH_PWAUTH="no"
  else
    CLOUDINIT_SSH_PWAUTH="yes"
  fi
  export CLOUDINIT_PASSWORD CLOUDINIT_SSH_PWAUTH
}

function ubuntu_finalize_cloud_init() {
  local password="$1"

  CLOUDINIT_PASSWORD="$password"
  if [ -n "${CLOUDINIT_PASSWORD:-}" ]; then
    qm set "$VMID" --cipassword "$CLOUDINIT_PASSWORD" >/dev/null
  else
    qm set "$VMID" --delete cipassword >/dev/null 2>&1 || true
  fi

  if [ "${CLOUDINIT_NETWORK_MODE:-dhcp}" = "dhcp" ]; then
    qm set "$VMID" --delete nameserver >/dev/null 2>&1 || true
  fi

  CLOUDINIT_CRED_FILE="/tmp/${HN}-${VMID}-cloud-init-credentials.txt"
  if [ "${CLOUDINIT_NETWORK_MODE:-dhcp}" = "static" ]; then
    CLOUDINIT_NETWORK_SUMMARY="static (IP: ${CLOUDINIT_IP}${CLOUDINIT_GW:+, GW: ${CLOUDINIT_GW}})"
    CLOUDINIT_DNS_SUMMARY="${CLOUDINIT_DNS:-not configured}"
  else
    CLOUDINIT_NETWORK_SUMMARY="DHCP"
    CLOUDINIT_DNS_SUMMARY="provided by DHCP"
  fi

  umask 077
  cat >"$CLOUDINIT_CRED_FILE" <<EOF
Cloud-Init Credentials
======================
VM ID:    ${VMID}
Hostname: ${HN}

Username: ${CLOUDINIT_USER}
Password: ${CLOUDINIT_PASSWORD:-not configured (SSH key authentication)}
Network:  ${CLOUDINIT_NETWORK_SUMMARY}
DNS:      ${CLOUDINIT_DNS_SUMMARY}

SSH Access:
  ssh ${CLOUDINIT_USER}@<vm-ip>

Delete this file after noting the credentials:
  rm -f ${CLOUDINIT_CRED_FILE}
EOF
  chmod 600 "$CLOUDINIT_CRED_FILE"
  export CLOUDINIT_CRED_FILE
}

function ubuntu_configure_cloud_init_advanced() {
  while true; do
    if CLOUDINIT_USER=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
      "Set the Cloud-Init login username. A non-root user is recommended and will receive passwordless sudo." \
      10 70 "ubuntu" --title "CLOUD-INIT USER" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      CLOUDINIT_USER="${CLOUDINIT_USER:-ubuntu}"
      ubuntu_validate_cloud_init_user "$CLOUDINIT_USER" && break
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID USERNAME" \
        --msgbox "Use 1-32 lowercase letters, numbers, underscores, or hyphens. The first character must be a letter or underscore." 10 70
    else
      return 1
    fi
  done

  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "NETWORK MODE" \
    --yesno "Use DHCP for network configuration?" 10 58; then
    CLOUDINIT_NETWORK_MODE="dhcp"
    CLOUDINIT_IP=""
    CLOUDINIT_GW=""
    CLOUDINIT_DNS=""
  else
    CLOUDINIT_NETWORK_MODE="static"
    while true; do
      if CLOUDINIT_IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
        "Static IP Address (CIDR format)\nExample: 192.168.1.100/24" 9 58 "" --title "IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        validate_ip_cidr "$CLOUDINIT_IP" && break
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID IP" \
          --msgbox "Please use CIDR format: x.x.x.x/xx" 8 58
      else
        return 1
      fi
    done
    while true; do
      if CLOUDINIT_GW=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
        "Gateway IP Address\nExample: 192.168.1.1" 8 58 "" --title "GATEWAY" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        validate_ip "$CLOUDINIT_GW" && break
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID GATEWAY" \
          --msgbox "Please use format: x.x.x.x" 8 58
      else
        return 1
      fi
    done
    if CLOUDINIT_DNS=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
      "DNS Servers (space-separated)" 8 58 "1.1.1.1 8.8.8.8" --title "DNS SERVERS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      CLOUDINIT_DNS="${CLOUDINIT_DNS:-1.1.1.1 8.8.8.8}"
    else
      return 1
    fi
  fi

  ubuntu_configure_cloud_init_credentials
}

function ubuntu_configure_cloud_init_default() {
  CLOUDINIT_ENABLE="yes"
  CLOUDINIT_USER="ubuntu"
  CLOUDINIT_NETWORK_MODE="dhcp"
  CLOUDINIT_IP=""
  CLOUDINIT_GW=""
  CLOUDINIT_DNS=""
  CLOUDINIT_PASSWORD=$(openssl rand -base64 16)
  if ubuntu_discover_host_ssh_keys >/dev/null; then
    CLOUDINIT_SSH_KEYS="$TEMP_DIR/cloud-init-host-sshkeys"
    CLOUDINIT_SSH_PWAUTH="no"
    echo -e "${ROOTSSH:-${TAB}🔑${TAB}${CL}}${BOLD}${DGN}SSH Keys: ${BGN}host keys selected${CL}"
  else
    CLOUDINIT_SSH_KEYS=""
    CLOUDINIT_SSH_PWAUTH="yes"
    echo -e "${ROOTSSH:-${TAB}🔑${TAB}${CL}}${BOLD}${DGN}SSH Keys: ${BGN}none found${CL}"
  fi
  echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init access: ${BGN}${CLOUDINIT_USER} with generated password${CL}"
}

function ubuntu_ensure_virt_customize() {
  if ! command -v virt-customize >/dev/null 2>&1; then
    msg_info "Installing libguestfs-tools"
    apt-get update >/dev/null 2>&1
    apt-get install -y libguestfs-tools >/dev/null 2>&1
    msg_ok "Installed libguestfs-tools"
  fi
}

function ubuntu_configure_image_access() {
  local image="$1"
  ubuntu_ensure_virt_customize
  if [ "$CLOUDINIT_ENABLE" = "yes" ]; then
    virt-customize -q -a "$image" --run-command \
      "mkdir -p /etc/cloud/cloud.cfg.d && printf 'ssh_pwauth: ${CLOUDINIT_SSH_PWAUTH}\\n' > /etc/cloud/cloud.cfg.d/99-community-scripts-ssh-pwauth.cfg" \
      >/dev/null 2>&1
  else
    virt-customize -q -a "$image" --run-command 'mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d /etc/systemd/system/getty@tty1.service.d && cat > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf << "EOF"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << "EOF"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF' >/dev/null 2>&1
  fi
}

function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_SIZE="7G"
  DISK_CACHE=""
  HN="ubuntu"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  ubuntu_configure_cloud_init_default
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 24.04 VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  DISK_SIZE="${DISK_SIZE:-7G}"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
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
      exit-script
    fi
  done

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Configure the VM with Cloud-Init?" 10 58); then
    CLOUDINIT_ENABLE="yes"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
    ubuntu_configure_cloud_init_advanced || exit_script
  else
    CLOUDINIT_ENABLE="no"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
  fi

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 10 or 10G).${CL}"
      exit-script
    fi
  else
    exit-script
  fi

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
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 ubuntu --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="ubuntu"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
    3>&1 1>&2 2>&3); then
    if [ $CPU_TYPE1 = "1" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $CORE_COUNT ]; then
      CORE_COUNT="2"
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    else
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    fi
  else
    exit-script
  fi

  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $RAM_SIZE ]; then
      RAM_SIZE="2048"
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    else
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    fi
  else
    exit-script
  fi

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then
      BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      MAC="$GEN_MAC"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
    else
      MAC="$MAC1"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC1${CL}"
    fi
  else
    exit-script
  fi

  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VLAN1 ]; then
      VLAN1="Default"
      VLAN=""
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    else
      VLAN=",tag=$VLAN1"
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    fi
  else
    exit-script
  fi

  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MTU1 ]; then
      MTU1="Default"
      MTU=""
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    else
      MTU=",mtu=$MTU1"
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    fi
  else
    exit-script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Ubuntu 24.04 VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 24.04 VM using the above advanced settings${CL}"
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
check_root
arch_check
pve_check
ssh_check
start_script
post_to_api_vm

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
msg_info "Retrieving the URL for the Ubuntu 24.04 Disk Image"
URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

ubuntu_configure_image_access "$FILE"

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir | cifs)
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

msg_info "Creating a Ubuntu 24.04 VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
if [ "$CLOUDINIT_ENABLE" = "yes" ]; then
  setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "$CLOUDINIT_USER" \
    "$CLOUDINIT_NETWORK_MODE" "${CLOUDINIT_IP:-}" "${CLOUDINIT_GW:-}" \
    "${CLOUDINIT_DNS:-}" "${CLOUDINIT_PASSWORD:-}"
  ubuntu_finalize_cloud_init "${CLOUDINIT_PASSWORD:-}"
fi
DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>ubuntu VM</h2>

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
if [ -n "$DISK_SIZE" ]; then
  msg_info "Resizing disk to $DISK_SIZE GB"
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
else
  msg_info "Using default disk size of $DEFAULT_DISK_SIZE GB"
  qm resize $VMID scsi0 ${DEFAULT_DISK_SIZE} >/dev/null
fi

msg_ok "Created a Ubuntu 24.04 VM ${CL}${BL}(${HN})"
if [ "$CLOUDINIT_ENABLE" = "yes" ]; then
  display_cloud_init_info "$VMID" "$HN" 2>/dev/null || true
else
  echo -e "${INFO}Console auto-login configured for root. Cloud-Init was not configured."
fi
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Ubuntu 24.04 VM"
  qm start $VMID
  msg_ok "Started Ubuntu 24.04 VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"
if [ "$CLOUDINIT_ENABLE" = "yes" ]; then
  echo -e "Cloud-Init configured for user ${CLOUDINIT_USER}.\n
SSH key authentication: $([ -n "${CLOUDINIT_SSH_KEYS:-}" ] && echo configured || echo not configured)\n
SSH password authentication: $([ "${CLOUDINIT_SSH_PWAUTH:-yes}" = "yes" ] && echo enabled || echo disabled)\n
Console password: $([ -n "${CLOUDINIT_PASSWORD:-}" ] && echo configured || echo not configured)\n
More info at https://github.com/community-scripts/ProxmoxVED/discussions/272 \n"
else
  echo -e "Cloud-Init was not configured.\n
Console auto-login is enabled for root.\n
More info at https://github.com/community-scripts/ProxmoxVED/discussions/272 \n"
fi

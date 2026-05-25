#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: JuanCF (https://github.com/JuanCF)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/JuanCF/proxmox-nut-server
#
# vm/nut-vm.sh - Proxmox NUT Server VM Setup Script
#
# Creates an Ubuntu 24.04 VM on Proxmox, configures USB passthrough for UPS,
# and installs/configures NUT (Network UPS Tools) in netserver mode.
#
# Uses virt-customize for offline disk image modification — no SSH.
#
# Must be run as root on a Proxmox host.

# Consumed by build.func via source on line 18 — shellcheck can’t follow non-constant sources.
# shellcheck disable=SC2034
APP="NUT VM"
var_tags="nut;vm;ups;network"
var_cpu="1"
var_ram="1024"
var_disk="8"
var_os="ubuntu"
var_version="24.04"

# These functions are fetched at runtime; shellcheck cannot statically analyze them.
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/cloud-init.func)

SPINNER_PID=""
SCRIPT_ERROR_LOG=()
WORK_FILE=""
CLOUDINIT_SNIPPET=""

# build.func's msg_error prints but does not call exit; override to add exit 1
# so that check_root, check_proxmox, and whiptail cancellations abort the script.
msg_error() {
  [[ -n "${SPINNER_PID:-}" ]] && ps -p "${SPINNER_PID:-}" &>/dev/null && kill "${SPINNER_PID:-}"
  printf "\e[?25h"
  echo -e "${BFR}${CROSS}${RD}${1}${CL}"
  SCRIPT_ERROR_LOG+=("[ERROR] $1")
  SPINNER_PID=""
  exit 1
}

msg_warn() {
  SCRIPT_ERROR_LOG+=("[WARN] $1")
  echo -e "${BFR}${YW}${1}${CL}"
}

header_info() {
  clear
  cat <<"EOF"
    _   _ _   _ _____
   | \ | | | | |_   _|
   |  \| | | | | | |
   | |\  | |_| | | |
   |_| \_|\___/  |_|

   Proxmox NUT Server VM Setup
EOF
}

#===============================================================================
# Constants
#===============================================================================

readonly UBUNTU_IMG_URL="https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
readonly UBUNTU_IMG_CHECKSUM_URL="https://cloud-images.ubuntu.com/minimal/releases/noble/release/SHA256SUMS"
readonly UBUNTU_IMG_NAME="ubuntu-24.04-minimal-cloudimg-amd64.img"
readonly IMG_CACHE_DIR="/var/lib/vz/template/iso"
readonly NUT_DEFAULT_PORT=3493
readonly SCRIPT_VERSION="1.0.0"
readonly NUT_ADMIN_REF="${NUT_ADMIN_REF:-v1.0.0}"
readonly NUT_ADMIN_RELEASES_URL="https://github.com/JuanCF/proxmox-nut-server/releases/download/${NUT_ADMIN_REF}"

# UPS Vendor IDs
# shellcheck disable=SC2034
# shellcheck disable=SC2080
readonly -A UPS_VENDORS=(
  ["051d"]="APC"
  ["0764"]="CyberPower"
  ["0463"]="Eaton"
  ["09ae"]="Tripp Lite"
  ["10af"]="Liebert"
)

#===============================================================================
# Section 2: Input/Prompt Helper Functions (whiptail)
#===============================================================================

AUTO_GENERATE_PASSWORDS=false
GENERATED_PASSWORDS=()

generate_password() {
  local length="${1:-16}"
  local password
  password=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c "$length")
  if [[ ${#password} -lt $length ]]; then
    password=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
  fi
  echo "$password"
}

prompt_autogenerate_passwords() {
  if whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "PASSWORD CONFIGURATION" \
    --yesno "Auto-generate all passwords?\n\nYes = generate secure passwords automatically.\nNo  = enter them manually." \
    12 58; then
    AUTO_GENERATE_PASSWORDS=true
    msg_ok "Passwords will be auto-generated"
  fi
}

prompt_default() {
  local varname="$1"
  local prompt_text="$2"
  local default_value="$3"
  local title="${4:-INPUT}"
  local result

  result=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "$title" \
    --inputbox "$prompt_text" \
    8 58 "$default_value" \
    3>&1 1>&2 2>&3) || msg_error "Cancelled by user"

  printf -v "$varname" '%s' "${result:-$default_value}"
}

prompt_password() {
  local varname="$1"
  local prompt_text="$2"

  if [[ "$AUTO_GENERATE_PASSWORDS" == "true" ]]; then
    local pass
    pass=$(generate_password 16)
    printf -v "$varname" '%s' "$pass"
    GENERATED_PASSWORDS+=("$prompt_text: $pass")
    return 0
  fi

  local pass1 pass2
  while true; do
    pass1=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "PASSWORD" \
      --passwordbox "$prompt_text" \
      8 58 \
      3>&1 1>&2 2>&3) || msg_error "Cancelled by user"

    pass2=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "PASSWORD" \
      --passwordbox "Confirm: $prompt_text" \
      8 58 \
      3>&1 1>&2 2>&3) || msg_error "Cancelled by user"

    if [[ "$pass1" == "$pass2" ]]; then
      printf -v "$varname" '%s' "$pass1"
      return 0
    fi
    whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "MISMATCH" \
      --msgbox "Passwords do not match. Please try again." 8 58
  done
}

prompt_yes_no() {
  local question="$1"
  local default="${2:-y}"
  local title="${3:-CONFIRM}"
  local args=(--backtitle "Proxmox VE Helper Scripts" --title "$title" --yesno "$question" 12 62)

  [[ "$default" == "n" ]] && args+=(--defaultno)
  whiptail "${args[@]}"
}

prompt_menu() {
  local varname="$1"
  local title="$2"
  shift 2
  local items=("$@")
  local menu_items=()
  local i
  for i in "${!items[@]}"; do
    menu_items+=("$((i + 1))" "${items[$i]}")
  done

  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "$title" \
    --menu "Select an option:" 16 70 "${#items[@]}" \
    "${menu_items[@]}" \
    3>&1 1>&2 2>&3) || msg_error "Cancelled by user"

  printf -v "$varname" '%s' "$((choice - 1))"
}

prompt_integer() {
  local varname="$1"
  local prompt_text="$2"
  local default_value="$3"
  local min="$4"
  local max="$5"
  local input

  while true; do
    input=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "INPUT" \
      --inputbox "$prompt_text (${min}-${max}):" \
      8 58 "$default_value" \
      3>&1 1>&2 2>&3) || msg_error "Cancelled by user"

    input="${input:-$default_value}"
    if [[ "$input" =~ ^[0-9]+$ ]] && ((input >= min && input <= max)); then
      printf -v "$varname" '%s' "$input"
      return 0
    fi
    whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "INVALID INPUT" \
      --msgbox "Please enter a number between $min and $max." 8 58
  done
}

#===============================================================================
# Section 3: Prerequisite Checks
#===============================================================================

check_root() {
  if [[ $EUID -ne 0 ]]; then
    msg_error "This script must be run as root"
  fi
  msg_ok "Running as root"
}

check_proxmox() {
  local missing=()

  for cmd in qm pvesh pveversion pvesm python3; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    msg_error "Missing Proxmox commands: ${missing[*]}"
  fi
  msg_ok "Proxmox VE environment detected"
}

check_dependencies() {
  local missing=()

  for cmd in wget curl lsusb whiptail timeout openssl ip sha256sum dpkg; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    msg_error "Missing required dependencies: ${missing[*]}"
  fi
  msg_ok "Dependencies satisfied"
}

check_virt_customize() {
  if ! command -v virt-customize &>/dev/null; then
    msg_info "virt-customize not found, installing libguestfs-tools..."
    if ! apt update -qq >/dev/null 2>&1 || ! apt install -y -qq libguestfs-tools >/dev/null 2>&1; then
      msg_error "Failed to install libguestfs-tools"
    fi
  fi

  local debian_version
  debian_version=$(lsb_release -rs 2>/dev/null || cat /etc/debian_version 2>/dev/null || echo "unknown")
  if [[ "$debian_version" == "13" ]] || [[ "$debian_version" == "trixie" ]] || [[ "$debian_version" == "13."* ]]; then
    if ! dpkg -l | grep -q "^ii  dhcpcd-base "; then
      msg_info "Installing dhcpcd-base for virt-customize network support on Debian 13..."
      if ! apt install -y -qq dhcpcd-base >/dev/null 2>&1; then
        msg_warn "Failed to install dhcpcd-base — virt-customize network commands may fail"
      fi
    fi
  fi

  msg_ok "virt-customize available"
}

check_architecture() {
  local arch
  arch=$(dpkg --print-architecture)
  if [[ "$arch" != "amd64" ]]; then
    echo -e "\n ${INFO}${YW}This script requires an amd64 Proxmox host (detected: ${arch})."
    echo -e " ${YW}The Ubuntu Noble cloud image ships amd64 only."
    sleep 2
    exit 1
  fi
  msg_ok "Architecture: amd64"
}

get_next_vmid() {
  pvesh get /cluster/nextid 2>/dev/null || echo "100"
}

list_storage_pools() {
  pvesm status --content images 2>/dev/null | awk 'NR>1 {print $1}' | head -20
}

validate_vmid() {
  local vmid="$1"
  if qm list 2>/dev/null | grep -q "^[[:space:]]*${vmid}[[:space:]]"; then
    return 1
  fi
  return 0
}

validate_bridge() {
  local bridge="$1"
  ip link show "$bridge" &>/dev/null
}

#===============================================================================
# Section 4: VM Configuration Prompts
#===============================================================================

collect_vm_config() {
  local storage_pools=()
  local storage_count=0

  VM_ID=$(get_next_vmid)
  prompt_integer VM_ID "VM ID" "$VM_ID" 100 999999999

  while ! validate_vmid "$VM_ID"; do
    whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "VM ID IN USE" \
      --msgbox "VM ID $VM_ID is already in use. Please choose another." 8 58
    prompt_integer VM_ID "VM ID" "$((VM_ID + 1))" 100 999999999
  done

  prompt_default VM_NAME "VM Hostname" "nut-server" "VM HOSTNAME"

  mapfile -t storage_pools < <(list_storage_pools)
  storage_count=${#storage_pools[@]}

  if [[ $storage_count -eq 0 ]]; then
    msg_error "No storage pools found with 'images' content type"
  elif [[ $storage_count -eq 1 ]]; then
    VM_STORAGE="${storage_pools[0]}"
    msg_ok "Using storage pool: $VM_STORAGE"
  else
    local storage_idx
    prompt_menu storage_idx "SELECT STORAGE POOL" "${storage_pools[@]}"
    VM_STORAGE="${storage_pools[$storage_idx]}"
  fi

  VM_BRIDGE="vmbr0"
  prompt_default VM_BRIDGE "Network bridge" "$VM_BRIDGE" "NETWORK BRIDGE"

  while ! validate_bridge "$VM_BRIDGE"; do
    whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "INVALID BRIDGE" \
      --msgbox "Bridge '$VM_BRIDGE' does not exist. Please try again." 8 58
    prompt_default VM_BRIDGE "Network bridge" "vmbr0" "NETWORK BRIDGE"
  done

  prompt_integer VM_RAM "RAM (MB)" "1024" 256 131072
  prompt_integer VM_CORES "CPU cores" "1" 1 128
  prompt_integer VM_DISK_GB "Disk size (GB)" "8" 4 10240
  prompt_default VM_USER "VM username" "ubuntu" "VM USER"
  prompt_password VM_PASSWORD "VM password"

  if ! prompt_yes_no "VM Configuration:\n\n  VM ID:     $VM_ID\n  Hostname:  $VM_NAME\n  Storage:   $VM_STORAGE\n  Bridge:    $VM_BRIDGE\n  RAM:       ${VM_RAM} MB\n  Cores:     $VM_CORES\n  Disk:      ${VM_DISK_GB} GB\n  Username:  $VM_USER\n\nProceed with VM creation?" "y" "VM CONFIGURATION SUMMARY"; then
    msg_error "Aborted by user"
  fi
}

#===============================================================================
# Section 5: NUT Configuration Prompts
#===============================================================================

collect_nut_config() {
  prompt_default NUT_UPS_NAME "UPS name (identifier)" "ups" "UPS NAME"
  prompt_default NUT_UPS_DESC "UPS description" "My UPS" "UPS DESCRIPTION"

  NUT_DRIVER="usbhid-ups"

  prompt_default NUT_ADMIN_USER "NUT admin username" "admin" "NUT ADMIN USER"
  prompt_password NUT_ADMIN_PASS "NUT admin password"
  prompt_default NUT_MONITOR_USER "NUT monitor username" "monuser" "NUT MONITOR USER"
  prompt_password NUT_MONITOR_PASS "NUT monitor password"
  prompt_default NUT_LISTEN_ADDR "NUT listen address" "0.0.0.0" "NUT LISTEN ADDRESS"
  prompt_integer NUT_LISTEN_PORT "NUT listen port" "$NUT_DEFAULT_PORT" 1 65535
}

#===============================================================================
# Section 6: Storage Type Detection
#===============================================================================

determine_storage_type() {
  STORAGE_TYPE=$(pvesm status -storage "$VM_STORAGE" | awk 'NR>1 {print $2}')
  case $STORAGE_TYPE in
  nfs | dir | cifs)
    DISK_EXT=".qcow2"
    DISK_REF_PREFIX="${VM_ID}/"
    DISK_IMPORT=(--format qcow2)
    ;;
  btrfs)
    DISK_EXT=".raw"
    DISK_REF_PREFIX="${VM_ID}/"
    DISK_IMPORT=(--format raw)
    ;;
  *)
    DISK_EXT=""
    DISK_REF_PREFIX=""
    DISK_IMPORT=(--format raw)
    ;;
  esac
  DISK0="vm-${VM_ID}-disk-0${DISK_EXT}"
  DISK0_REF="${VM_STORAGE}:${DISK_REF_PREFIX}${DISK0}"
}

#===============================================================================
# Section 7: Cloud Image Download
#===============================================================================

get_img_checksum() {
  curl -fsSL "$UBUNTU_IMG_CHECKSUM_URL" | grep " \*\?${UBUNTU_IMG_NAME}$" | awk '{print $1}'
}

download_cloud_image() {
  local img_path="$IMG_CACHE_DIR/$UBUNTU_IMG_NAME"

  if [[ -f "$img_path" ]]; then
    msg_info "Verifying cached Ubuntu 24.04 cloud image"
    local expected_sha
    expected_sha=$(get_img_checksum)
    if [[ -n "$expected_sha" ]] && echo "${expected_sha}  ${img_path}" | sha256sum -c --status 2>/dev/null; then
      msg_ok "Using cached Ubuntu 24.04 cloud image (checksum verified)"
      return 0
    fi
    msg_info "Cached image checksum mismatch — re-downloading"
    rm -f "$img_path"
  fi

  msg_info "Downloading Ubuntu 24.04 cloud image"
  mkdir -p "$IMG_CACHE_DIR"

  if ! wget -q -c -O "${img_path}.tmp" "$UBUNTU_IMG_URL" 2>/dev/null; then
    msg_error "Failed to download cloud image"
  fi

  mv "${img_path}.tmp" "$img_path"

  msg_info "Verifying SHA-256 checksum"
  local expected_sha
  expected_sha=$(get_img_checksum)
  if [[ -z "$expected_sha" ]]; then
    msg_error "Could not fetch checksum for $UBUNTU_IMG_NAME"
  fi
  if ! echo "${expected_sha}  ${img_path}" | sha256sum -c --status; then
    rm -f "$img_path"
    msg_error "SHA-256 checksum verification failed — image may be corrupt"
  fi

  msg_ok "Downloaded and verified Ubuntu 24.04 cloud image"
}

generate_cloudinit_snippet() {
  local snippet_path="/var/lib/vz/snippets/nut-vm-${VM_ID}-cloudinit.yaml"
  CLOUDINIT_SNIPPET=""

  local cfg_content
  cfg_content=$(awk '$1 == "dir:" && $2 == "local" {f=1} f && /content/{print $2; exit}' /etc/pve/storage.cfg 2>/dev/null || echo "")
  if [[ "$cfg_content" != *snippets* ]]; then
    if [[ -n "$cfg_content" ]]; then
      pvesm set local --content "${cfg_content},snippets" 2>/dev/null || true
    else
      pvesm set local --content "vztmpl,iso,backup,snippets" 2>/dev/null || true
    fi
    cfg_content=$(awk '$1 == "dir:" && $2 == "local" {f=1} f && /content/{print $2; exit}' /etc/pve/storage.cfg 2>/dev/null || echo "")
    if [[ "$cfg_content" != *snippets* ]]; then
      msg_warn "Could not enable snippets on local storage — vendor cloud-init snippet will be skipped"
      msg_warn "VM IP detection may fall back to manual entry after boot"
      return 0
    fi
  fi

  mkdir -p "/var/lib/vz/snippets"

  python3 -c "
import sys
with open(sys.argv[1], 'w') as f:
    f.write('#cloud-config\n')
    f.write('chpasswd:\n')
    f.write('  list: |\n')
    f.write('    ' + sys.argv[2] + ':' + sys.argv[3] + '\n')
    f.write('  expire: False\n')
" "$snippet_path" "$VM_USER" "$VM_PASSWORD"
  chmod 600 "$snippet_path"

  CLOUDINIT_SNIPPET="$snippet_path"
  msg_ok "Generated cloud-init snippet"
}

#===============================================================================
# Section 8: virt-customize Offline Disk Modification
#===============================================================================

virt_customize_image() {
  local img_path="$IMG_CACHE_DIR/$UBUNTU_IMG_NAME"
  WORK_FILE="/tmp/nut-vm-${VM_ID}-work.img"

  msg_info "Preparing working disk image for virt-customize"
  cp -f "$img_path" "$WORK_FILE"

  local tmp_dir
  tmp_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir'" RETURN

  #-----------------------------------------------------------------
  # Write NUT config files locally
  #-----------------------------------------------------------------
  printf 'MODE=netserver\n' >"$tmp_dir/nut.conf"

  printf '[%s]\n  driver = %s\n  port = auto\n  desc = "%s"\n  pollinterval = 5\n  pollonly = 1\n' \
    "$NUT_UPS_NAME" "$NUT_DRIVER" "$NUT_UPS_DESC" >"$tmp_dir/ups.conf"

  printf 'LISTEN %s %s\nMAXAGE 15\nSTATEPATH /var/run/nut\n' \
    "$NUT_LISTEN_ADDR" "$NUT_LISTEN_PORT" >"$tmp_dir/upsd.conf"

  printf '[%s]\n  password = %s\n  actions = SET\n  instcmds = ALL\n\n[%s]\n  password = %s\n  upsmon master\n' \
    "$NUT_ADMIN_USER" "$NUT_ADMIN_PASS" "$NUT_MONITOR_USER" "$NUT_MONITOR_PASS" >"$tmp_dir/upsd.users"

  cat >"$tmp_dir/upsmon.conf" <<'UPSMON_EOF'
MONITOR __UPS_NAME__@localhost:__LISTEN_PORT__ 1 __MONITOR_USER__ __MONITOR_PASS__ master

MINSUPPLIES 1
NOTIFYCMD "/etc/nut/notifycmd.sh"
SHUTDOWNCMD "/sbin/shutdown -h +0"
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
POWERDOWNFLAG /etc/killpower

NOTIFYMSG ONLINE    "UPS %s on line power"
NOTIFYMSG ONBATT    "UPS %s on battery"
NOTIFYMSG LOWBATT   "UPS %s battery is low"
NOTIFYMSG COMMOK    "Communications with UPS %s established"
NOTIFYMSG COMMBAD   "Communications with UPS %s lost"
NOTIFYMSG SHUTDOWN  "UPS %s forcing system shutdown"

NOTIFYFLAG ONLINE   SYSLOG+WALL+EXEC
NOTIFYFLAG ONBATT   SYSLOG+WALL+EXEC
NOTIFYFLAG LOWBATT  SYSLOG+WALL+EXEC
NOTIFYFLAG COMMOK   SYSLOG+WALL+EXEC
NOTIFYFLAG COMMBAD  SYSLOG+WALL+EXEC
NOTIFYFLAG SHUTDOWN SYSLOG+WALL+EXEC
NOTIFYFLAG REPLBATT SYSLOG+WALL+EXEC
NOTIFYFLAG NOCOMM   SYSLOG+WALL+EXEC
NOTIFYFLAG NOPARENT SYSLOG+WALL+EXEC
RBWARNTIME 43200
NOCOMMWARNTIME 300
FINALDELAY 5
UPSMON_EOF

  sed -i \
    -e "s/__UPS_NAME__/$NUT_UPS_NAME/g" \
    -e "s/__LISTEN_PORT__/$NUT_LISTEN_PORT/g" \
    -e "s/__MONITOR_USER__/$NUT_MONITOR_USER/g" \
    -e "s/__MONITOR_PASS__/$NUT_MONITOR_PASS/g" \
    "$tmp_dir/upsmon.conf"

  cat >"$tmp_dir/notifycmd.sh" <<'NOTIFY_EOF'
#!/bin/bash
LOGFILE="/var/log/nut/notifycmd.log"
HOOKDIR="/etc/nut/notify.d"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
UPSNAME_BARE="${UPSNAME%%@*}"
echo "[$TIMESTAMP] UPS=$UPSNAME EVENT=$NOTIFYTYPE" >>"$LOGFILE"
[[ -x "$HOOKDIR/${UPSNAME_BARE}_${NOTIFYTYPE}.sh" ]] && "$HOOKDIR/${UPSNAME_BARE}_${NOTIFYTYPE}.sh" >>"$LOGFILE" 2>&1
NOTIFY_EOF

  #-----------------------------------------------------------------
  # Write nut-detect oneshot script + systemd service
  #-----------------------------------------------------------------
  cat >"$tmp_dir/nut-detect.sh" <<'DETECT_EOF'
#!/bin/bash
nut-scanner -U > /tmp/nut-scan.txt
DRIVER=$(awk -F'"' '/driver/ {print $2; exit}' /tmp/nut-scan.txt)
PORT=$(awk -F'"' '/port/ {print $2; exit}' /tmp/nut-scan.txt)
VENDORID=$(awk -F'"' '/vendorid/ {print $2; exit}' /tmp/nut-scan.txt)
PRODUCTID=$(awk -F'"' '/productid/ {print $2; exit}' /tmp/nut-scan.txt)

{
  printf "[%s]\n" "__UPS_NAME__"
  printf "  driver = %s\n" "${DRIVER:-usbhid-ups}"
  printf "  port = %s\n" "${PORT:-auto}"
  [[ -n "$VENDORID" ]] && printf "  vendorid = %s\n" "$VENDORID"
  [[ -n "$PRODUCTID" ]] && printf "  productid = %s\n" "$PRODUCTID"
  printf "  desc = \"%s\"\n" "__UPS_DESC__"
  printf "  pollinterval = 5\n"
  printf "  pollonly = 1\n"
} > /etc/nut/ups.conf

chown root:nut /etc/nut/ups.conf
chmod 640 /etc/nut/ups.conf
systemctl restart nut-driver nut-server nut-monitor
touch /var/lib/nut/driver-detected
DETECT_EOF

  sed -i \
    -e "s/__UPS_NAME__/$NUT_UPS_NAME/g" \
    -e "s/__UPS_DESC__/$NUT_UPS_DESC/g" \
    "$tmp_dir/nut-detect.sh"

  cat >"$tmp_dir/nut-detect.service" <<'SERVICE_EOF'
[Unit]
Description=Auto-detect UPS driver on first boot
After=multi-user.target
ConditionPathExists=!/var/lib/nut/driver-detected

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nut-detect.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_EOF

  #-----------------------------------------------------------------
  # Build virt-customize command
  #-----------------------------------------------------------------
  local vc_cmd=(virt-customize -a "$WORK_FILE")

  [[ "${VERBOSE:-}" == "yes" ]] && vc_cmd+=(-v)

  # Install packages
  vc_cmd+=(--install "qemu-guest-agent,nut-server,nut-client,python3-venv,python3-pip,curl,usbutils")

  # Update packages
  vc_cmd+=(--update)
  vc_cmd+=(--run-command "DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq")

  # Upload NUT configs
  vc_cmd+=(--upload "$tmp_dir/nut.conf:/etc/nut/nut.conf")
  vc_cmd+=(--upload "$tmp_dir/ups.conf:/etc/nut/ups.conf")
  vc_cmd+=(--upload "$tmp_dir/upsd.conf:/etc/nut/upsd.conf")
  vc_cmd+=(--upload "$tmp_dir/upsd.users:/etc/nut/upsd.users")
  vc_cmd+=(--upload "$tmp_dir/upsmon.conf:/etc/nut/upsmon.conf")

  # Upload nut-detect script + service
  vc_cmd+=(--upload "$tmp_dir/nut-detect.sh:/usr/local/bin/nut-detect.sh")
  vc_cmd+=(--run-command "chmod +x /usr/local/bin/nut-detect.sh")
  vc_cmd+=(--upload "$tmp_dir/nut-detect.service:/etc/systemd/system/nut-detect.service")

  # Upload notifycmd sample script
  vc_cmd+=(--upload "$tmp_dir/notifycmd.sh:/etc/nut/notifycmd.sh")
  vc_cmd+=(--run-command "chmod 750 /etc/nut/notifycmd.sh && chown root:nut /etc/nut/notifycmd.sh")
  vc_cmd+=(--run-command "mkdir -p /etc/nut/notify.d /var/log/nut")
  vc_cmd+=(--run-command "chown root:nut /etc/nut/notify.d && chmod 750 /etc/nut/notify.d")
  vc_cmd+=(--run-command "chown nut:nut /var/log/nut")

  # Set permissions
  vc_cmd+=(--run-command 'chown root:nut /etc/nut/*.conf && chmod 640 /etc/nut/*.conf')
  vc_cmd+=(--run-command 'mkdir -p /var/run/nut && chown nut:nut /var/run/nut')

  # Library symlinks for nut-scanner
  vc_cmd+=(--run-command 'ln -sf /usr/lib/x86_64-linux-gnu/libusb-1.0.so.0 /usr/lib/x86_64-linux-gnu/libusb-1.0.so || true')
  vc_cmd+=(--run-command 'ln -sf /usr/lib/x86_64-linux-gnu/libnetsnmp.so.40 /usr/lib/x86_64-linux-gnu/libnetsnmp.so || true')
  vc_cmd+=(--run-command 'ln -sf /usr/lib/x86_64-linux-gnu/libneon-gnutls.so.27 /usr/lib/x86_64-linux-gnu/libneon.so || true')
  vc_cmd+=(--run-command 'ln -sf /usr/lib/x86_64-linux-gnu/libavahi-client.so.3 /usr/lib/x86_64-linux-gnu/libavahi-client.so || true')
  vc_cmd+=(--run-command 'ln -sf /usr/lib/x86_64-linux-gnu/libfreeipmi.so.17 /usr/lib/x86_64-linux-gnu/libfreeipmi.so || true')
  vc_cmd+=(--run-command 'ln -sf /usr/lib/x86_64-linux-gnu/libupsclient.so.6 /usr/lib/x86_64-linux-gnu/libupsclient.so || true')

  # Enable services
  vc_cmd+=(--run-command 'systemctl enable qemu-guest-agent')
  vc_cmd+=(--run-command 'systemctl enable nut-detect')

  # Enable NUT services based on available systemd units
  vc_cmd+=(--run-command '
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable nut-server 2>/dev/null || true
    systemctl enable nut-monitor 2>/dev/null || true
    if [ -f /lib/systemd/system/nut-driver-enumerator.service ]; then
      systemctl enable nut-driver-enumerator.service 2>/dev/null || true
      systemctl enable nut-driver-enumerator.path 2>/dev/null || true
      systemctl enable nut-driver-target 2>/dev/null || true
    elif [ -f /lib/systemd/system/nut-driver@.service ]; then
      systemctl enable nut-driver@'"$NUT_UPS_NAME"' 2>/dev/null || true
    else
      systemctl enable nut-driver 2>/dev/null || true
    fi
  ')

  # nut-admin install (graceful failure)
  local tarball_url="${NUT_ADMIN_URL_PREFIX:-${NUT_ADMIN_RELEASES_URL}}/nut-admin.tar.gz"
  # shellcheck disable=SC2016
  vc_cmd+=(--run-command '
    TARBALL_URL="'"$tarball_url"'"
    curl -fsSL "$TARBALL_URL" -o /tmp/nut-admin.tar.gz && \
    mkdir -p /opt/nut-admin && tar -xzf /tmp/nut-admin.tar.gz -C /opt/nut-admin/ && \
    python3 -m venv /opt/nut-admin/venv && \
    /opt/nut-admin/venv/bin/pip install -q -r /opt/nut-admin/requirements.txt && \
    cp /opt/nut-admin/nut-admin.service /etc/systemd/system/ && \
    systemctl enable nut-admin || \
    echo "[WARN] NUT Admin installation failed, continuing"
  ')

  # System bootstrap
  vc_cmd+=(--hostname "$VM_NAME")
  vc_cmd+=(--run-command 'rm -f /etc/machine-id && touch /etc/machine-id')
  vc_cmd+=(--run-command 'systemctl enable ssh')

  local vcout="/tmp/nut-vm-${VM_ID}-virt-customize.log"
  msg_info "Running virt-customize (this may take a few minutes)..."
  if ! "${vc_cmd[@]}" >"$vcout" 2>&1; then
    cat "$vcout"
    rm -f "$vcout" "$WORK_FILE"
    msg_error "virt-customize failed"
  fi
  [[ "${VERBOSE:-}" == "yes" ]] && cat "$vcout"
  rm -f "$vcout"

  msg_ok "Disk image customized successfully"
}

#===============================================================================
# Section 9: VM Creation
#===============================================================================

create_vm() {
  generate_cloudinit_snippet
  determine_storage_type

  msg_info "Creating VM $VM_ID"
  $STD qm create "$VM_ID" \
    --name "$VM_NAME" \
    --memory "$VM_RAM" \
    --cores "$VM_CORES" \
    --net0 "virtio,bridge=$VM_BRIDGE" \
    --ostype l26 \
    --agent enabled=1 \
    --serial0 socket \
    --vga serial0 \
    --onboot 1 \
    --tags 'community-script;nut;network;ups'
  msg_ok "Created VM $VM_ID"

  msg_info "Importing customized disk image"
  [[ "${VERBOSE:-}" == "yes" ]] && set -x
  if ! $STD qm importdisk "$VM_ID" "$WORK_FILE" "$VM_STORAGE" "${DISK_IMPORT[@]}"; then
    msg_error "Failed to import disk"
  fi
  [[ "${VERBOSE:-}" == "yes" ]] && set +x
  rm -f "$WORK_FILE"
  WORK_FILE=""
  msg_ok "Imported disk image"

  msg_info "Configuring VM"
  $STD qm set "$VM_ID" --scsihw virtio-scsi-pci
  $STD qm set "$VM_ID" --scsi0 "${DISK0_REF}"
  $STD qm resize "$VM_ID" scsi0 "${VM_DISK_GB}G"
  $STD qm set "$VM_ID" --boot c --bootdisk scsi0

  # shellcheck disable=SC2034
  CLOUDINIT_SSH_KEYS=""
  setup_cloud_init "$VM_ID" "$VM_STORAGE" "$VM_NAME" "yes" "$VM_USER"
  if [[ -n "${CLOUDINIT_SNIPPET:-}" ]]; then
    $STD qm set "$VM_ID" --cicustom "vendor=local:snippets/nut-vm-${VM_ID}-cloudinit.yaml"
  fi

  msg_ok "VM configured"
}

#===============================================================================
# Section 10: USB Detection + Passthrough
#===============================================================================

prompt_ups_manual_entry() {
  local reason="$1" title="$2"
  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --yesno "$reason" 8 58; then
    UPS_VENDOR_PRODUCT=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "UPS DEVICE" \
      --inputbox "Enter UPS vendor:product (e.g. 051d:0002):" \
      8 58 "" 3>&1 1>&2 2>&3) || true
  fi
}

detect_ups() {
  if ! command -v lsusb &>/dev/null; then
    msg_warn "lsusb not found — USB detection unavailable"
    prompt_ups_manual_entry "lsusb not available. Enter UPS vendor:product manually?" "USB DETECTION"
    return
  fi

  msg_info "Scanning for USB UPS devices"

  local lsusb_output
  lsusb_output=$(timeout 10 lsusb 2>/dev/null) || {
    msg_warn "USB device detection timed out"
    prompt_ups_manual_entry "lsusb timed out. Enter UPS vendor:product manually?" "USB TIMEOUT"
    return
  }

  msg_ok "USB scan complete"

  local usb_devices=()
  local device_info=()
  local i=0

  while IFS= read -r line; do
    if [[ "$line" =~ Bus[[:space:]]([0-9]+)[[:space:]]Device[[:space:]]([0-9]+).+ID[[:space:]]([0-9a-f]{4}):([0-9a-f]{4})[[:space:]]*(.*) ]]; then
      local bus="${BASH_REMATCH[1]}"
      local device="${BASH_REMATCH[2]}"
      local vendor="${BASH_REMATCH[3]}"
      local product="${BASH_REMATCH[4]}"
      local name="${BASH_REMATCH[5]}"
      local vendor_name="${UPS_VENDORS[$vendor]:-Unknown}"

      if [[ -n "${UPS_VENDORS[$vendor]:-}" ]] || [[ "$name" =~ [Uu][Pp][Ss] ]]; then
        usb_devices+=("$vendor:$product")
        device_info+=("Bus $bus Device $device - $vendor_name ($vendor:$product) - $name")
        ((++i))
      fi
    fi
  done <<<"$lsusb_output"

  UPS_DEVICE_COUNT=$i

  if [[ $UPS_DEVICE_COUNT -eq 0 ]]; then
    msg_warn "No USB UPS devices detected"
    prompt_ups_manual_entry "No UPS devices found. Enter vendor:product manually?" "NO UPS FOUND"
    return
  elif [[ $UPS_DEVICE_COUNT -eq 1 ]]; then
    if whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "UPS DETECTED" \
      --yesno "Use this device?\n\n${device_info[0]}" 10 70; then
      UPS_VENDOR_PRODUCT="${usb_devices[0]}"
      UPS_BUS_PORT=""
    fi
  else
    local choice
    prompt_menu choice "SELECT UPS DEVICE" "${device_info[@]}"
    UPS_VENDOR_PRODUCT="${usb_devices[$choice]}"

    local duplicates=0
    local dev
    for dev in "${usb_devices[@]}"; do
      [[ "$dev" == "$UPS_VENDOR_PRODUCT" ]] && ((++duplicates))
    done

    if [[ $duplicates -gt 1 ]]; then
      msg_warn "Multiple devices with same ID — using bus-port notation"
      if [[ "${device_info[$choice]}" =~ Bus[[:space:]]([0-9]+)[[:space:]]Device[[:space:]]([0-9]+) ]]; then
        local bus="${BASH_REMATCH[1]}"
        local devnum="${BASH_REMATCH[2]}"
        local port="1"
        local sysdev
        for sysdev in /sys/bus/usb/devices/*/; do
          local dev_bus dev_num devpath
          dev_bus=$(cat "${sysdev}busnum" 2>/dev/null) || continue
          dev_num=$(cat "${sysdev}devnum" 2>/dev/null) || continue
          if [[ "$((10#$dev_bus))" == "$((10#$bus))" && "$((10#$dev_num))" == "$((10#$devnum))" ]]; then
            devpath=$(basename "$sysdev")
            if [[ "$devpath" =~ ^[0-9]+-([0-9]+) ]]; then
              port="${BASH_REMATCH[1]}"
            fi
            break
          fi
        done
        UPS_BUS_PORT="${bus}-${port}"
      fi
    fi
  fi
}

setup_usb_passthrough() {
  if [[ -z "${UPS_VENDOR_PRODUCT:-}" ]]; then
    msg_warn "No UPS device selected, skipping USB passthrough"
    return
  fi

  msg_info "Setting up USB passthrough for $UPS_VENDOR_PRODUCT"

  local usb_param
  if [[ -n "${UPS_BUS_PORT:-}" ]]; then
    usb_param="host=${UPS_BUS_PORT}"
  else
    usb_param="host=${UPS_VENDOR_PRODUCT}"
  fi

  if $STD qm set "$VM_ID" --usb0 "$usb_param"; then
    msg_ok "USB passthrough configured"
  else
    msg_warn "Failed to set USB passthrough (continuing anyway)"
  fi
}

#===============================================================================
# Section 11: VM Boot + Guest Agent IP Detection
#===============================================================================

start_vm() {
  msg_info "Starting VM $VM_ID"

  if ! $STD qm start "$VM_ID"; then
    msg_error "Failed to start VM"
  fi

  msg_ok "VM started"
}

get_vm_ip() {
  # Wait for the qemu-guest-agent installed by virt-customize.
  # Once the VM boots, the agent reports IPs directly.
  local ip="" elapsed=0 max_wait=300

  if [[ -n "${VM_IP:-}" ]]; then
    msg_ok "VM IP address (from VM_IP env): $VM_IP"
    return 0
  fi

  msg_info "Waiting for VM guest agent (~1-3 min on first boot)"

  while [[ $elapsed -lt $max_wait ]]; do
    ip=$(qm guest cmd "$VM_ID" network-get-interfaces 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict):
        ifaces = data.get('result', [])
    else:
        ifaces = data
    for iface in ifaces:
        for a in iface.get('ip-addresses', []):
            addr = a.get('ip-address', '')
            if (a.get('ip-address-type') == 'ipv4'
                    and not addr.startswith('127.')
                    and not addr.startswith('169.254.')):
                print(addr)
                sys.exit(0)
except Exception:
    pass
" 2>/dev/null) || true

    if [[ -n "$ip" ]]; then
      VM_IP="$ip"
      msg_ok "VM IP address: $VM_IP"
      return 0
    fi

    sleep 15
    elapsed=$((elapsed + 15))
    [[ $((elapsed % 60)) -eq 0 ]] && msg_info "Still waiting for guest agent (${elapsed}s elapsed)"
  done

  msg_warn "Guest agent did not respond after ${max_wait}s"

  VM_IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "VM IP ADDRESS" \
    --inputbox "Enter VM IP address manually:" \
    8 58 "" 3>&1 1>&2 2>&3) || msg_error "No IP address provided"
  if [[ -z "$VM_IP" ]]; then
    msg_error "No IP address provided"
  fi
}

#===============================================================================
# Section 12: Final Summary Output
#===============================================================================

print_summary() {
  local summary_text
  summary_text="NUT VM Setup Complete!\n\n"
  summary_text+="  VM ID:      $VM_ID\n"
  summary_text+="  VM Name:    $VM_NAME\n"
  summary_text+="  VM IP:      $VM_IP\n\n"
  summary_text+="  NUT Server: ${VM_IP}:${NUT_LISTEN_PORT}\n"
  summary_text+="  UPS Name:   $NUT_UPS_NAME\n\n"
  summary_text+="  Test command:\n"
  summary_text+="    upsc ${NUT_UPS_NAME}@${VM_IP}\n\n"
  summary_text+="  Client upsmon.conf:\n"
  summary_text+="    MONITOR ${NUT_UPS_NAME}@${VM_IP}:${NUT_LISTEN_PORT} 1 ${NUT_MONITOR_USER} PASS slave\n\n"
  summary_text+="  Note: On first boot the nut-detect service scans the USB UPS\n"
  summary_text+="        and auto-configures the correct driver."

  if [[ "$AUTO_GENERATE_PASSWORDS" == "true" && ${#GENERATED_PASSWORDS[@]} -gt 0 ]]; then
    summary_text+="\n\n⚠ AUTO-GENERATED PASSWORDS (save these!):\n"
    for pwd_entry in "${GENERATED_PASSWORDS[@]}"; do
      summary_text+="  $pwd_entry\n"
    done
  fi

  whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "SETUP COMPLETE" \
    --msgbox "$summary_text" 26 72

  echo
  echo -e "${GN}${CM}NUT VM setup completed successfully!${CL}"
  echo -e "${INFO}${YW}VM IP:      ${BGN}${VM_IP}${CL}"
  echo -e "${INFO}${YW}NUT Server: ${BGN}${VM_IP}:${NUT_LISTEN_PORT}${CL}"
  echo -e "${INFO}${YW}Test with:  ${BGN}upsc ${NUT_UPS_NAME}@${VM_IP}${CL}"

  if [[ "$AUTO_GENERATE_PASSWORDS" == "true" && ${#GENERATED_PASSWORDS[@]} -gt 0 ]]; then
    echo
    echo -e "${YW}⚠ Auto-generated passwords:${CL}"
    for pwd_entry in "${GENERATED_PASSWORDS[@]}"; do
      echo -e "  ${DGN}${pwd_entry}${CL}"
    done
  fi

  if [[ "${VERBOSE:-}" == "yes" && ${#SCRIPT_ERROR_LOG[@]} -gt 0 ]]; then
    echo
    echo -e "${YW}Debug - Script error/warning log:${CL}"
    for entry in "${SCRIPT_ERROR_LOG[@]}"; do
      echo -e "  ${entry}"
    done
  fi
  echo
}

#===============================================================================
# Main
#===============================================================================

main() {
  case "${1:-}" in
  --help | -h)
    echo "Usage: $0 [--debug|--version|--help]"
    echo
    echo "Creates an Ubuntu 24.04 VM on Proxmox and configures NUT netserver."
    echo "Uses virt-customize for offline disk image setup (no SSH)."
    echo
    echo "Options:"
    echo "  --help, -h      Show this help message"
    echo "  --version       Show version"
    echo "  --debug, -d     Enable debug tracing (set -x) and show all command output"
    echo
    echo "Environment:"
    echo "  VERBOSE=yes     Show full command output"
    exit 0
    ;;
  --version)
    echo "nut-vm.sh v${SCRIPT_VERSION}"
    exit 0
    ;;
  --debug | -d)
    VERBOSE=yes
    set -x
    ;;
  esac

  header_info
  color
  variables
  catch_errors

  if [[ "${VERBOSE:-}" == "yes" ]]; then
    STD=""
    set -x
  fi

  echo -e "${BOLD}  v${SCRIPT_VERSION}${CL}\n"

  check_root
  check_proxmox
  check_dependencies
  check_virt_customize
  check_architecture

  prompt_autogenerate_passwords
  collect_vm_config
  collect_nut_config

  if ! prompt_yes_no "NUT Configuration:\n\n  UPS Name:     $NUT_UPS_NAME\n  UPS Desc:     $NUT_UPS_DESC\n  Driver:       $NUT_DRIVER\n  Admin User:   $NUT_ADMIN_USER\n  Monitor User: $NUT_MONITOR_USER\n  Listen:       $NUT_LISTEN_ADDR:$NUT_LISTEN_PORT\n\nProceed with VM and NUT setup?" "y" "NUT CONFIGURATION SUMMARY"; then
    msg_error "Aborted by user"
  fi

  download_cloud_image
  virt_customize_image
  create_vm
  detect_ups
  setup_usb_passthrough
  start_vm

  get_vm_ip

  print_summary
}

cleanup_work_file() {
  [[ -n "${WORK_FILE:-}" ]] && rm -f "$WORK_FILE"
}

trap 'cleanup_work_file' EXIT
trap '[[ -n "${SPINNER_PID:-}" ]] && kill "${SPINNER_PID:-}" 2>/dev/null; printf "\e[?25h"; cleanup_work_file; echo -e "\n${RD}Interrupted${CL}"; exit 130' INT TERM

main "$@"

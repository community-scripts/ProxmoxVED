#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

header_info
echo -e "Loading..."
GEN_MAC=$(echo '00 60 2f'$(od -An -N3 -t xC /dev/urandom) | sed -e 's/ /:/g' | tr '[:lower:]' '[:upper:]')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
APP="MikroTik RouterOS"
APP_TYPE="vm"
NSAPP="mikrotik-routeros"
var_os="mikrotik"
var_version=" "
DISK_SIZE="1G"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Mikrotik RouterOS CHR VM" --yesno "This will create a Mikrotik RouterOS CHR VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x, 9.0 and 9.2

function default_settings() {
  vm_apply_machine_type "i440fx"
  VMID=$(get_valid_nextid)
  DISK_SIZE="8G"
  DISK_CACHE=""
  HN="mikrotik-routeros-chr"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="512"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  CLOUD_INIT="no"
  METHOD="default"
  vm_echo_default_settings
}

function get_mikrotik_version() {
  local mode="$1"
  local rss_url
  local tree_name

  case "$mode" in
  s) rss_url="https://cdn.mikrotik.com/routeros/latest-stable.rss" ;;
  d) rss_url="https://cdn.mikrotik.com/routeros/latest-development.rss" ;;
  l) rss_url="https://cdn.mikrotik.com/routeros/latest-long-term.rss" ;;
  t) rss_url="https://cdn.mikrotik.com/routeros/latest-testing.rss" ;;
  *) return 0 ;;
  esac

  local rss_content
  rss_content=$(curl -fsSL $rss_url 2>/dev/null)
  if [ -n "$rss_content" ]; then
    local version
    version=$(echo "$rss_content" | grep -oP '<title>RouterOS \K[0-9.]+(?= \[)' 2>/dev/null || echo "$rss_content" | sed -n 's/.*<title>RouterOS \([0-9.]\+\) \[.*/\1/p' 2>/dev/null)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+ ]]; then
      echo "$version"
      return 0
    fi
  fi

  case "$mode" in
  s) tree_name="Stable release tree" ;;
  d) tree_name="Development release tree" ;;
  l) tree_name="Long-term release tree" ;;
  t) tree_name="Testing release tree" ;;
  esac

  local html
  html=$(curl -fsSL "https://mikrotik.com/download/changelogs" 2>/dev/null)
  if [ -n "$html" ]; then
    local start_line
    start_line=$(echo "$html" | grep -n "$tree_name" | cut -d: -f1 | head -n1)
    if [[ "$start_line" =~ ^[0-9]+$ ]]; then
      local line
      line=$(echo "$html" | tail -n +"$start_line" | grep -m 1 -E "c-(stable|longTerm|testing|development)-v|RouterOS [0-9]+\.[0-9]+" 2>/dev/null)

      local version
      version=$(echo "$line" | sed -n 's/.*c-[^"]*-v\([0-9_.a-zA-Z-]\+\).*/\1/p' | tr '_' '.' 2>/dev/null)
      [ -z "$version" ] && version=$(echo "$line" | grep -oP 'RouterOS \K[0-9]+\.[0-9]+(\.[0-9]+)?' 2>/dev/null)

      if [[ "$version" =~ ^[0-9]+\.[0-9]+ ]]; then
        echo "$version"
        return 0
      fi
    fi
  fi

  for minor in $(seq 50 -1 15); do
    local test_version="7.${minor}"
    if curl -fsSL -I "https://download.mikrotik.com/routeros/${test_version}/chr-${test_version}.img.zip" 2>/dev/null | grep -q "200 OK"; then
      echo "$test_version"
      return 0
    fi
  done

  return 0
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "i440fx"
  vm_prompt_disk_size "8G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "mikrotik-routeros-chr"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "512"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a MikroTik RouterOS VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a MikroTik RouterOS VM using the above advanced settings${CL}"
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
msg_info "Getting URL for Latest Mikrotik RouterOS CHR Disk Image"

MIK_VER=$(get_mikrotik_version s)

if [ -n "$MIK_VER" ]; then
  msg_ok "Latest stable version: ${CL}${BL}$MIK_VER${CL}."
else
  msg_error "Could not get latest version"
  msg_ok "Defaulting to version 7.20"
  MIK_VER="7.20"
fi

URL=https://download.mikrotik.com/routeros/$MIK_VER/chr-$MIK_VER.img.zip

sleep 2
msg_ok "Downloading from URL: ${CL}${BL}${URL}${CL}"
# A mirror serving an error page returns 200, so size decides whether this
# is an image. Anything real here is far above 5 MB.
vm_fetch_image "$URL" "$(basename "$URL")" --min-bytes $((5 * 1024 * 1024)) || exit 1
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}$FILE${CL}"
msg_info "Extracting Mikrotik RouterOS CHR Disk Image"
gunzip -f -S .zip $FILE
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  ;;
zfspool)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  ;;
esac

DISK_VAR="vm-${VMID}-disk-0${DISK_EXT:-}"
DISK_REF="${STORAGE}:${DISK_REF:-}${DISK_VAR:-}"

msg_ok "Extracted Mikrotik RouterOS CHR Disk Image"
msg_info "Creating Mikrotik RouterOS CHR VM"
qm create $VMID -tablet 0 -localtime 1 -cores $CORE_COUNT -memory $RAM_SIZE -name $HN \
  -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU \
  -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
qm importdisk $VMID ${FILE%.*} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -scsi0 "$DISK_REF" \
  -boot order=scsi0 >/dev/null

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://community-scripts.org' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Mikrotik RouterOS CHR</h2>

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
qm set $VMID -description "$DESCRIPTION" >/dev/null
if [ -n "$DISK_SIZE" ]; then
  msg_info "Resizing disk to $DISK_SIZE GB"
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
else
  msg_info "Using default disk size of $DEFAULT_DISK_SIZE GB"
  qm resize $VMID scsi0 ${DEFAULT_DISK_SIZE} >/dev/null
fi

msg_ok "Mikrotik RouterOS CHR VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Mikrotik RouterOS CHR VM"
  qm start $VMID
  msg_ok "Started Mikrotik RouterOS CHR VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

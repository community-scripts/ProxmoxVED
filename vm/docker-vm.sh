#!/usr/bin/env bash
# Docker VM (Debian/Ubuntu Cloud-Image) für Proxmox VE 8/9
#
# PVE 8: direct inject via virt-customize
# PVE 9: Cloud-Init (user-data via local:snippets)
#
# Copyright (c) 2021-2025 community-scripts ORG
# Author: thost96 (thost96) | Co-Author: michelroegl-brunner
# Refactor (q35 + PVE9 cloud-init + Robustheit): MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -euo pipefail

# ---- API-Funktionen laden ----------------------------------------------------
source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/api.func)"

# ---- UI / Farben -------------------------------------------------------------
YW=$'\033[33m'; BL=$'\033[36m'; RD=$'\033[01;31m'; GN=$'\033[1;92m'; DGN=$'\033[32m'; CL=$'\033[m'
BOLD=$'\033[1m'; BFR=$'\\r\\033[K'; TAB="  "
CM="${TAB}✔️${TAB}${CL}"; CROSS="${TAB}✖️${TAB}${CL}"; INFO="${TAB}💡${TAB}${CL}"
OSI="${TAB}🖥️${TAB}${CL}"; DISKSIZE="${TAB}💾${TAB}${CL}"; CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"; CONTAINERID="${TAB}🆔${TAB}${CL}"; HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"; GATEWAY="${TAB}🌐${TAB}${CL}"; DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"; VLANTAG="${TAB}🏷️${TAB}${CL}"; CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"

# ---- Spinner-/Msg-Funktionen (kompakt) ---------------------------------------
msg_info()  { echo -ne "${TAB}${YW}$1${CL}"; }
msg_ok()    { echo -e  "${BFR}${CM}${GN}$1${CL}"; }
msg_error() { echo -e  "${BFR}${CROSS}${RD}$1${CL}"; }

# ---- Header ------------------------------------------------------------------
header_info() {
  clear
  cat <<"EOF"
    ____             __                _    ____  ___
   / __ \____  _____/ /_____  _____   | |  / /  |/  /
  / / / / __ \/ ___/ //_/ _ \/ ___/   | | / / /|_/ /
 / /_/ / /_/ / /__/ ,< /  __/ /       | |/ / /  / /
/_____/\____/\___/_/|_|\___/_/        |___/_/  /_/

EOF
}
header_info; echo -e "\n Loading..."

trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap 'cleanup' EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

error_handler() {
  local ec=$? ln="$1" cmd="$2"
  msg_error "in line ${ln}: exit code ${ec}: while executing: ${YW}${cmd}${CL}"
  post_update_to_api "failed" "${cmd}"
  cleanup_vmid || true
  exit "$ec"
}

cleanup_vmid() {
  if [[ -n "${VMID:-}" ]] && qm status "$VMID" &>/dev/null; then
    qm stop "$VMID" &>/dev/null || true
    qm destroy "$VMID" &>/dev/null || true
  fi
}

TEMP_DIR="$(mktemp -d)"
cleanup() {
  popd >/dev/null 2>&1 || true
  rm -rf "$TEMP_DIR"
  post_update_to_api "done" "none"
}

pushd "$TEMP_DIR" >/dev/null

# ---- Sanity Checks -----------------------------------------------------------
check_root() { if [[ "$(id -u)" -ne 0 ]]; then msg_error "Run as root."; exit 1; fi; }
arch_check() { [[ "$(dpkg --print-architecture)" = "amd64" ]] || { msg_error "ARM/PiMox nicht unterstützt."; exit 1; }; }
pve_check() {
  local ver; ver="$(pveversion | awk -F'/' '{print $2}' | cut -d'-' -f1)"
  case "$ver" in
    8.*|9.*) : ;;
    *) msg_error "Unsupported Proxmox VE: ${ver} (need 8.x or 9.x)"; exit 1 ;;
  esac
}

check_root; arch_check; pve_check;

# ---- Defaults / UI Vorbelegung ----------------------------------------------
GEN_MAC="02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/:$//')"
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
NSAPP="docker-vm"
THIN="discard=on,ssd=1,"
FORMAT=",efitype=4m"
DISK_CACHE=""
DISK_SIZE="10G"
HN="docker"
CPU_TYPE=""
CORE_COUNT="2"
RAM_SIZE="4096"
BRG="vmbr0"
MAC="$GEN_MAC"
VLAN=""
MTU=""
START_VM="yes"
METHOD="default"
var_os="debian"
var_version="12"

# ---- Helper: VMID-Find -------------------------------------------------------
get_valid_nextid() {
  local id; id=$(pvesh get /cluster/nextid)
  while :; do
    if [[ -f "/etc/pve/qemu-server/${id}.conf" || -f "/etc/pve/lxc/${id}.conf" ]]; then id=$((id+1)); continue; fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${id}($|[-_])"; then id=$((id+1)); continue; fi
    break
  done
  echo "$id"
}

# ---- Msg Wrapper -------------------------------------------------------------
exit-script() { clear; echo -e "\n${CROSS}${RD}User exited script${CL}\n"; exit 1; }

default_settings() {
  VMID="$(get_valid_nextid)"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${GN}${VMID}${CL}"
  echo -e "${OSI}${BOLD}${DGN}CPU Model: ${GN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${GN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${GN}${RAM_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${GN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${GN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${GN}${HN}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${GN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${GN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${GN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${GN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${GN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above default settings${CL}"
}

advanced_settings() {
  METHOD="advanced"
  [[ -z "${VMID:-}" ]] && VMID="$(get_valid_nextid)"
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 "$VMID" \
      --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      [[ -z "$VMID" ]] && VMID="$(get_valid_nextid)"
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"; sleep 1.5; continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${GN}$VMID${CL}"
      break
    else exit-script; fi
  done

  echo -e "${OSI}${BOLD}${DGN}Machine Type: ${GN}q35${CL}"

  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" \
      --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE="$(echo "$DISK_SIZE" | tr -d ' ')"; [[ "$DISK_SIZE" =~ ^[0-9]+$ ]] && DISK_SIZE="${DISK_SIZE}G"
    [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]] || { msg_error "Invalid Disk Size"; exit-script; }
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${GN}$DISK_SIZE${CL}"
  else exit-script; fi

  if DISK_CACHE_SEL=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" \
      --radiolist "Choose" --cancel-button Exit-Script 10 58 2 "0" "None (Default)" ON "1" "Write Through" OFF \
      3>&1 1>&2 2>&3); then
    if [[ "$DISK_CACHE_SEL" = "1" ]]; then DISK_CACHE="cache=writethrough,"; echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${GN}Write Through${CL}"
    else DISK_CACHE=""; echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${GN}None${CL}"
    fi
  else exit-script; fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 "$HN" \
      --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [[ -z "$VM_NAME" ]] && VM_NAME="docker"; HN="$(echo "${VM_NAME,,}" | tr -d ' ')"
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${GN}$HN${CL}"
  else exit-script; fi

  if CPU_TYPE_SEL=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" \
      --radiolist "Choose" --cancel-button Exit-Script 10 58 2 "0" "KVM64 (Default)" ON "1" "Host" OFF \
      3>&1 1>&2 2>&3); then
    if [[ "$CPU_TYPE_SEL" = "1" ]]; then CPU_TYPE=" -cpu host"; echo -e "${OSI}${BOLD}${DGN}CPU Model: ${GN}Host${CL}"
    else CPU_TYPE=""; echo -e "${OSI}${BOLD}${DGN}CPU Model: ${GN}KVM64${CL}"
    fi
  else exit-script; fi

  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 "$CORE_COUNT" \
      --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [[ -z "$CORE_COUNT" ]] && CORE_COUNT="2"
    echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${GN}$CORE_COUNT${CL}"
  else exit-script; fi

  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 "$RAM_SIZE" \
      --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [[ -z "$RAM_SIZE" ]] && RAM_SIZE="2048"
    echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${GN}$RAM_SIZE${CL}"
  else exit-script; fi

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 "$BRG" \
      --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [[ -z "$BRG" ]] && BRG="vmbr0"
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${GN}$BRG${CL}"
  else exit-script; fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 "$MAC" \
      --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [[ -z "$MAC1" ]] && MAC1="$GEN_MAC"; MAC="$MAC1"
    echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${GN}$MAC${CL}"
  else exit-script; fi

  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set VLAN (blank = default)" 8 58 "" \
      --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [[ -z "$VLAN1" ]]; then VLAN1="Default"; VLAN=""; else VLAN=",tag=$VLAN1"; fi
    echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${GN}$VLAN1${CL}"
  else exit-script; fi

  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Interface MTU Size (blank = default)" 8 58 "" \
      --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [[ -z "$MTU1" ]]; then MTU1="Default"; MTU=""; else MTU=",mtu=$MTU1"; fi
    echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${GN}$MTU1${CL}"
  else exit-script; fi

  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" \
      --yesno "Start VM when completed?" 10 58; then START_VM="yes"; else START_VM="no"; fi
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${GN}${START_VM}${CL}"

  if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" \
      --yesno "Ready to create a Docker VM?" --no-button Do-Over 10 58; then
    header_info; echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"; advanced_settings
  else
    echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above advanced settings${CL}"
  fi
}

start_script() {
  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" \
       --yesno "Use Default Settings?" --no-button Advanced 10 58; then
    header_info; echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"; default_settings
  else
    header_info; echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"; advanced_settings
  fi
}

# ---------- Cloud-Init Snippet-Storage ermitteln ----------
pick_snippet_storage() {
  # Liefert in SNIPPET_STORE und SNIPPET_DIR zurück
  mapfile -t SNIPPET_STORES < <(pvesm status -content snippets | awk 'NR>1 {print $1}')

  _store_snippets_dir() {
    local store="$1"
    local p; p="$(pvesm path "$store" 2>/dev/null || true)"
    [[ -n "$p" ]] || return 1
    echo "$p/snippets"
  }

  # 1) Gewählter Storage selbst
  if printf '%s\n' "${SNIPPET_STORES[@]}" | grep -qx -- "$STORAGE"; then
    SNIPPET_STORE="$STORAGE"
    SNIPPET_DIR="$(_store_snippets_dir "$STORAGE")" || return 1
    return 0
  fi

  # 2) Fallback: "local"
  if printf '%s\n' "${SNIPPET_STORES[@]}" | grep -qx -- "local"; then
    SNIPPET_STORE="local"
    SNIPPET_DIR="$(_store_snippets_dir local)" || true
    [[ -n "$SNIPPET_DIR" ]] && return 0
  fi

  # 3) Irgendein anderer
  for s in "${SNIPPET_STORES[@]}"; do
    SNIPPET_DIR="$(_store_snippets_dir "$s")" || continue
    SNIPPET_STORE="$s"
    return 0
  done

  return 1
}

start_script; post_to_api_vm

# ---- OS Auswahl --------------------------------------------------------------
choose_os() {
  local OS_CHOICE
  if OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Choose Base OS" --radiolist \
      "Select the OS for the Docker VM:" 12 70 3 \
      "debian12" "Debian 12 (Bookworm, stable & best for scripts)" ON \
      "debian13" "Debian 13 (Trixie, newer, but repos lag)" OFF \
      "ubuntu24" "Ubuntu 24.04 LTS (modern kernel, GPU/AI friendly)" OFF \
      3>&1 1>&2 2>&3); then
    case "$OS_CHOICE" in
      debian12) var_os="debian"; var_version="12"; URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-$(dpkg --print-architecture).qcow2" ;;
      debian13) var_os="debian"; var_version="13"; URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-$(dpkg --print-architecture).qcow2" ;;
      ubuntu24) var_os="ubuntu"; var_version="24.04"; URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-$(dpkg --print-architecture).img" ;;
    esac
    echo -e "${OSI}${BOLD}${DGN}Selected OS: ${GN}${OS_CHOICE}${CL}"
  else
    exit-script
  fi
}

SSH_PUB_KEYS=()
while IFS= read -r -d '' key; do
  SSH_PUB_KEYS+=("$key")
done < <(find /root/.ssh -maxdepth 1 -type f -name "*.pub" -print0 2>/dev/null)

USE_KEYS="no"
if [[ ${#SSH_PUB_KEYS[@]} -gt 0 ]]; then
  if whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "SSH Key Authentication" \
      --yesno "Found SSH public keys on the host:\n\n${SSH_PUB_KEYS[*]}\n\nUse them for root login in the new VM?" 15 70; then
    USE_KEYS="yes"
  fi
fi

# ---- PVE Version + Install-Mode (einmalig) -----------------------------------
PVE_MAJ="$(pveversion | awk -F'/' '{print $2}' | cut -d'-' -f1 | cut -d'.' -f1)"
case "$PVE_MAJ" in
  8) INSTALL_MODE="direct" ;;
  9) INSTALL_MODE="cloudinit" ;;
  *) msg_error "Unsupported Proxmox VE major: $PVE_MAJ (need 8 or 9)"; exit 1 ;;
esac

# Optionaler Override (einmalig)
if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker Installation Mode" --yesno \
      "Detected PVE ${PVE_MAJ}. Use ${INSTALL_MODE^^} mode?\n\nYes = ${INSTALL_MODE^^}\nNo  = Switch to the other mode" 11 70; then
  INSTALL_MODE=$([ "$INSTALL_MODE" = "direct" ] && echo cloudinit || echo direct)
fi

# ---- Storage Auswahl ---------------------------------------------------------
msg_info "Validating Storage"
DISK_MENU=(); MSG_MAX_LENGTH=0
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
  FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf("%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  (( ${#ITEM} + 2 > MSG_MAX_LENGTH )) && MSG_MAX_LENGTH=${#ITEM}+2
  DISK_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')

VALID=$(pvesm status -content images | awk 'NR>1')
if [[ -z "$VALID" ]]; then
  msg_error "No storage with content=images available. You need at least one images-capable storage."
  exit 1
elif (( ${#DISK_MENU[@]} / 3 == 1 )); then
  STORAGE=${DISK_MENU[0]}
else
  while [[ -z "${STORAGE:+x}" ]]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Disk Storage" --radiolist \
      "Which storage pool should be used for the VM disk?\n(Use Spacebar to select)" \
      16 $((MSG_MAX_LENGTH + 23)) 6 "${DISK_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${BL}${STORAGE}${CL} for VM disk"

if [[ "$PVE_MAJ" -eq 9 && "$INSTALL_MODE" = "cloudinit" ]]; then
  msg_info "Validating Snippet Storage"
  SNIP_MENU=(); MSG_MAX_LENGTH=0
  while read -r line; do
    TAG=$(echo "$line" | awk '{print $1}')
    TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
    FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf("%9sB", $6)}')
    ITEM="  Type: $TYPE Free: $FREE "
    (( ${#ITEM} + 2 > MSG_MAX_LENGTH )) && MSG_MAX_LENGTH=${#ITEM}+2
    SNIP_MENU+=("$TAG" "$ITEM" "OFF")
  done < <(pvesm status -content snippets | awk 'NR>1')

  VALID=$(pvesm status -content snippets | awk 'NR>1')
  if [[ -z "$VALID" ]]; then
    msg_error "No storage with content=snippets available. Please enable 'Snippets' on at least one directory storage (e.g. local)."
    exit 1
  elif (( ${#SNIP_MENU[@]} / 3 == 1 )); then
    SNIPPET_STORE=${SNIP_MENU[0]}
  else
    while [[ -z "${SNIPPET_STORE:+x}" ]]; do
      SNIPPET_STORE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Snippet Storage" --radiolist \
        "Which storage should be used for the Cloud-Init snippet?\n(Use Spacebar to select)" \
        16 $((MSG_MAX_LENGTH + 23)) 6 "${SNIP_MENU[@]}" 3>&1 1>&2 2>&3)
    done
  fi
  msg_ok "Using ${BL}${SNIPPET_STORE}${CL} for Cloud-Init snippets"
fi

configure_authentication() {
  local SSH_PUB_KEYS=()
  while IFS= read -r -d '' key; do
    SSH_PUB_KEYS+=("$key")
  done < <(find /root/.ssh -maxdepth 1 -type f -name "*.pub" -print0 2>/dev/null)

  if [[ ${#SSH_PUB_KEYS[@]} -gt 0 ]]; then
    # Found keys → ask user
    if whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "SSH Key Authentication" \
        --yesno "Found SSH public keys:\n\n${SSH_PUB_KEYS[*]}\n\nDo you want to use them for root login in the new VM?" \
        15 70; then
      echo -e "${CM}${GN}Using SSH keys for root login${CL}"
      qm set "$VMID" --ciuser root --sshkeys "${SSH_PUB_KEYS[0]}" >/dev/null
      return
    fi
  fi

  # No key or user said No → ask for password twice
  local PASS1 PASS2
  while true; do
    PASS1=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "Root Password" \
      --passwordbox "Enter a password for root user" 10 70 3>&1 1>&2 2>&3) || exit-script

    PASS2=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "Confirm Root Password" \
      --passwordbox "Re-enter password for confirmation" 10 70 3>&1 1>&2 2>&3) || exit-script

    if [[ "$PASS1" == "$PASS2" && -n "$PASS1" ]]; then
      echo -e "${CM}${GN}Root password confirmed and set${CL}"
      qm set "$VMID" --ciuser root --cipassword "$PASS1" >/dev/null
      break
    else
      whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "Password Mismatch" \
        --msgbox "Passwords did not match or were empty. Please try again." 10 70
    fi
  done
}


# ---- Cloud Image Download ----------------------------------------------------
choose_os
msg_info "Retrieving Cloud Image for $var_os $var_version"
echo -e ""
echo -e ""
curl --retry 30 --retry-delay 3 --retry-connrefused -fSL -o "$(basename "$URL")" "$URL"
FILE="$(basename "$URL")"
msg_ok "Downloaded ${BL}${FILE}${CL}"

# Ubuntu RAW → qcow2
if [[ "$FILE" == *.img ]]; then
  msg_info "Converting RAW image to qcow2"
  qemu-img convert -O qcow2 "$FILE" "${FILE%.img}.qcow2"
  rm -f "$FILE"
  FILE="${FILE%.img}.qcow2"
  msg_ok "Converted to ${BL}${FILE}${CL}"
fi

# ---- Codename & Docker-Repo (einmalig) ---------------------------------------
detect_codename_and_repo() {
  if [[ "$URL" == *"/bookworm/"* || "$FILE" == *"debian-12-"* ]]; then
    CODENAME="bookworm"; DOCKER_BASE="https://download.docker.com/linux/debian"
  elif [[ "$URL" == *"/trixie/"* || "$FILE" == *"debian-13-"* ]]; then
    CODENAME="trixie";   DOCKER_BASE="https://download.docker.com/linux/debian"
  elif [[ "$URL" == *"/noble/"*  || "$FILE" == *"noble-"* ]]; then
    CODENAME="noble";    DOCKER_BASE="https://download.docker.com/linux/ubuntu"
  else
    CODENAME="bookworm"; DOCKER_BASE="https://download.docker.com/linux/debian"
  fi
  REPO_CODENAME="$CODENAME"
  if [[ "$DOCKER_BASE" == *"linux/debian"* && "$CODENAME" == "trixie" ]]; then
    REPO_CODENAME="bookworm"
  fi
}
detect_codename_and_repo

get_snippet_dir() {
  local store="$1"
  awk -v s="$store" '
    $1 == "dir:" && $2 == s {getline; print $2 "/snippets"}
  ' /etc/pve/storage.cfg
}

# ---- PVE8: direct inject via virt-customize ----------------------------------
if [[ "$INSTALL_MODE" = "direct" ]]; then
  msg_info "Injecting Docker & QGA into image (${CODENAME}, repo: $(basename "$DOCKER_BASE"))"
  export LIBGUESTFS_BACKEND=direct
  if ! command -v virt-customize >/dev/null 2>&1; then
    apt-get -qq update >/dev/null
    apt-get -qq install -y libguestfs-tools >/dev/null
  fi
  vrun() { virt-customize -q -a "${FILE}" "$@" >/dev/null; }
  vrun \
    --install qemu-guest-agent,ca-certificates,curl,gnupg,lsb-release,apt-transport-https \
    --run-command "install -m 0755 -d /etc/apt/keyrings" \
    --run-command "curl -fsSL ${DOCKER_BASE}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg" \
    --run-command "chmod a+r /etc/apt/keyrings/docker.gpg" \
    --run-command "echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_BASE} ${REPO_CODENAME} stable' > /etc/apt/sources.list.d/docker.list" \
    --run-command "apt-get update -qq" \
    --run-command "apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin" \
    --run-command "systemctl enable docker qemu-guest-agent" \
    --run-command "sed -i 's#^ENV_SUPATH.*#ENV_SUPATH  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#' /etc/login.defs || true" \
    --run-command "sed -i 's#^ENV_PATH.*#ENV_PATH    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#' /etc/login.defs || true" \
    --run-command "printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' >/etc/environment" \
    --run-command "grep -q 'export PATH=' /root/.bashrc || echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' >> /root/.bashrc"
  msg_ok "Docker & QGA injected"
fi

# ---- PVE9: Cloud-Init Snippet (NoCloud) --------------------------------------
if [[ "$INSTALL_MODE" = "cloudinit" ]]; then
  msg_info "Preparing Cloud-Init user-data for Docker (${CODENAME})"

  # Use SNIPPET_STORE selected earlier
  SNIPPET_DIR="$(get_snippet_dir "$SNIPPET_STORE")"
  mkdir -p "$SNIPPET_DIR"

  SNIPPET_FILE="docker-${VMID}-user-data.yaml"
  SNIPPET_PATH="${SNIPPET_DIR}/${SNIPPET_FILE}"

  DOCKER_GPG_B64="$(curl -fsSL "${DOCKER_BASE}/gpg" | gpg --dearmor | base64 -w0)"

cat >"$SNIPPET_PATH" <<EOYAML
#cloud-config
hostname: ${HN}
manage_etc_hosts: true

package_update: true
package_upgrade: false
packages:
  - ca-certificates
  - curl
  - gnupg
  - qemu-guest-agent
  - cloud-guest-utils

runcmd:
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL ${DOCKER_BASE}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - chmod a+r /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_BASE} ${REPO_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update -qq
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  - systemctl enable --now qemu-guest-agent
  - systemctl enable --now docker

growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false

fs_resize: true

power_state:
  mode: reboot
  condition: true
EOYAML

  chmod 0644 "$SNIPPET_PATH"
  msg_ok "Cloud-Init user-data written: ${SNIPPET_PATH}"
fi

# ---- VM erstellen (q35) ------------------------------------------------------
msg_info "Creating a Docker VM shell"
qm create "$VMID" -machine q35 -bios ovmf -agent 1 -tablet 0 -localtime 1 ${CPU_TYPE} \
  -cores "$CORE_COUNT" -memory "$RAM_SIZE" -name "$HN" -tags community-script \
  -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
msg_ok "Created VM shell"

msg_info "Configuring authentication"
configure_authentication
msg_ok "Authentication configured"

# ---- Disk importieren --------------------------------------------------------
msg_info "Importing disk into storage ($STORAGE)"
if qm disk import --help >/dev/null 2>&1; then IMPORT_CMD=(qm disk import); else IMPORT_CMD=(qm importdisk); fi
IMPORT_OUT="$("${IMPORT_CMD[@]}" "$VMID" "${FILE}" "$STORAGE" --format qcow2 2>&1 || true)"
DISK_REF="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p" | tr -d "\r\"'")"
[[ -z "$DISK_REF" ]] && DISK_REF="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"
[[ -z "$DISK_REF" ]] && { msg_error "Unable to determine imported disk reference."; echo "$IMPORT_OUT"; exit 1; }
msg_ok "Imported disk (${BL}${DISK_REF}${CL})"

SSHKEYS_ARG=""
if [[ -s /root/.ssh/authorized_keys ]]; then
  SSHKEYS_ARG="--sshkeys /root/.ssh/authorized_keys"
fi

# ---- EFI + Root + Cloud-Init anhängen ---------------------------------------
msg_info "Attaching EFI/root disk and Cloud-Init (Patience)"
qm set "$VMID" \
  --efidisk0 "${STORAGE}:0${FORMAT}" \
  --scsi0 "${DISK_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE}" \
  --boot order=scsi0 \
  --serial0 socket \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --ide2 "${STORAGE}:cloudinit" \
  --ipconfig0 "ip=dhcp" >/dev/null

if [[ "$INSTALL_MODE" = "cloudinit" ]]; then
  qm set "$VMID" --cicustom "user=${SNIPPET_STORE}:snippets/${SNIPPET_FILE}" >/dev/null
fi
msg_ok "Attached EFI/root and Cloud-Init"

# ---- Disk auf Zielgröße im PVE-Layer (Cloud-Init wächst FS) ------------------
msg_info "Resizing disk to $DISK_SIZE (PVE layer)"
qm resize "$VMID" scsi0 "${DISK_SIZE}" >/dev/null || true
msg_ok "Resized disk"

# ---- Beschreibung ------------------------------------------------------------
DESCRIPTION=$(
  cat <<'EOF'
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
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
qm set "$VMID" -description "$DESCRIPTION" >/dev/null
msg_ok "Created a Docker VM ${BL}(${HN})${CL}"

# ---- Start -------------------------------------------------------------------
if [[ "$START_VM" == "yes" ]]; then
  msg_info "Starting Docker VM"
  qm start "$VMID"
  msg_ok "Started Docker VM"
fi

post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"

# ---- Hinweise/Debug (Cloud-Init) --------------------------------------------
# In der VM prüfen:
#   journalctl -u cloud-init -b
#   cat /var/log/cloud-init.log
#   cat /var/log/cloud-init-output.log
#   cloud-init status --long

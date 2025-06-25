#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# Co-Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# This sets verbose mode if the global variable is set to "yes"
# if [ "$VERBOSE" == "yes" ]; then set -x; fi

if command -v curl >/dev/null 2>&1; then
  source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
  load_functions
  #echo "(create-lxc.sh) Loaded core.func via curl"
elif command -v wget >/dev/null 2>&1; then
  source <(wget -qO- https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
  load_functions
  #echo "(create-lxc.sh) Loaded core.func via wget"
fi

# This sets error handling options and defines the error_handler function to handle errors
set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap on_exit EXIT
trap on_interrupt INT
trap on_terminate TERM

function on_exit() {
  local exit_code="$?"
  [[ -n "${lockfile:-}" ]]
  exit "$exit_code"
}

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  printf "\e[?25h"
  echo -e "\n${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}\n"
  exit "$exit_code"
}

function on_interrupt() {
  echo -e "\n${RD}Interrupted by user (SIGINT)${CL}"
  exit 130
}

function on_terminate() {
  echo -e "\n${RD}Terminated by signal (SIGTERM)${CL}"
  exit 143
}

# This checks for the presence of valid Container Storage and Template Storage locations
msg_info "Validating Storage"
VALIDCT=$(pvesm status -content rootdir | awk 'NR>1')
if [ -z "$VALIDCT" ]; then
  msg_error "Unable to detect a valid Container Storage location."
  exit 1
fi
VALIDTMP=$(pvesm status -content vztmpl | awk 'NR>1')
if [ -z "$VALIDTMP" ]; then
  msg_error "Unable to detect a valid Template Storage location."
  exit 1
fi

# This function is used to select the storage class and determine the corresponding storage content type and label.
function select_storage() {
  local CLASS=$1 CONTENT CONTENT_LABEL
  case $CLASS in
  container)
    CONTENT='rootdir'
    CONTENT_LABEL='Container'
    ;;
  template)
    CONTENT='vztmpl'
    CONTENT_LABEL='Container template'
    ;;
  iso)
    CONTENT='iso'
    CONTENT_LABEL='ISO image'
    ;;
  images)
    CONTENT='images'
    CONTENT_LABEL='VM Disk image'
    ;;
  backup)
    CONTENT='backup'
    CONTENT_LABEL='Backup'
    ;;
  snippets)
    CONTENT='snippets'
    CONTENT_LABEL='Snippets'
    ;;
  *)
    msg_error "Invalid storage class '$CLASS'."
    exit 201
    ;;
  esac

  command -v whiptail >/dev/null || {
    msg_error "whiptail missing."
    exit 220
  }
  command -v numfmt >/dev/null || {
    msg_error "numfmt missing."
    exit 221
  }

  local -a MENU
  while read -r line; do
    local TAG=$(echo $line | awk '{print $1}')
    local TYPE=$(echo $line | awk '{printf "%-10s", $2}')
    local FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
    MENU+=("$TAG" "Type: $TYPE Free: $FREE " "OFF")
  done < <(pvesm status -content $CONTENT | awk 'NR>1')

  if [ ${#MENU[@]} -eq 0 ]; then
    msg_error "No storage found for content type '$CONTENT'."
    exit 203
  fi

  if [ $((${#MENU[@]} / 3)) -eq 1 ]; then
    printf "%s" "${MENU[0]}"
    return
  fi

  local STORAGE
  STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
    "Which storage pool for ${CONTENT_LABEL,,}?\n(Spacebar to select)" \
    16 70 6 "${MENU[@]}" 3>&1 1>&2 2>&3) || {
    msg_error "Storage selection cancelled by user."
    exit 202
  }
  printf "%s" "$STORAGE"
}

# Test if required variables are set
[[ "${CTID:-}" ]] || {
  msg_error "You need to set 'CTID' variable."
  exit 203
}
[[ "${PCT_OSTYPE:-}" ]] || {
  msg_error "You need to set 'PCT_OSTYPE' variable."
  exit 204
}

# Test if ID is valid
[ "$CTID" -ge "100" ] || {
  msg_error "ID cannot be less than 100."
  exit 205
}

# Test if ID is in use
if qm status "$CTID" &>/dev/null || pct status "$CTID" &>/dev/null; then
  echo -e "ID '$CTID' is already in use."
  unset CTID
  msg_error "Cannot use ID that is already in use."
  exit 206
fi

DEFAULT_FILE="/usr/local/community-scripts/default_storage"
if [[ -f "$DEFAULT_FILE" ]]; then
  source "$DEFAULT_FILE"
  if [[ -n "$TEMPLATE_STORAGE" && -n "$CONTAINER_STORAGE" ]]; then
    msg_info "Using default storage configuration from: $DEFAULT_FILE"
    msg_ok "Template Storage: ${BL}$TEMPLATE_STORAGE${CL} ${GN}|${CL} Container Storage: ${BL}$CONTAINER_STORAGE${CL}"
  else
    msg_warn "Default storage file exists but is incomplete – falling back to manual selection"
    TEMPLATE_STORAGE=$(select_storage template)
    msg_ok "Using ${BL}$TEMPLATE_STORAGE${CL} ${GN}for Template Storage."
    CONTAINER_STORAGE=$(select_storage container)
    msg_ok "Using ${BL}$CONTAINER_STORAGE${CL} ${GN}for Container Storage."
  fi
else
  TEMPLATE_STORAGE=$(select_storage template)
  msg_ok "Using ${BL}$TEMPLATE_STORAGE${CL} ${GN}for Template Storage."
  CONTAINER_STORAGE=$(select_storage container)
  msg_ok "Using ${BL}$CONTAINER_STORAGE${CL} ${GN}for Container Storage."
fi

# Check free space on selected container storage
STORAGE_FREE=$(pvesm status | awk -v s="$CONTAINER_STORAGE" '$1 == s { print $6 }')
REQUIRED_KB=$((${PCT_DISK_SIZE:-8} * 1024 * 1024))
if [ "$STORAGE_FREE" -lt "$REQUIRED_KB" ]; then
  msg_error "Not enough space on '$CONTAINER_STORAGE'. Needed: ${PCT_DISK_SIZE:-8}G."
  exit 214
fi
# Check Cluster Quorum if in Cluster
if [ -f /etc/pve/corosync.conf ]; then
  msg_info "Checking Proxmox cluster quorum status"
  if ! pvecm status | awk -F':' '/^Quorate/ { exit ($2 ~ /Yes/) ? 0 : 1 }'; then
    printf "\e[?25h"
    msg_error "Cluster is not quorate. Start all nodes or configure quorum device (QDevice)."
    exit 210
  fi
  msg_ok "Cluster is quorate"
fi

# Update LXC template list
TEMPLATE_SEARCH="${PCT_OSTYPE}-${PCT_OSVERSION:-}"

msg_info "Updating LXC Template List"
if ! timeout 15 pveam update >/dev/null 2>&1; then
  TEMPLATE_FALLBACK=$(pveam list "$TEMPLATE_STORAGE" | awk "/$TEMPLATE_SEARCH/ {print \$2}" | sort -t - -k 2 -V | tail -n1)
  if [[ -z "$TEMPLATE_FALLBACK" ]]; then
    msg_error "Failed to update LXC template list and no local template matching '$TEMPLATE_SEARCH' found."
    exit 201
  fi
  msg_info "Skipping template update – using local fallback: $TEMPLATE_FALLBACK"
else
  msg_ok "LXC Template List Updated"
fi

# Get LXC template string
TEMPLATE_SEARCH="${PCT_OSTYPE}-${PCT_OSVERSION:-}"
mapfile -t TEMPLATES < <(pveam available -section system | sed -n "s/.*\($TEMPLATE_SEARCH.*\)/\1/p" | sort -t - -k 2 -V)

if [ ${#TEMPLATES[@]} -eq 0 ]; then
  msg_error "No matching LXC template found for '${TEMPLATE_SEARCH}'. Make sure your host can reach the Proxmox template repository."
  exit 207
fi

TEMPLATE="${TEMPLATES[-1]}"
TEMPLATE_PATH="$(pvesm path $TEMPLATE_STORAGE:vztmpl/$TEMPLATE 2>/dev/null || echo "/var/lib/vz/template/cache/$TEMPLATE")"

# Check if template exists and is valid
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE" || ! zstdcat "$TEMPLATE_PATH" | tar -tf - >/dev/null 2>&1; then
  msg_warn "Template $TEMPLATE not found or appears to be corrupted. Re-downloading."

  [[ -f "$TEMPLATE_PATH" ]] && rm -f "$TEMPLATE_PATH"
  for attempt in {1..3}; do
    msg_info "Attempt $attempt: Downloading LXC template..."

    if timeout 120 pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null 2>&1; then
      msg_ok "Template download successful."
      break
    fi

    if [ $attempt -eq 3 ]; then
      msg_error "Failed after 3 attempts. Please check your Proxmox host’s internet access or manually run:\n  pveam download $TEMPLATE_STORAGE $TEMPLATE"
      exit 208
    fi

    sleep $((attempt * 5))
  done
fi

msg_ok "LXC Template '$TEMPLATE' is ready to use."
# Check and fix subuid/subgid
grep -q "root:100000:65536" /etc/subuid || echo "root:100000:65536" >>/etc/subuid
grep -q "root:100000:65536" /etc/subgid || echo "root:100000:65536" >>/etc/subgid

# Combine all options
PCT_OPTIONS=(${PCT_OPTIONS[@]:-${DEFAULT_PCT_OPTIONS[@]}})
[[ " ${PCT_OPTIONS[@]} " =~ " -rootfs " ]] || PCT_OPTIONS+=(-rootfs "$CONTAINER_STORAGE:${PCT_DISK_SIZE:-8}")

# Secure creation of the LXC container with lock and template check
lockfile="/tmp/template.${TEMPLATE}.lock"
exec 9>"$lockfile" >/dev/null 2>&1 || {
  msg_error "Failed to create lock file '$lockfile'."
  exit 200
}
flock -w 60 9 || {
  msg_error "Timeout while waiting for template lock"
  exit 211
}

msg_info "Creating LXC Container"
if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" &>/dev/null; then
  msg_error "Container creation failed. Checking if template is corrupted or incomplete."

  if [[ ! -s "$TEMPLATE_PATH" || "$(stat -c%s "$TEMPLATE_PATH")" -lt 1000000 ]]; then
    msg_error "Template file too small or missing – re-downloading."
    rm -f "$TEMPLATE_PATH"
  elif ! zstdcat "$TEMPLATE_PATH" | tar -tf - &>/dev/null; then
    msg_error "Template appears to be corrupted – re-downloading."
    rm -f "$TEMPLATE_PATH"
  else
    msg_error "Template is valid, but container creation still failed."
    exit 209
  fi

  # Retry download
  for attempt in {1..3}; do
    msg_info "Attempt $attempt: Re-downloading template..."
    if timeout 120 pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null; then
      msg_ok "Template re-download successful."
      break
    fi
    if [ "$attempt" -eq 3 ]; then
      msg_error "Three failed attempts. Aborting."
      exit 208
    fi
    sleep $((attempt * 5))
  done

  sleep 1 # I/O-Sync-Delay
  msg_ok "Re-downloaded LXC Template"
fi

if ! pct list | awk '{print $1}' | grep -qx "$CTID"; then
  msg_error "Container ID $CTID not listed in 'pct list' – unexpected failure."
  exit 215
fi

if ! grep -q '^rootfs:' "/etc/pve/lxc/$CTID.conf"; then
  msg_error "RootFS entry missing in container config – storage not correctly assigned."
  exit 216
fi

if grep -q '^hostname:' "/etc/pve/lxc/$CTID.conf"; then
  CT_HOSTNAME=$(grep '^hostname:' "/etc/pve/lxc/$CTID.conf" | awk '{print $2}')
  if [[ ! "$CT_HOSTNAME" =~ ^[a-z0-9-]+$ ]]; then
    msg_warn "Hostname '$CT_HOSTNAME' contains invalid characters – may cause issues with networking or DNS."
  fi
fi

if [[ "${PCT_RAM_SIZE:-2048}" -lt 1024 ]]; then
  msg_warn "Configured RAM (${PCT_RAM_SIZE}MB) is below 1024MB – some apps may not work properly."
fi

if [[ "${PCT_UNPRIVILEGED:-1}" == "1" && " ${PCT_OPTIONS[*]} " == *"fuse=1"* ]]; then
  msg_warn "Unprivileged container with FUSE may fail unless extra device mappings are configured."
fi

# Extra: Debug-Ausgabe (wenn DEBUG=yes gesetzt)
DEBUG_LOG="/tmp/lxc_debug_${CTID}.log"
{
  echo "--- DEBUG DUMP for CTID $CTID ---"
  echo "Hostname: ${CT_HOSTNAME:-unknown}"
  echo "Template: ${TEMPLATE}"
  echo "Template Storage: ${TEMPLATE_STORAGE}"
  echo "Container Storage: ${CONTAINER_STORAGE}"
  echo "Template Path: ${TEMPLATE_PATH}"
  echo "Disk Size: ${PCT_DISK_SIZE:-8} GB"
  echo "RAM Size: ${PCT_RAM_SIZE:-2048} MB"
  echo "CPU Cores: ${PCT_CPU_CORES:-2}"
  echo "Unprivileged: ${PCT_UNPRIVILEGED:-1}"
  echo "PCT_OPTIONS:"
  printf '  %s\n' "${PCT_OPTIONS[@]}"
  echo "--- Container Config Dump ---"
  [[ -f "/etc/pve/lxc/$CTID.conf" ]] && cat "/etc/pve/lxc/$CTID.conf"
  echo "--- LVM Volumes ---"
  lvs | grep "vm-${CTID}-disk-0" || echo "No LVM volume found."
  echo "--- pct list ---"
  pct list
} >"$DEBUG_LOG"

msg_ok "LXC Container ${BL}$CTID${CL} ${GN}was successfully created."

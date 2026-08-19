#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# LXC Disk Resize — shrink LXC container disks safely via dd copy + checksum
# verification for LVM/LVM-thin/directory storage, or refquota adjustment for
# ZFS subvolumes.  Supports both interactive (whiptail) and non-interactive
# (CLI) modes.

set -eEuo pipefail
export PERL_BADLANG=0

# =============================================================================
# Constants and color codes
# =============================================================================

BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
YW="\033[33m"
CL="\033[m"
TAB="  "
CM="${TAB}✔${TAB}"

LOGFILE="/var/log/lxc-resize.log"

msg_info() { echo -e "${BL}[Info]${GN} $1${CL}"; }
msg_ok()   { echo -e "${GN}${TAB}${CM}${CL} ${GN}$1${CL}"; }
msg_error(){ echo -e "${RD}[Error]${CL} $1"; }

# =============================================================================
# Logging
# =============================================================================

# Append a timestamped line to the log file.
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >>"$LOGFILE"
}

# =============================================================================
# Interrupt handling
# =============================================================================

# During critical operations (dd copy, volume swap) Ctrl+C must be blocked to
# prevent data loss.  This flag is toggled by block_interrupts/allow_interrupts.
INTERRUPT_BLOCKED=0

trap_exit() {
  if [[ "$INTERRUPT_BLOCKED" -eq 1 ]]; then
    echo -e "\n${RD}Cannot interrupt — critical operation in progress. Wait for it to finish.${CL}"
    log "INTERRUPT_BLOCKED"
    return
  fi
  echo -e "\n${RD}Interrupted by user.${CL}"
  log "INTERRUPTED by user"
  exit 130
}

block_interrupts() { INTERRUPT_BLOCKED=1; }
allow_interrupts() { INTERRUPT_BLOCKED=0; }

trap trap_exit INT TERM

# =============================================================================
# UI helpers
# =============================================================================

function header_info() {
  clear
  cat <<"EOF"
    _   ___  ________   ____       __     __
   / | / / / /_  __/  / __ \___  / /__  / /____
  /  |/ / / / / /    / / / / _ \/ / _ \/ __/ _ \
 / /|  / /_/ / /    / /_/ /  __/ /  __/ /_/  __/
/_/ |_/\____/_/    /____/\___/_/\___/\__/\___/
            DISK RESIZE
EOF
}

# Display a spinner animation while a background process runs.
# Usage: spinner $PID "Message"
spinner() {
  local pid=$1
  local msg=${2:-"Working"}
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while ps -p "$pid" >/dev/null 2>&1; do
    echo -ne "\r\033[36m[Info]\033[1;92m ${msg}... ${spinstr:0:1}\033[m"
    spinstr=${spinstr#?}${spinstr%"${spinstr#?}"}
    sleep "$delay"
  done
  echo -ne "\r\033[K"
}

# Run a command in the background with a spinner and report success/failure.
run_with_spinner() {
  local msg=$1
  shift
  msg_info "${msg}..."
  log "SPINNER $msg"
  "$@" &
  local pid=$!
  spinner "$pid" "$msg"
  wait "$pid"
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    msg_ok "${msg} — done"
    log "DONE $msg"
  else
    msg_error "${msg} — failed (exit $rc)"
    log "FAIL $msg exit=$rc"
  fi
  return $rc
}

# Stream progress percentages from stdin and render a visual progress bar.
# Used by dd's status=progress output piped into this function.
progress_bar() {
  local label=$1
  local total=$2
  local current=0
  local width=40
  msg_info "${label}..."
  log "PROGRESS_START $label total=$total"
  while IFS= read -r line; do
    local pct
    pct=$(echo "$line" | grep -oP '\d+(?=%)' || echo "0")
    if [[ -n "$pct" && "$pct" -gt "$current" ]] 2>/dev/null; then
      current=$pct
      local filled=$((current * width / 100))
      local empty=$((width - filled))
      printf "\r  [${GN}%${filled}s${CL}%${empty}s${CL}] ${current}%%" | tr ' ' '█' | tr ' ' '░'
    fi
  done
  printf "\r\033[K"
  msg_ok "${label} — done"
  log "PROGRESS_DONE $label"
}

# =============================================================================
# Size conversion helpers
# =============================================================================

# Convert a human-readable size string (e.g. "3G", "500M", "1.5T") to bytes.
# Accepts optional unit suffixes: T, G, M, K, B, or bare number (treated as bytes).
parse_size_to_bytes() {
  local size="$1"
  local num="${size%%[KMGTPkmgtp]*}"
  local unit="${size##*[0-9]}"
  unit="${unit^^}"
  # Use awk for floating point support (e.g. 2.4G)
  case "$unit" in
    T) awk "BEGIN { printf \"%.0f\", $num * 1024 * 1024 * 1024 * 1024 }" ;;
    G) awk "BEGIN { printf \"%.0f\", $num * 1024 * 1024 * 1024 }" ;;
    M) awk "BEGIN { printf \"%.0f\", $num * 1024 * 1024 }" ;;
    K) awk "BEGIN { printf \"%.0f\", $num * 1024 }" ;;
    B|"") echo "$num" ;;
    *) echo "0" ;;
  esac
}

# Convert a byte count to the largest human-readable unit (G, M, K, or B).
bytes_to_human() {
  local bytes=$1
  if ((bytes >= 1073741824)); then
    echo "$((bytes / 1073741824))G"
  elif ((bytes >= 1048576)); then
    echo "$((bytes / 1048576))M"
  elif ((bytes >= 1024)); then
    echo "$((bytes / 1024))K"
  else
    echo "${bytes}B"
  fi
}

# =============================================================================
# Proxmox / storage query helpers
# =============================================================================

# Return the storage backend type for a Proxmox storage ID (e.g. "local-zfs" -> "zfspool").
get_storage_type() {
  local storage="$1"
  pvesm status | awk -v st="$storage" '$1 == st {print $2}'
}

# Return the absolute path for a Proxmox volume reference (e.g. "local-lvm:vm-100-disk-0").
get_volume_path() {
  local vol="$1"
  pvesm path "$vol" 2>/dev/null
}

# Parse /etc/pve/storage.cfg and return the ZFS pool name for a given storage ID.
# Example: get_zfs_pool "local-zfs" -> "rpool/data"
get_zfs_pool() {
  local storage="$1"
  awk -v st="$storage" '
    /^zfspool:/ { match_name = ($2 == st) }
    match_name && /^[\t ]+pool / { print $2; exit }
  ' /etc/pve/storage.cfg 2>/dev/null
}

# Build the full ZFS dataset path by combining pool and volume name.
# Example: get_zfs_dataset "local-zfs" "subvol-999-disk-0" -> "rpool/data/subvol-999-disk-0"
get_zfs_dataset() {
  local storage="$1"
  local vol_name="$2"
  local pool
  pool=$(get_zfs_pool "$storage")
  if [[ -n "$pool" ]]; then
    echo "${pool}/${vol_name}"
  else
    echo ""
  fi
}

# =============================================================================
# Container config query helpers
# =============================================================================

# Extract the volume name from a container's pct config line for a given disk key.
# Works for all storage types — not limited to LVM despite the original name.
# Config format: "rootfs: local-zfs:subvol-999-disk-0,size=4G"
# Returns: "subvol-999-disk-0"
get_volume_name() {
  local ctid=$1
  local disk_key=$2
  local config_line
  config_line=$(pct config "$ctid" | awk "/^${disk_key}:/ {print}")
  echo "$config_line" | cut -d: -f3 | cut -d, -f1
}

# Extract the storage ID for a given disk key from the container config.
# Config format: "rootfs: local-zfs:subvol-999-disk-0,size=4G"
# Returns: "local-zfs"
get_storage_for_disk() {
  local ctid=$1
  local disk_key=$2
  local config_line
  config_line=$(pct config "$ctid" | awk "/^${disk_key}:/ {print}")
  echo "$config_line" | awk -F": " '{print $2}' | cut -d: -f1
}

# Extract the declared size string (e.g. "4G") from the container config.
get_size_from_config() {
  local ctid=$1
  local disk_key=$2
  local config_line
  config_line=$(pct config "$ctid" | awk "/^${disk_key}:/ {print}")
  echo "$config_line" | grep -oP 'size=\K[^ ,]+'
}

# Return the actually-used bytes for a disk, as reported by `pct df`.
get_used_bytes() {
  local ctid=$1
  local disk_key=$2
  # pct df output columns: MP Volume Size Used Avail Use% Path
  local used
  used=$(pct df "$ctid" 2>/dev/null | awk -v dk="$disk_key" '$1 == dk {print $4}')
  if [[ -n "$used" ]]; then
    parse_size_to_bytes "$used"
  else
    echo "0"
  fi
}

# Return the declared maximum size in bytes for a disk from the container config.
get_max_bytes() {
  local ctid=$1
  local disk_key=$2
  local size_str
  size_str=$(get_size_from_config "$ctid" "$disk_key")
  if [[ -n "$size_str" ]]; then
    parse_size_to_bytes "$size_str"
  else
    echo "0"
  fi
}

# =============================================================================
# LVM volume group resolution
# =============================================================================

# Resolve the LVM volume group name for a given logical volume name.
# First tries a direct lookup by LV name; falls back to the first VG on the system.
resolve_vg_name() {
  local vol_name="$1"
  local vg_name
  vg_name=$(lvs --noheadings -o vg_name 2>/dev/null | awk -v lv="$vol_name" '$1 == lv {print $1}')
  if [[ -z "$vg_name" ]]; then
    vg_name=$(lvs --noheadings -o vg_name 2>/dev/null | head -1 | tr -d ' ')
  fi
  echo "$vg_name"
}

# =============================================================================
# Device path resolution
# =============================================================================

# Return the /dev/ path for a Proxmox volume, dispatching by storage type.
#   LVM/LVM-thin: /dev/<vg>/<lv>
#   ZFS:          /dev/zvol/<pool>/<vol>
#   dir/nfs/cifs: resolved via pvesm path
get_device_path() {
  local vol="$1"
  local storage="${vol%%:*}"
  local vol_name="${vol#*:}"
  local storage_type
  storage_type=$(get_storage_type "$storage")

  case $storage_type in
    lvmthin|lvm)
      local vg_name
      vg_name=$(resolve_vg_name "$vol_name")
      echo "/dev/${vg_name}/${vol_name}"
      ;;
    zfs)
      local zfs_pool
      zfs_pool=$(get_zfs_pool "$storage")
      echo "/dev/zvol/${zfs_pool}/${vol_name}"
      ;;
    dir|nfs|cifs)
      pvesm path "$vol" 2>/dev/null
      ;;
    *)
      echo ""
      ;;
  esac
}

# =============================================================================
# Volume lifecycle operations (create / remove)
# =============================================================================

# Determine the next available disk number for a container by scanning its config.
# Example: if container has disk-0 and disk-1, returns 2.
get_next_disk_number() {
  local ctid=$1
  local max_disk=-1
  local vol
  for vol in $(pct config "$ctid" 2>/dev/null | awk -F'[: ,]' '/^(rootfs|mp[0-9]+)/ {print $4}'); do
    local disk_num
    disk_num=$(echo "$vol" | grep -oP 'disk-\K[0-9]+' || echo "-1")
    if [[ "$disk_num" =~ ^[0-9]+$ ]] && ((disk_num > max_disk)); then
      max_disk=$disk_num
    fi
  done
  echo $((max_disk + 1))
}

# Create a new volume of the specified size on the same storage backend as the disk.
# Returns the Proxmox volume reference (e.g. "local-lvm:vm-100-disk-2").
# Returns empty string and exits non-zero on unsupported storage types.
create_new_volume() {
  local ctid=$1
  local disk_key=$2
  local new_size=$3
  local storage
  storage=$(get_storage_for_disk "$ctid" "$disk_key")
  local storage_type
  storage_type=$(get_storage_type "$storage")
  local next_disk
  next_disk=$(get_next_disk_number "$ctid")

  case $storage_type in
    lvmthin|lvm)
      local vg_name
      vg_name=$(lvs --noheadings -o vg_name 2>/dev/null | head -1 | tr -d ' ')
      local new_vol="vm-${ctid}-disk-${next_disk}"
      lvcreate -L "${new_size}" -n "$new_vol" "$vg_name"
      echo "${storage}:${new_vol}"
      ;;
    zfs)
      local new_vol="subvol-${ctid}-disk-${next_disk}"
      local zfs_ds
      zfs_ds=$(get_zfs_dataset "$storage" "$new_vol")
      zfs create -V "${new_size}" "$zfs_ds"
      echo "${storage}:${new_vol}"
      ;;
    dir|nfs|cifs)
      local new_vol="vm-${ctid}-disk-new.raw"
      local storage_path
      storage_path=$(pvesm path "${storage}:${new_vol}" 2>/dev/null)
      mkdir -p "$(dirname "$storage_path")"
      truncate -s "${new_size}" "$storage_path"
      echo "${storage}:${new_vol}"
      ;;
    *)
      echo ""
      return 1
      ;;
  esac
}

# Remove a volume from its storage backend.
# Errors are silently ignored (|| true) since the caller may invoke this during rollback
# when the volume might already be gone.
remove_volume() {
  local vol="$1"
  local storage="${vol%%:*}"
  local vol_name="${vol#*:}"
  local storage_type
  storage_type=$(get_storage_type "$storage")

  case $storage_type in
    lvmthin|lvm)
      local vg_name
      vg_name=$(resolve_vg_name "$vol_name")
      lvremove -f "/dev/${vg_name}/${vol_name}" 2>/dev/null || true
      ;;
    zfs)
      local zfs_ds
      zfs_ds=$(get_zfs_dataset "$storage" "$vol_name")
      zfs destroy "$zfs_ds" 2>/dev/null || true
      ;;
    dir|nfs|cifs)
      local vol_path
      vol_path=$(pvesm path "$vol" 2>/dev/null)
      rm -f "$vol_path" 2>/dev/null || true
      ;;
  esac
}

# =============================================================================
# Data copy and verification
# =============================================================================

# Compute the standard dd block size (1M) and block count for a given byte size.
# Both copy_data and verify_checksum need identical parameters, so they share this.
get_dd_params() {
  local source_size=$1
  local bs=1M
  local count=$((source_size / 1048576))
  if ((count < 1)); then
    count=1
  fi
  echo "$bs" "$count"
}

# Copy data from source device to destination using dd.
# Only copies source_size bytes (not the entire device) to avoid copying
# beyond what the container actually uses.
copy_data() {
  local source_dev="$1"
  local dest_dev="$2"
  local source_size=$3

  local bs count
  read -r bs count <<< "$(get_dd_params "$source_size")"
  dd if="$source_dev" of="$dest_dev" bs="$bs" count="$count" status=progress 2>&1
}

# Compare MD5 checksums of source and destination to detect corruption.
# Returns 0 on match, 1 on mismatch.
verify_checksum() {
  local source_dev="$1"
  local dest_dev="$2"
  local source_size=$3

  local bs count
  read -r bs count <<< "$(get_dd_params "$source_size")"

  local source_hash dest_hash
  source_hash=$(dd if="$source_dev" bs="$bs" count="$count" 2>/dev/null | md5sum | awk '{print $1}')
  dest_hash=$(dd if="$dest_dev" bs="$bs" count="$count" 2>/dev/null | md5sum | awk '{print $1}')

  if [[ "$source_hash" == "$dest_hash" ]]; then
    return 0
  else
    return 1
  fi
}

# =============================================================================
# Container config manipulation
# =============================================================================

# Replace a disk entry in the container's pct config with a new volume reference.
# For mount points (mp0, mp1, ...) the existing mount options are preserved.
replace_volume_in_config() {
  local ctid=$1
  local disk_key=$2
  local new_vol=$3
  local new_size=${4:-}

  local storage="${new_vol%%:*}"
  local vol_name="${new_vol#*:}"

  # Build the value string for pct set, optionally including size
  local vol_value="${storage}:${vol_name}"
  if [[ -n "$new_size" ]]; then
    vol_value="${vol_value},size=${new_size}"
  fi

  # Remove the old disk entry first
  pct set "$ctid" --delete "$disk_key"

  # Re-add with the new volume, preserving mount options for mp* keys
  case $disk_key in
    rootfs)
      pct set "$ctid" --rootfs "${vol_value}"
      ;;
    mp[0-9]*)
      local old_mp_opts
      old_mp_opts=$(pct config "$ctid" 2>/dev/null | awk "/^${disk_key}:/ {sub(/^[^ ]+ [^ ]+ [^ ]+ /, \"\"); print}" || true)
      if [[ -n "$old_mp_opts" ]]; then
        pct set "$ctid" -"${disk_key}" "${vol_value},${old_mp_opts}"
      else
        pct set "$ctid" -"${disk_key}" "${vol_value}"
      fi
      ;;
  esac
}

# =============================================================================
# Rollback metadata and operations
# =============================================================================

# Save the pre-operation state so that rollback can restore it later.
# Stored as a simple KEY=VALUE file in META_DIR.
save_rollback_metadata() {
  local ctid=$1
  local disk_key=$2
  local old_vol=$3
  local new_vol=$4
  local old_size=${5:-}

  mkdir -p "$META_DIR"
  cat >"${META_DIR}/${ctid}.meta" <<EOF
CTID=$ctid
DISK_KEY=$disk_key
OLD_VOL=$old_vol
NEW_VOL=$new_vol
OLD_SIZE=${old_size}
TIMESTAMP=$(date +%s)
EOF
}

# Roll back a resize operation: remove the new volume and restore the old config.
# For ZFS subvolumes, the refquota is restored instead of performing a volume swap.
rollback_operation() {
  local ctid=$1
  local disk_key=$2
  local old_vol=$3
  local new_vol=$4

  msg_info "Rolling back operation..."
  log "ROLLBACK CTID=$ctid DISK_KEY=$disk_key OLD_VOL=$old_vol NEW_VOL=$new_vol"

  # Load the old size from saved metadata
  local old_size=""
  if [[ -f "${META_DIR}/${ctid}.meta" ]]; then
    # shellcheck source=/dev/null
    source "${META_DIR}/${ctid}.meta"
    old_size="${OLD_SIZE:-}"
  fi

  # Stop the container if it is currently running
  if [[ "$(pct status "$ctid" 2>/dev/null)" == "status: running" ]]; then
    pct stop "$ctid"
    sleep 3
  fi

  # ZFS subvol rollback: restore the original refquota value
  local storage="${old_vol%%:*}"
  local vol_name="${old_vol#*:}"
  local stype
  stype=$(get_storage_type "$storage")

  if [[ "$stype" == "zfspool" ]]; then
    local zfs_ds ds_type
    zfs_ds=$(get_zfs_dataset "$storage" "$vol_name")
    ds_type=$(zfs get -H -o value type "$zfs_ds" 2>/dev/null || echo "")
    if [[ "$ds_type" == "filesystem" && -n "$old_size" ]]; then
      msg_info "Restoring refquota to ${old_size}..."
      zfs set refquota="${old_size}" "$zfs_ds"
      msg_ok "refquota restored"
      log "ROLLBACK_REFQUOTA old_size=$old_size"
      pct start "$ctid"
      sleep 3
      msg_ok "Rollback completed"
      log "ROLLBACK_OK CTID=$ctid"
      return 0
    fi
  fi

  # LVM / zvol / directory rollback: remove the new volume, restore old config
  remove_volume "$new_vol"
  replace_volume_in_config "$ctid" "$disk_key" "$old_vol" "$old_size"

  pct start "$ctid"
  sleep 3

  msg_ok "Rollback completed"
  log "ROLLBACK_OK CTID=$ctid"
}

# =============================================================================
# Input validation
# =============================================================================

# Validate all inputs before starting a resize operation.
# Checks: container existence, disk key in config, size format, and that the
# target size is between used space and current maximum.
validate_inputs() {
  local ctid=$1
  local disk_key=$2
  local target_size=$3

  if ! pct status "$ctid" >/dev/null 2>&1; then
    echo "Error: Container $ctid does not exist."
    return 1
  fi

  local config_line
  config_line=$(pct config "$ctid" 2>/dev/null | awk "/^${disk_key}:/ {print}")
  if [[ -z "$config_line" ]]; then
    echo "Error: Disk '$disk_key' not found in container $ctid."
    return 1
  fi

  if ! [[ "$target_size" =~ ^[0-9]+(\.[0-9]+)?[KMGTPkmgtp]?$ ]]; then
    echo "Error: Invalid size format '$target_size'. Use e.g. 3G, 500M, 1500MB, or a bare number for GB."
    return 1
  fi

  local used_bytes max_bytes new_bytes
  used_bytes=$(get_used_bytes "$ctid" "$disk_key")
  max_bytes=$(get_max_bytes "$ctid" "$disk_key")
  new_bytes=$(parse_size_to_bytes "$target_size")

  if ((new_bytes == 0)); then
    echo "Error: Target size resolves to 0 bytes."
    return 1
  fi

  # Target must be strictly less than current max (we are shrinking)
  if ((new_bytes >= max_bytes)) && ((max_bytes > 0)); then
    echo "Error: Target size ($(bytes_to_human "$new_bytes")) must be less than current size ($(bytes_to_human "$max_bytes"))."
    return 1
  fi

  # Target must be strictly greater than used space
  if ((new_bytes <= used_bytes)) && ((used_bytes > 0)); then
    echo "Error: Target size ($(bytes_to_human "$new_bytes")) must be greater than used space ($(bytes_to_human "$used_bytes"))."
    return 1
  fi

  return 0
}

# =============================================================================
# Interactive UI (whiptail menus)
# =============================================================================

# Present a radio-list of all LXC containers and return the selected CTID.
select_container() {
  mapfile -t containers < <(pct list | tail -n +2)

  if [[ ${#containers[@]} -eq 0 ]]; then
    whiptail --title "LXC Disk Resize" --msgbox "No LXC containers found!" 8 50
    exit 1
  fi

  local menu_items=()
  for line in "${containers[@]}"; do
    local cid cname cstatus cos
    cid=$(echo "$line" | awk '{print $1}')
    cname=$(echo "$line" | awk '{print $2}')
    cstatus=$(echo "$line" | awk '{print $3}')
    cos=$(echo "$line" | awk '{print $4}')
    local desc
    desc=$(printf "%-20s %-10s %-15s" "$cname" "$cstatus" "$cos")
    menu_items+=("$cid" "$desc" "OFF")
  done

  msg_info "Loading containers..." >&2
  local selected
  selected=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Select Container" \
    --radiolist "\nSelect an LXC container to resize:" \
    22 78 12 "${menu_items[@]}" 3>&1 1>&2 2>&3) || exit 0

  echo "$selected"
}

# Present a radio-list of disks for the given container and return the selected disk key.
select_disk() {
  local ctid=$1
  local config_lines
  config_lines=$(pct config "$ctid" | awk '/^(rootfs|mp[0-9]+):/ {print}')

  if [[ -z "$config_lines" ]]; then
    whiptail --title "LXC Disk Resize" --msgbox "No disks found in container $ctid!" 8 50
    exit 1
  fi

  msg_info "Loading disks..." >&2
  local menu_items=()
  while IFS= read -r line; do
    local key
    key=$(echo "$line" | awk -F'[: ,]' '{print $1}')
    local storage
    storage=$(echo "$line" | awk -F'[: ,]' '{print $2}')
    local size_str
    size_str=$(echo "$line" | grep -oP 'size=\K[^ ,]+' || echo "N/A")
    local stype
    stype=$(get_storage_type "$storage")
    local desc="${key}  |  ${storage} (${stype})  |  ${size_str}"
    menu_items+=("$key" "$desc" "OFF")
  done <<<"$config_lines"

  local selected
  selected=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Select Disk" \
    --radiolist "\nSelect disk to resize:" \
    20 78 10 "${menu_items[@]}" 3>&1 1>&2 2>&3) || exit 0

  echo "$selected"
}

# Prompt for target size interactively, with validation loop and sensible defaults.
# Default suggestion: used_space * 1.2 (with minimum of 1G and maximum of current_size - 1).
get_target_size() {
  local ctid=$1
  local disk_key=$2

  local used_bytes max_bytes
  used_bytes=$(get_used_bytes "$ctid" "$disk_key")
  max_bytes=$(get_max_bytes "$ctid" "$disk_key")

  local used_gb max_gb default_size
  used_gb=$((used_bytes / 1073741824))
  max_gb=$((max_bytes / 1073741824))

  if ((used_gb > 0)); then
    default_size=$((used_gb + used_gb / 5 + 1))
  else
    default_size=2
  fi
  if ((default_size >= max_gb)) && ((max_gb > 0)); then
    default_size=$((max_gb - 1))
  fi
  if ((default_size < 1)); then
    default_size=1
  fi

  msg_info "Calculating disk usage..." >&2
  local hint=""
  if ((used_bytes > 0)); then
    hint="Current: $(bytes_to_human "$max_bytes") | Used: $(bytes_to_human "$used_bytes")\nMust be > $(bytes_to_human "$used_bytes") and < $(bytes_to_human "$max_bytes")"
  else
    hint="Current: $(bytes_to_human "$max_bytes")\nMust be < $(bytes_to_human "$max_bytes")"
  fi

  while true; do
    local target_size
    target_size=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "Target Size" \
      --inputbox "\n${hint}\n\nExamples: 3G, 500M, 1500MB, 2 (defaults to GB)" \
      14 60 "$default_size" 3>&1 1>&2 2>&3) || exit 0

    [[ -z "$target_size" ]] && continue

    # Strip whitespace
    target_size="${target_size// /}"

    # Bare number is treated as gigabytes
    if [[ "$target_size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      target_size="${target_size}G"
    fi

    local validation_error
    if validation_error=$(validate_inputs "$ctid" "$disk_key" "$target_size" 2>&1); then
      echo "$target_size"
      return 0
    else
      log "VALIDATION_FAIL size=$target_size error=$validation_error"
      msg_error "${TAB}✘ ${validation_error}" >&2
      whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "Error" --msgbox "\n${validation_error}" 10 60 2>/dev/null || true
    fi
  done
}

# Show a confirmation dialog with all operation details before proceeding.
confirm_operation() {
  local ctid=$1
  local disk_key=$2
  local target_size=$3

  local container_name
  container_name=$(pct config "$ctid" | awk '/^hostname:/ {print $2}')
  local current_size
  current_size=$(get_size_from_config "$ctid" "$disk_key")
  local storage
  storage=$(get_storage_for_disk "$ctid" "$disk_key")
  local stype
  stype=$(get_storage_type "$storage")

  local msg="Container: ${ctid} (${container_name})\n"
  msg+="Disk: ${disk_key}\n"
  msg+="Storage: ${storage} (${stype})\n"
  msg+="Current size: ${current_size}\n"
  msg+="New size: ${target_size}\n\n"
  msg+="The container will be stopped during the operation.\n"
  msg+="Proceed?"

  whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Confirm Resize" \
    --yesno "$msg" 16 60 || exit 0
}

# Show a post-operation menu: delete old volume, keep it, or rollback.
post_operation() {
  local ctid=$1
  local disk_key=$2
  local old_vol=$3
  local new_vol=$4

  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Post-Operation" \
    --menu "\nResize complete. What to do with the old volume?\n\nOld: ${old_vol}\nNew: ${new_vol}" \
    14 70 3 \
    "1" "Delete old volume" \
    "2" "Keep old volume (do nothing)" \
    "3" "Rollback to original" \
    3>&1 1>&2 2>&3) || choice="2"

  case "$choice" in
    1)
      msg_info "Deleting old volume..."
      remove_volume "$old_vol"
      msg_ok "Old volume deleted"
      log "POST_DELETE old_vol=$old_vol"
      ;;
    3)
      rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
      ;;
    *)
      msg_info "Old volume kept"
      log "POST_KEEP old_vol=$old_vol"
      ;;
  esac
}

# =============================================================================
# Resize strategies
# =============================================================================

# Resize a ZFS subvolume by adjusting its refquota.
# This is the fast path — no data copy needed, just a metadata update.
# Falls back to the dd-based approach if the refquota change fails verification
# and the user opts in.
#
# Returns 0 on success, 1 on failure.
resize_zfs_subvol() {
  local ctid=$1
  local disk_key=$2
  local target_size=$3
  local storage=$4
  local vol_name=$5
  local current_size=$6

  local zfs_ds ds_type
  zfs_ds=$(get_zfs_dataset "$storage" "$vol_name")
  ds_type=$(zfs get -H -o value type "$zfs_ds" 2>/dev/null || echo "")

  # Only proceed if this is a ZFS filesystem (subvol), not a zvol
  if [[ "$ds_type" != "filesystem" ]]; then
    return 1  # Signal caller to fall through to dd approach
  fi

  msg_info "ZFS subvol — shrinking via refquota"
  log "MODE=refquota zfs_ds=$zfs_ds"

  # Validate: current used space must fit within the new quota
  local used_bytes target_bytes
  used_bytes=$(zfs get -H -o value used "$zfs_ds" 2>/dev/null || echo "0")
  used_bytes=$(parse_size_to_bytes "$used_bytes")
  target_bytes=$(parse_size_to_bytes "$target_size")

  if ((used_bytes >= target_bytes)); then
    msg_error "Error: Used space ($(bytes_to_human "$used_bytes")) >= target size (${target_size})"
    log "ERROR used_space_exceeds_target"
    return 1
  fi

  # Step 1: Stop the container
  msg_info "Step 1/4: Stopping container..."
  log "STEP1_STOPPING ctid=$ctid"
  if [[ "$(pct status "$ctid" 2>/dev/null)" == "status: running" ]]; then
    pct stop "$ctid" &
    spinner $! "Stopping container"
  fi
  msg_ok "Container stopped"
  log "STEP1_OK"

  # Step 2: Set the new refquota
  msg_info "Step 2/4: Setting refquota to ${target_size}..."
  log "STEP2_REFQUOTA ds=$zfs_ds size=$target_size"
  zfs set refquota="${target_size}" "$zfs_ds" &
  spinner $! "Setting refquota"
  msg_ok "refquota updated"
  log "STEP2_OK refquota=$target_size"

  # Step 3: Start the container
  msg_info "Step 3/4: Starting container..."
  log "STEP3_STARTING ctid=$ctid"
  pct start "$ctid" &
  spinner $! "Starting container"
  sleep 5
  msg_ok "Container started"
  log "STEP3_OK"

  # Step 4: Verify the resize took effect
  msg_info "Step 4/4: Verifying resize..."
  sleep 2
  local actual_size
  actual_size=$(pct df "$ctid" 2>/dev/null | awk '$1 == "rootfs" {print $3}')
  local actual_status
  actual_status=$(pct status "$ctid" 2>/dev/null)

  if [[ "$actual_status" == "status: running" ]]; then
    msg_ok "Container is running"
    log "VERIFY_OK status=running"
  else
    msg_error "Container is not running!"
    log "VERIFY_FAIL status=$actual_status"
  fi

  if [[ -n "$actual_size" ]]; then
    msg_ok "Disk size: ${actual_size}"
    log "VERIFY_OK size=$actual_size expected=$target_size"

    # Allow 5% tolerance for unit rounding
    local actual_bytes expected_bytes diff pct_diff
    actual_bytes=$(parse_size_to_bytes "$actual_size")
    expected_bytes=$(parse_size_to_bytes "$target_size")
    if ((actual_bytes > expected_bytes)); then
      diff=$((actual_bytes - expected_bytes))
    else
      diff=$((expected_bytes - actual_bytes))
    fi
    pct_diff=$((diff * 100 / expected_bytes))
    if ((pct_diff > 5)); then
      msg_error "Size mismatch: expected ${target_size}, got ${actual_size}"
      log "VERIFY_FAIL size_mismatch expected=$target_size actual=$actual_size"
      echo -e "${YW}${TAB}Would you like to retry with dd copy instead? (y/N)${CL}"
      read -rp "${TAB}Choice: " dd_retry
      if [[ "$dd_retry" =~ ^[Yy]$ ]]; then
        msg_info "Falling back to dd copy approach..."
        log "FALLBACK_DD"
        return 1  # Signal caller to fall through to dd approach
      else
        log "FALLBACK_DECLINED"
        return 1
      fi
    else
      log "SUCCESS CTID=$ctid DISK_KEY=$disk_key OLD=$current_size NEW=$target_size MODE=refquota"
      return 0
    fi
  else
    msg_error "Could not read disk size"
    log "VERIFY_FAIL size_unknown"
    return 1
  fi
}

# Resize via the dd copy approach: create a smaller volume, copy data, verify,
# swap the config, and start the container.
#
# This is the universal fallback for LVM, LVM-thin, ZFS zvols, and directory
# storage.  On any failure during the critical section, the operation is
# automatically rolled back.
#
# Returns 0 on success, 1 on failure.
resize_via_dd() {
  local ctid=$1
  local disk_key=$2
  local target_size=$3
  local storage=$4
  local vol_name=$5
  local current_size=$6
  local old_vol="${storage}:${vol_name}"

  msg_info "Using dd copy approach"
  log "MODE=dd old_vol=$old_vol"

  # Step 1: Create the new smaller volume
  msg_info "Step 1/7: Creating new volume..."
  log "STEP1_CREATE_VOL ctid=$ctid disk=$disk_key size=$target_size"
  local new_vol
  new_vol=$(create_new_volume "$ctid" "$disk_key" "$target_size")
  if [[ -z "$new_vol" ]]; then
    msg_error "Error: Failed to create new volume"
    log "ERROR create_new_volume failed"
    return 1
  fi
  msg_ok "New volume created: ${new_vol}"
  log "STEP1_OK new_vol=$new_vol"

  # Step 2: Stop the container
  msg_info "Step 2/7: Stopping container..."
  log "STEP2_STOPPING ctid=$ctid"
  if [[ "$(pct status "$ctid" 2>/dev/null)" == "status: running" ]]; then
    pct stop "$ctid" &
    spinner $! "Stopping container"
  fi
  msg_ok "Container stopped"
  log "STEP2_OK"

  # Step 3: Copy data from old volume to new volume
  msg_info "Step 3/7: Copying data..."
  local source_dev dest_dev
  source_dev=$(get_device_path "$old_vol")
  dest_dev=$(get_device_path "$new_vol")

  if [[ -z "$source_dev" || -z "$dest_dev" ]]; then
    msg_error "Error: Could not resolve device paths"
    msg_error "Source: ${source_dev:-<none>}, Dest: ${dest_dev:-<none>}"
    log "ERROR device_path source=$source_dev dest=$dest_dev"
    rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
    return 1
  fi

  local source_bytes
  source_bytes=$(get_max_bytes "$ctid" "$disk_key")

  echo -e "${TAB}Source: ${source_dev} ($(bytes_to_human "$source_bytes"))"
  echo -e "${TAB}Dest:   ${dest_dev} (${target_size})"
  log "STEP3_COPY src=$source_dev dst=$dest_dev bytes=$source_bytes"

  if ! copy_data "$source_dev" "$dest_dev" "$source_bytes"; then
    msg_error "Error: Data copy failed"
    log "ERROR copy_data failed"
    rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
    return 1
  fi
  msg_ok "Data copied"
  log "STEP3_OK"

  # Step 4: Verify data integrity via MD5 checksum comparison
  msg_info "Step 4/7: Verifying checksum..."
  log "STEP4_CHECKSUM src=$source_dev dst=$dest_dev"
  if ! verify_checksum "$source_dev" "$dest_dev" "$source_bytes"; then
    msg_error "Error: Checksum mismatch — data corruption detected"
    log "ERROR checksum_mismatch"
    rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
    return 1
  fi
  msg_ok "Checksum verified"
  log "STEP4_OK"

  # Step 5: Swap the volume reference in the container config
  msg_info "Step 5/7: Replacing volume in config..."
  log "STEP5_REPLACE ctid=$ctid disk=$disk_key new=$new_vol size=$target_size"
  save_rollback_metadata "$ctid" "$disk_key" "$old_vol" "$new_vol" "$current_size"
  replace_volume_in_config "$ctid" "$disk_key" "$new_vol" "$target_size"
  msg_ok "Volume replaced"
  log "STEP5_OK"

  # Step 6: Start the container
  msg_info "Step 6/7: Starting container..."
  log "STEP6_STARTING ctid=$ctid"
  pct start "$ctid" &
  spinner $! "Starting container"
  sleep 3
  msg_ok "Container started"
  log "STEP6_OK"

  # Step 7: Verify the container is healthy and running
  msg_info "Step 7/7: Verifying container health..."
  if [[ "$(pct status "$ctid" 2>/dev/null)" == "status: running" ]]; then
    msg_ok "Container is running"
    log "STEP7_OK status=running"
  else
    msg_error "Warning: Container is not running after start"
    log "STEP7_WARN status=$(pct status "$ctid" 2>/dev/null)"
  fi

  log "SUCCESS CTID=$ctid DISK_KEY=$disk_key OLD=$current_size NEW=$target_size OLD_VOL=$old_vol NEW_VOL=$new_vol"

  # Handle the old volume: auto-rollback, interactive prompt, or keep
  if [[ "${AUTO_ROLLBACK:-0}" -eq 1 ]]; then
    msg_info "Auto-rollback requested, reverting to original..."
    rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
  else
    post_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
  fi

  return 0
}

# =============================================================================
# Main resize orchestrator
# =============================================================================

# Entry point for the resize operation.  Detects the storage type and delegates
# to the appropriate strategy (ZFS refquota or dd copy).
do_resize() {
  local ctid=$1
  local disk_key=$2
  local target_size=$3

  block_interrupts
  log "START CTID=$ctid DISK_KEY=$disk_key TARGET=$target_size"
  msg_info "Detecting storage type..."

  local storage
  storage=$(get_storage_for_disk "$ctid" "$disk_key")
  local stype
  stype=$(get_storage_type "$storage")
  local vol_name
  vol_name=$(get_volume_name "$ctid" "$disk_key")
  local current_size
  current_size=$(get_size_from_config "$ctid" "$disk_key")

  msg_info "Resizing ${disk_key} on container ${ctid} from ${current_size} to ${target_size}"
  log "INFO storage_type=$stype current_size=$current_size"

  local rc=0

  # Try ZFS subvol (refquota) path first for zfspool storage
  if [[ "$stype" == "zfspool" ]]; then
    msg_info "Probing ZFS dataset..."
    if resize_zfs_subvol "$ctid" "$disk_key" "$target_size" "$storage" "$vol_name" "$current_size"; then
      allow_interrupts
      return 0
    fi
    msg_info "ZFS zvol or refquota fallback — switching to dd copy"
  fi

  # Universal dd copy path for LVM, ZFS zvol, and directory storage
  resize_via_dd "$ctid" "$disk_key" "$target_size" "$storage" "$vol_name" "$current_size"
  rc=$?

  allow_interrupts
  return $rc
}

# =============================================================================
# CLI help
# =============================================================================

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Shrink an LXC container disk by creating a smaller copy and swapping volumes.

Options:
  -d, --ctid ID        Container ID
  -k, --disk KEY       Disk key (rootfs, mp0, mp1, ...)
  -s, --size SIZE      Target size (e.g. 8G, 500M, 16)
  -y, --yes            Skip confirmation prompts
  -r, --rollback       Auto-rollback to original after success
  -h, --help           Show this help message

Examples:
  $(basename "$0")                                  # Interactive mode
  $(basename "$0") -d 900 -k rootfs -s 8G -y       # CLI: shrink rootfs to 8G
  $(basename "$0") -d 900 -k mp0 -s 2G -y -r       # CLI: shrink mp0, rollback after

Interactive mode guides you through container, disk, and size selection.
CLI mode requires --ctid, --disk, and --size.
EOF
}

# =============================================================================
# Entry point
# =============================================================================

CTID=""
DISK_KEY=""
TARGET_SIZE=""
AUTO_YES=0
AUTO_ROLLBACK=0

while [[ $# -gt 0 ]]; do
  case $1 in
    -d | --ctid) CTID="$2"; shift 2 ;;
    -k | --disk) DISK_KEY="$2"; shift 2 ;;
    -s | --size) TARGET_SIZE="$2"; shift 2 ;;
    -y | --yes) AUTO_YES=1; shift ;;
    -r | --rollback) AUTO_ROLLBACK=1; shift ;;
    -h | --help) show_help; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

CLI_MODE=0
if [[ -n "$CTID" && -n "$DISK_KEY" && -n "$TARGET_SIZE" ]]; then
  CLI_MODE=1
fi

header_info

# Non-interactive (CLI) mode: all three parameters were provided on the command line
if [[ $CLI_MODE -eq 1 ]]; then
  # Normalize bare number to GB
  if [[ "$TARGET_SIZE" =~ ^[0-9]+$ ]]; then
    TARGET_SIZE="${TARGET_SIZE}G"
  fi

  if ! validate_inputs "$CTID" "$DISK_KEY" "$TARGET_SIZE"; then
    exit 1
  fi

  if [[ $AUTO_YES -eq 0 ]]; then
    confirm_operation "$CTID" "$DISK_KEY" "$TARGET_SIZE"
  fi

  do_resize "$CTID" "$DISK_KEY" "$TARGET_SIZE"
  exit $?
fi

# Interactive mode: guide the user through selection menus
CTID=$(select_container) || exit 0
[[ -z "$CTID" ]] && exit 0
DISK_KEY=$(select_disk "$CTID") || exit 0
[[ -z "$DISK_KEY" ]] && exit 0
TARGET_SIZE=$(get_target_size "$CTID" "$DISK_KEY") || exit 0
[[ -z "$TARGET_SIZE" ]] && exit 0
confirm_operation "$CTID" "$DISK_KEY" "$TARGET_SIZE" || exit 0
do_resize "$CTID" "$DISK_KEY" "$TARGET_SIZE"

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# LXC Disk Resize — shrink LXC container disks safely via dd copy + checksum verification.
# Supports LVM, LVM-thin, ZFS, and directory-based storage.

set -eEuo pipefail
export PERL_BADLANG=0

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

BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
YW="\033[33m"
CL="\033[m"
TAB="  "

LOGFILE="/var/log/lxc-resize.log"

# Ctrl+C handling: safe during menus, blocked during critical operations
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

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >>"$LOGFILE"
}

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

run_with_spinner() {
  local msg=$1
  shift
  echo -e "${BL}[Info]${GN} ${msg}...${CL}"
  log "SPINNER $msg"
  "$@" &
  local pid=$!
  spinner "$pid" "$msg"
  wait "$pid"
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    echo -e "${GN}${TAB}✔${CL} ${GN}${msg} — done${CL}"
    log "DONE $msg"
  else
    echo -e "${RD}${TAB}✘${CL} ${RD}${msg} — failed (exit $rc)${CL}"
    log "FAIL $msg exit=$rc"
  fi
  return $rc
}

progress_bar() {
  local label=$1
  local total=$2
  local current=0
  local width=40
  echo -e "${BL}[Info]${GN} ${label}...${CL}"
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
  echo -e "${GN}${TAB}✔${CL} ${GN}${label} — done${CL}"
  log "PROGRESS_DONE $label"
}

# --- Size helpers ---

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

# --- Storage helpers ---

get_storage_type() {
  local storage="$1"
  pvesm status | awk -v st="$storage" '$1 == st {print $2}'
}

get_volume_path() {
  local vol="$1"
  pvesm path "$vol" 2>/dev/null
}

# Get the ZFS pool name for a Proxmox storage ID (e.g. "local-zfs" -> "rpool/data")
get_zfs_pool() {
  local storage="$1"
  # Parse /etc/pve/storage.cfg for the pool line under this zfspool entry
  awk -v st="$storage" '
    /^zfspool:/ { match_name = ($2 == st) }
    match_name && /^[\t ]+pool / { print $2; exit }
  ' /etc/pve/storage.cfg 2>/dev/null
}

# Get full ZFS dataset path (e.g. "rpool/data/subvol-999-disk-0")
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

# Get the LV name for a ctid + disk key from pct config
get_lv_name() {
  local ctid=$1
  local disk_key=$2
  local config_line
  config_line=$(pct config "$ctid" | awk "/^${disk_key}:/ {print}")
  # Config format: "rootfs: local-zfs:subvol-999-disk-0,size=4G"
  # Extract volume name: field 3 after splitting by colon, then strip options after comma
  echo "$config_line" | cut -d: -f3 | cut -d, -f1
}

get_storage_for_disk() {
  local ctid=$1
  local disk_key=$2
  local config_line
  config_line=$(pct config "$ctid" | awk "/^${disk_key}:/ {print}")
  # Config format: "rootfs: local-zfs:subvol-999-disk-0,size=4G"
  # Extract storage: after first ": ", before next ":"
  echo "$config_line" | awk -F": " '{print $2}' | cut -d: -f1
}

get_size_from_config() {
  local ctid=$1
  local disk_key=$2
  local config_line
  config_line=$(pct config "$ctid" | awk "/^${disk_key}:/ {print}")
  echo "$config_line" | grep -oP 'size=\K[^ ,]+'
}

get_used_bytes() {
  local ctid=$1
  local disk_key=$2
  # pct df gives: MP Volume Size Used Avail Use% Path
  # rootfs local-zfs:subvol-108-disk-0 10.0G 2.4G 7.6G 23.9 /
  local used
  used=$(pct df "$ctid" 2>/dev/null | awk -v dk="$disk_key" '$1 == dk {print $4}')
  if [[ -n "$used" ]]; then
    parse_size_to_bytes "$used"
  else
    echo "0"
  fi
}

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

# --- Volume operations per storage type ---

create_new_volume() {
  local ctid=$1
  local disk_key=$2
  local new_size=$3
  local storage
  storage=$(get_storage_for_disk "$ctid" "$disk_key")
  local storage_type
  storage_type=$(get_storage_type "$storage")

  # Find next available disk number for this container
  local max_disk=-1
  local vol
  for vol in $(pct config "$ctid" 2>/dev/null | awk -F'[: ,]' '/^(rootfs|mp[0-9]+)/ {print $4}'); do
    local disk_num
    disk_num=$(echo "$vol" | grep -oP 'disk-\K[0-9]+' || echo "-1")
    if [[ "$disk_num" =~ ^[0-9]+$ ]] && ((disk_num > max_disk)); then
      max_disk=$disk_num
    fi
  done
  local next_disk=$((max_disk + 1))

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

get_device_path() {
  local vol="$1"
  local storage="${vol%%:*}"
  local vol_name="${vol#*:}"
  local storage_type
  storage_type=$(get_storage_type "$storage")

  case $storage_type in
    lvmthin|lvm)
      local vg_name
      vg_name=$(lvs --noheadings -o vg_name 2>/dev/null | awk -v lv="$vol_name" '$1 == lv {print $1}')
      if [[ -z "$vg_name" ]]; then
        vg_name=$(lvs --noheadings -o vg_name 2>/dev/null | head -1 | tr -d ' ')
      fi
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

remove_volume() {
  local vol="$1"
  local storage="${vol%%:*}"
  local vol_name="${vol#*:}"
  local storage_type
  storage_type=$(get_storage_type "$storage")

  case $storage_type in
    lvmthin|lvm)
      local vg_name
      vg_name=$(lvs --noheadings -o vg_name 2>/dev/null | awk -v lv="$vol_name" '$1 == lv {print $1}')
      if [[ -z "$vg_name" ]]; then
        vg_name=$(lvs --noheadings -o vg_name 2>/dev/null | head -1 | tr -d ' ')
      fi
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

copy_data() {
  local source_dev="$1"
  local dest_dev="$2"
  local source_size=$3

  local bs=1M
  local count=$((source_size / 1048576))
  if ((count < 1)); then
    count=1
  fi

  dd if="$source_dev" of="$dest_dev" bs="$bs" count="$count" status=progress 2>&1
}

verify_checksum() {
  local source_dev="$1"
  local dest_dev="$2"
  local source_size=$3

  local bs=1M
  local count=$((source_size / 1048576))
  if ((count < 1)); then
    count=1
  fi

  local source_hash dest_hash
  source_hash=$(dd if="$source_dev" bs="$bs" count="$count" 2>/dev/null | md5sum | awk '{print $1}')
  dest_hash=$(dd if="$dest_dev" bs="$bs" count="$count" 2>/dev/null | md5sum | awk '{print $1}')

  if [[ "$source_hash" == "$dest_hash" ]]; then
    return 0
  else
    return 1
  fi
}

replace_volume_in_config() {
  local ctid=$1
  local disk_key=$2
  local new_vol=$3
  local new_size=${4:-}

  local storage="${new_vol%%:*}"
  local vol_name="${new_vol#*:}"

  # Build the value for pct set with size
  local vol_value="${storage}:${vol_name}"
  if [[ -n "$new_size" ]]; then
    vol_value="${vol_value},size=${new_size}"
  fi

  # Remove old disk config
  pct set "$ctid" --delete "$disk_key"

  # Re-add with new volume
  case $disk_key in
    rootfs)
      pct set "$ctid" --rootfs "${vol_value}"
      ;;
    mp[0-9]*)
      # Preserve mount options from old config
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

save_rollback_metadata() {
  local ctid=$1
  local disk_key=$2
  local old_vol=$3
  local new_vol=$4
  local old_size=${5:-}

  local meta_dir="/var/lib/lxc-resize"
  mkdir -p "$meta_dir"
  cat >"${meta_dir}/${ctid}.meta" <<EOF
CTID=$ctid
DISK_KEY=$disk_key
OLD_VOL=$old_vol
NEW_VOL=$new_vol
OLD_SIZE=${old_size}
TIMESTAMP=$(date +%s)
EOF
}

load_rollback_metadata() {
  local ctid=$1
  local meta_dir="/var/lib/lxc-resize"
  if [[ -f "${meta_dir}/${ctid}.meta" ]]; then
    # shellcheck source=/dev/null
    source "${meta_dir}/${ctid}.meta"
  fi
}

rollback_operation() {
  local ctid=$1
  local disk_key=$2
  local old_vol=$3
  local new_vol=$4

  echo -e "${BL}[Info]${YW} Rolling back operation...${CL}"
  log "ROLLBACK CTID=$ctid DISK_KEY=$disk_key OLD_VOL=$old_vol NEW_VOL=$new_vol"

  # Load metadata for old size
  local old_size=""
  local meta_dir="/var/lib/lxc-resize"
  if [[ -f "${meta_dir}/${ctid}.meta" ]]; then
    # shellcheck source=/dev/null
    source "${meta_dir}/${ctid}.meta"
    old_size="${OLD_SIZE:-}"
  fi

  # Stop container if running
  if [[ "$(pct status "$ctid" 2>/dev/null)" == "status: running" ]]; then
    pct stop "$ctid"
    sleep 3
  fi

  # ZFS subvol rollback: restore refquota
  local storage="${old_vol%%:*}"
  local vol_name="${old_vol#*:}"
  local stype
  stype=$(get_storage_type "$storage")

  if [[ "$stype" == "zfspool" ]]; then
    local zfs_ds ds_type
    zfs_ds=$(get_zfs_dataset "$storage" "$vol_name")
    ds_type=$(zfs get -H -o value type "$zfs_ds" 2>/dev/null || echo "")
    if [[ "$ds_type" == "filesystem" && -n "$old_size" ]]; then
      echo -e "${BL}[Info]${GN} Restoring refquota to ${old_size}...${CL}"
      zfs set refquota="${old_size}" "$zfs_ds"
      echo -e "${GN}${TAB}✔${CL} ${GN}refquota restored${CL}"
      log "ROLLBACK_REFQUOTA old_size=$old_size"
      pct start "$ctid"
      sleep 3
      echo -e "${GN}${TAB}✔${CL} ${GN}Rollback completed${CL}"
      log "ROLLBACK_OK CTID=$ctid"
      return 0
    fi
  fi

  # LVM / zvol / dir rollback: remove new volume, restore config
  remove_volume "$new_vol"
  replace_volume_in_config "$ctid" "$disk_key" "$old_vol" "$old_size"

  # Start container
  pct start "$ctid"
  sleep 3

  echo -e "${GN}${TAB}✔${CL} ${GN}Rollback completed${CL}"
  log "ROLLBACK_OK CTID=$ctid"
}

# --- Validation ---

validate_inputs() {
  local ctid=$1
  local disk_key=$2
  local target_size=$3

  # Validate container exists
  if ! pct status "$ctid" >/dev/null 2>&1; then
    echo "Error: Container $ctid does not exist."
    return 1
  fi

  # Validate disk key exists
  local config_line
  config_line=$(pct config "$ctid" 2>/dev/null | awk "/^${disk_key}:/ {print}")
  if [[ -z "$config_line" ]]; then
    echo "Error: Disk '$disk_key' not found in container $ctid."
    return 1
  fi

  # Validate target size format
  if ! [[ "$target_size" =~ ^[0-9]+(\.[0-9]+)?[KMGTPkmgtp]?$ ]]; then
    echo "Error: Invalid size format '$target_size'. Use e.g. 3G, 500M, 1500MB, or a bare number for GB."
    return 1
  fi

  # Get current sizes
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

# --- Interactive UI ---

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
    desc=$(printf "%-8s %-20s %-10s %-15s" "$cid" "$cname" "$cstatus" "$cos")
    menu_items+=("$cid" "$desc" "OFF")
  done

  echo -e "${BL}[Info]${GN} Loading containers...${CL}" >&2
  local selected
  selected=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Select Container" \
    --radiolist "\nSelect an LXC container to resize:" \
    22 78 12 "${menu_items[@]}" 3>&1 1>&2 2>&3) || exit 0

  echo "$selected"
}

select_disk() {
  local ctid=$1
  local config_lines
  config_lines=$(pct config "$ctid" | awk '/^(rootfs|mp[0-9]+):/ {print}')

  if [[ -z "$config_lines" ]]; then
    whiptail --title "LXC Disk Resize" --msgbox "No disks found in container $ctid!" 8 50
    exit 1
  fi

  echo -e "${BL}[Info]${GN} Loading disks...${CL}" >&2
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

get_target_size() {
  local ctid=$1
  local disk_key=$2

  local used_bytes max_bytes
  used_bytes=$(get_used_bytes "$ctid" "$disk_key")
  max_bytes=$(get_max_bytes "$ctid" "$disk_key")

  local used_gb max_gb default_size
  used_gb=$((used_bytes / 1073741824))
  max_gb=$((max_bytes / 1073741824))

  # Suggest used * 1.2
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

  echo -e "${BL}[Info]${GN} Calculating disk usage...${CL}" >&2
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

    # Strip spaces
    target_size="${target_size// /}"

    # Bare number = GB
    if [[ "$target_size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      target_size="${target_size}G"
    fi

    local validation_error
    if validation_error=$(validate_inputs "$ctid" "$disk_key" "$target_size" 2>&1); then
      echo "$target_size"
      return 0
    else
      log "VALIDATION_FAIL size=$target_size error=$validation_error"
      echo -e "${RD}${TAB}✘ ${validation_error}${CL}" >&2
      whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "Error" --msgbox "\n${validation_error}" 10 60 2>/dev/null || true
    fi
  done
}

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

# --- Main resize operation ---

do_resize() {
  local ctid=$1
  local disk_key=$2
  local target_size=$3

  block_interrupts
  log "START CTID=$ctid DISK_KEY=$disk_key TARGET=$target_size"
  echo -e "${BL}[Info]${GN} Detecting storage type...${CL}"

  local storage
  storage=$(get_storage_for_disk "$ctid" "$disk_key")
  local stype
  stype=$(get_storage_type "$storage")
  local vol_name
  vol_name=$(get_lv_name "$ctid" "$disk_key")
  local old_vol="${storage}:${vol_name}"
  local current_size
  current_size=$(get_size_from_config "$ctid" "$disk_key")

  echo -e "${BL}[Info]${GN} Resizing ${disk_key} on container ${ctid} from ${current_size} to ${target_size}${CL}"
  log "INFO old_vol=$old_vol storage_type=$stype current_size=$current_size"

  # --- ZFS subvol: use refquota (no dd copy needed) ---
  if [[ "$stype" == "zfspool" ]]; then
    echo -e "${BL}[Info]${GN} Probing ZFS dataset...${CL}"
    local zfs_ds ds_type
    zfs_ds=$(get_zfs_dataset "$storage" "$vol_name")
    ds_type=$(zfs get -H -o value type "$zfs_ds" 2>/dev/null || echo "")

    if [[ "$ds_type" == "filesystem" ]]; then
      # ZFS subvol: shrink via refquota
      echo -e "${BL}[Info]${GN} ZFS subvol — shrinking via refquota${CL}"
      log "MODE=refquota zfs_ds=$zfs_ds"

      # Validate: used must fit in new quota
      local used_bytes target_bytes
      used_bytes=$(zfs get -H -o value used "$zfs_ds" 2>/dev/null || echo "0")
      used_bytes=$(parse_size_to_bytes "$used_bytes")
      target_bytes=$(parse_size_to_bytes "$target_size")

      if ((used_bytes >= target_bytes)); then
        echo -e "${RD}Error: Used space ($(bytes_to_human "$used_bytes")) >= target size (${target_size})${CL}"
        log "ERROR used_space_exceeds_target"
        return 1
      fi

      # Step 1: Stop container
      echo -e "${BL}[Info]${GN} Step 1/3: Stopping container...${CL}"
      log "STEP1_STOPPING ctid=$ctid"
      if [[ "$(pct status "$ctid" 2>/dev/null)" == "status: running" ]]; then
        pct stop "$ctid" &
        spinner $! "Stopping container"
      fi
      echo -e "${GN}${TAB}✔${CL} ${GN}Container stopped${CL}"
      log "STEP1_OK"

      # Step 2: Set new refquota
      echo -e "${BL}[Info]${GN} Step 2/3: Setting refquota to ${target_size}...${CL}"
      log "STEP2_REFQUOTA ds=$zfs_ds size=$target_size"
      zfs set refquota="${target_size}" "$zfs_ds" &
      spinner $! "Setting refquota"
      echo -e "${GN}${TAB}✔${CL} ${GN}refquota updated${CL}"
      log "STEP2_OK refquota=$target_size"

      # Step 3: Start container
      echo -e "${BL}[Info]${GN} Step 3/3: Starting container...${CL}"
      log "STEP3_STARTING ctid=$ctid"
      pct start "$ctid" &
      spinner $! "Starting container"
      sleep 5
      echo -e "${GN}${TAB}✔${CL} ${GN}Container started${CL}"
      log "STEP3_OK"

      # Step 4: Verify
      echo -e "${BL}[Info]${GN} Verifying resize...${CL}"
      sleep 2
      local actual_size
      actual_size=$(pct df "$ctid" 2>/dev/null | awk '$1 == "rootfs" {print $3}')
      local actual_status
      actual_status=$(pct status "$ctid" 2>/dev/null)

      if [[ "$actual_status" == "status: running" ]]; then
        echo -e "${GN}${TAB}✔${CL} ${GN}Container is running${CL}"
        log "VERIFY_OK status=running"
      else
        echo -e "${RD}${TAB}✘${CL} ${RD}Container is not running!${CL}"
        log "VERIFY_FAIL status=$actual_status"
      fi

      if [[ -n "$actual_size" ]]; then
        echo -e "${GN}${TAB}✔${CL} ${GN}Disk size: ${actual_size}${CL}"
        log "VERIFY_OK size=$actual_size expected=$target_size"

        # Check if size actually changed (allow 5% tolerance for rounding)
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
          echo -e "${RD}${TAB}✘${CL} ${RD}Size mismatch: expected ${target_size}, got ${actual_size}${CL}"
          log "VERIFY_FAIL size_mismatch expected=$target_size actual=$actual_size"
          echo -e "${YW}${TAB}Would you like to retry with dd copy instead? (y/N)${CL}"
          read -rp "${TAB}Choice: " dd_retry
          if [[ "$dd_retry" =~ ^[Yy]$ ]]; then
            echo -e "${BL}[Info]${GN} Falling back to dd copy approach...${CL}"
            log "FALLBACK_DD"
            # Fall through to dd approach below
          else
            log "FALLBACK_DECLINED"
            return 1
          fi
        else
          log "SUCCESS CTID=$ctid DISK_KEY=$disk_key OLD=$current_size NEW=$target_size MODE=refquota"
          return 0
        fi
      else
        echo -e "${RD}${TAB}✘${CL} ${RD}Could not read disk size${CL}"
        log "VERIFY_FAIL size_unknown"
        return 1
      fi
    fi

    # ZFS zvol: fall through to dd-based approach below
    echo -e "${BL}[Info]${GN} ZFS zvol detected — using dd copy approach${CL}"
  fi

  # --- LVM / ZFS-zvol / directory: dd copy approach ---

  # Step 1: Create new volume
  echo -e "${BL}[Info]${GN} Step 1/7: Creating new volume...${CL}"
  log "STEP1_CREATE_VOL ctid=$ctid disk=$disk_key size=$target_size"
  local new_vol
  new_vol=$(create_new_volume "$ctid" "$disk_key" "$target_size")
  if [[ -z "$new_vol" ]]; then
    echo -e "${RD}Error: Failed to create new volume${CL}"
    log "ERROR create_new_volume failed"
    return 1
  fi
  echo -e "${GN}${TAB}✔${CL} ${GN}New volume created: ${new_vol}${CL}"
  log "STEP1_OK new_vol=$new_vol"

  # Step 2: Stop container
  echo -e "${BL}[Info]${GN} Step 2/7: Stopping container...${CL}"
  log "STEP2_STOPPING ctid=$ctid"
  if [[ "$(pct status "$ctid" 2>/dev/null)" == "status: running" ]]; then
    pct stop "$ctid" &
    spinner $! "Stopping container"
  fi
  echo -e "${GN}${TAB}✔${CL} ${GN}Container stopped${CL}"
  log "STEP2_OK"

  # Step 3: Copy data
  echo -e "${BL}[Info]${GN} Step 3/7: Copying data...${CL}"
  local source_dev dest_dev
  source_dev=$(get_device_path "$old_vol")
  dest_dev=$(get_device_path "$new_vol")

  if [[ -z "$source_dev" || -z "$dest_dev" ]]; then
    echo -e "${RD}Error: Could not resolve device paths${CL}"
    echo -e "${RD}Source: ${source_dev:-<none>}, Dest: ${dest_dev:-<none>}${CL}"
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
    echo -e "${RD}Error: Data copy failed${CL}"
    log "ERROR copy_data failed"
    rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
    return 1
  fi
  echo -e "${GN}${TAB}✔${CL} ${GN}Data copied${CL}"
  log "STEP3_OK"

  # Step 4: Verify checksum
  echo -e "${BL}[Info]${GN} Step 4/7: Verifying checksum...${CL}"
  log "STEP4_CHECKSUM src=$source_dev dst=$dest_dev"
  if ! verify_checksum "$source_dev" "$dest_dev" "$source_bytes"; then
    echo -e "${RD}Error: Checksum mismatch — data corruption detected${CL}"
    log "ERROR checksum_mismatch"
    rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
    return 1
  fi
  echo -e "${GN}${TAB}✔${CL} ${GN}Checksum verified${CL}"
  log "STEP4_OK"

  # Step 5: Replace volume in config
  echo -e "${BL}[Info]${GN} Step 5/7: Replacing volume in config...${CL}"
  log "STEP5_REPLACE ctid=$ctid disk=$disk_key new=$new_vol size=$target_size"
  save_rollback_metadata "$ctid" "$disk_key" "$old_vol" "$new_vol" "$current_size"
  replace_volume_in_config "$ctid" "$disk_key" "$new_vol" "$target_size"
  echo -e "${GN}${TAB}✔${CL} ${GN}Volume replaced${CL}"
  log "STEP5_OK"

  # Step 6: Start container
  echo -e "${BL}[Info]${GN} Step 6/7: Starting container...${CL}"
  log "STEP6_STARTING ctid=$ctid"
  pct start "$ctid" &
  spinner $! "Starting container"
  sleep 3
  echo -e "${GN}${TAB}✔${CL} ${GN}Container started${CL}"
  log "STEP6_OK"

  # Step 7: Verify health
  echo -e "${BL}[Info]${GN} Step 7/7: Verifying container health...${CL}"
  if [[ "$(pct status "$ctid" 2>/dev/null)" == "status: running" ]]; then
    echo -e "${GN}${TAB}✔${CL} ${GN}Container is running${CL}"
    log "STEP7_OK status=running"
  else
    echo -e "${RD}Warning: Container is not running after start${CL}"
    log "STEP7_WARN status=$(pct status "$ctid" 2>/dev/null)"
  fi

  log "SUCCESS CTID=$ctid DISK_KEY=$disk_key OLD=$current_size NEW=$target_size OLD_VOL=$old_vol NEW_VOL=$new_vol"

  # Post-operation: ask about old volume (or auto-rollback if --rollback was passed)
  if [[ "${AUTO_ROLLBACK:-0}" -eq 1 ]]; then
    echo -e "${BL}[Info]${GN} Auto-rollback requested, reverting to original...${CL}"
    rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
  else
    post_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
  fi

  allow_interrupts
}

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
      echo -e "${BL}[Info]${GN} Deleting old volume...${CL}"
      remove_volume "$old_vol"
      echo -e "${GN}${TAB}✔${CL} ${GN}Old volume deleted${CL}"
      log "POST_DELETE old_vol=$old_vol"
      ;;
    3)
      rollback_operation "$ctid" "$disk_key" "$old_vol" "$new_vol"
      ;;
    *)
      echo -e "${BL}[Info]${GN} Old volume kept${CL}"
      log "POST_KEEP old_vol=$old_vol"
      ;;
  esac
}

# --- CLI ---

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

# --- Entry point ---

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

# Validate CLI inputs
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

# Interactive mode
CTID=$(select_container)
DISK_KEY=$(select_disk "$CTID")
TARGET_SIZE=$(get_target_size "$CTID" "$DISK_KEY")
confirm_operation "$CTID" "$DISK_KEY" "$TARGET_SIZE"
do_resize "$CTID" "$DISK_KEY" "$TARGET_SIZE"

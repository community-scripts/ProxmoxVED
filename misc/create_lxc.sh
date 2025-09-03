#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# Co-Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# This sets verbose mode if the global variable is set to "yes"
if [ "$CREATE_LXC_VERBOSE" == "yes" ]; then set -x; fi

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
  [[ -n "${lockfile:-}" && -e "$lockfile" ]] && rm -f "$lockfile"
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

function exit_script() {
  clear
  printf "\e[?25h"
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  kill 0
  exit 1
}

# Resolve and validate a preselected storage for a given class.
# class: "template" -> requires content=vztmpl
#        "container" -> requires content=rootdir
resolve_storage_preselect() {
  local class="$1"
  local preselect="$2"
  local required_content=""
  case "$class" in
  template) required_content="vztmpl" ;;
  container) required_content="rootdir" ;;
  *) return 1 ;;
  esac

  # No preselect provided
  [ -z "$preselect" ] && return 1

  # Check storage exists and supports required content
  if ! pvesm status -content "$required_content" | awk 'NR>1{print $1}' | grep -qx -- "$preselect"; then
    msg_warn "Preselected storage '${preselect}' does not support content '${required_content}' (or not found)"
    return 1
  fi

  # Build human-readable info string from pvesm status
  # Expected columns: Name Type Status Total Used Free ...
  local line total used free
  line="$(pvesm status | awk -v s="$preselect" 'NR>1 && $1==s {print $0}')"
  if [ -z "$line" ]; then
    STORAGE_INFO="n/a"
  else
    total="$(echo "$line" | awk '{print $4}')"
    used="$(echo "$line" | awk '{print $5}')"
    free="$(echo "$line" | awk '{print $6}')"
    # Format bytes to IEC
    local total_h used_h free_h
    if command -v numfmt >/dev/null 2>&1; then
      total_h="$(numfmt --to=iec --suffix=B --format %.1f "$total" 2>/dev/null || echo "$total")"
      used_h="$(numfmt --to=iec --suffix=B --format %.1f "$used" 2>/dev/null || echo "$used")"
      free_h="$(numfmt --to=iec --suffix=B --format %.1f "$free" 2>/dev/null || echo "$free")"
      STORAGE_INFO="Free: ${free_h}  Used: ${used_h}"
    else
      STORAGE_INFO="Free: ${free}  Used: ${used}"
    fi
  fi

  # Set outputs expected by your callers
  STORAGE_RESULT="$preselect"
  return 0
}

function check_storage_support() {
  local CONTENT="$1"
  local -a VALID_STORAGES=()

  while IFS= read -r line; do
    local STORAGE_NAME
    STORAGE_NAME=$(awk '{print $1}' <<<"$line")
    [[ -z "$STORAGE_NAME" ]] && continue
    VALID_STORAGES+=("$STORAGE_NAME")
  done < <(pvesm status -content "$CONTENT" 2>/dev/null | awk 'NR>1')

  [[ ${#VALID_STORAGES[@]} -gt 0 ]]
}

# This function selects a storage pool for a given content type (e.g., rootdir, vztmpl).
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
    msg_error "Invalid storage class '$CLASS'"
    return 1
    ;;
  esac

  # Check for preset STORAGE variable
  if [ "$CONTENT" = "rootdir" ] && [ -n "${STORAGE:-}" ]; then
    if pvesm status -content "$CONTENT" | awk 'NR>1 {print $1}' | grep -qx "$STORAGE"; then
      STORAGE_RESULT="$STORAGE"
      msg_info "Using preset storage: $STORAGE_RESULT for $CONTENT_LABEL"
      return 0
    else
      msg_error "Preset storage '$STORAGE' is not valid for content type '$CONTENT'."
      return 2
    fi
  fi

  local -A STORAGE_MAP
  local -a MENU
  local COL_WIDTH=0

  while read -r TAG TYPE _ TOTAL USED FREE _; do
    [[ -n "$TAG" && -n "$TYPE" ]] || continue
    local STORAGE_NAME="$TAG"
    local DISPLAY="${STORAGE_NAME} (${TYPE})"
    local USED_FMT=$(numfmt --to=iec --from-unit=K --format %.1f <<<"$USED")
    local FREE_FMT=$(numfmt --to=iec --from-unit=K --format %.1f <<<"$FREE")
    local INFO="Free: ${FREE_FMT}B  Used: ${USED_FMT}B"
    STORAGE_MAP["$DISPLAY"]="$STORAGE_NAME"
    MENU+=("$DISPLAY" "$INFO" "OFF")
    ((${#DISPLAY} > COL_WIDTH)) && COL_WIDTH=${#DISPLAY}
  done < <(pvesm status -content "$CONTENT" | awk 'NR>1')

  if [ ${#MENU[@]} -eq 0 ]; then
    msg_error "No storage found for content type '$CONTENT'."
    return 2
  fi

  if [ $((${#MENU[@]} / 3)) -eq 1 ]; then
    STORAGE_RESULT="${STORAGE_MAP[${MENU[0]}]}"
    STORAGE_INFO="${MENU[1]}"
    return 0
  fi

  local WIDTH=$((COL_WIDTH + 42))
  while true; do
    local DISPLAY_SELECTED
    DISPLAY_SELECTED=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "Storage Pools" \
      --radiolist "Which storage pool for ${CONTENT_LABEL,,}?\n(Spacebar to select)" \
      16 "$WIDTH" 6 "${MENU[@]}" 3>&1 1>&2 2>&3)

    # Cancel or ESC
    [[ $? -ne 0 ]] && exit_script

    # Strip trailing whitespace or newline (important for storages like "storage (dir)")
    DISPLAY_SELECTED=$(sed 's/[[:space:]]*$//' <<<"$DISPLAY_SELECTED")

    if [[ -z "$DISPLAY_SELECTED" || -z "${STORAGE_MAP[$DISPLAY_SELECTED]+_}" ]]; then
      whiptail --msgbox "No valid storage selected. Please try again." 8 58
      continue
    fi

    STORAGE_RESULT="${STORAGE_MAP[$DISPLAY_SELECTED]}"
    for ((i = 0; i < ${#MENU[@]}; i += 3)); do
      if [[ "${MENU[$i]}" == "$DISPLAY_SELECTED" ]]; then
        STORAGE_INFO="${MENU[$i + 1]}"
        break
      fi
    done
    return 0
  done
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

msg_debug "CTID=$CTID"
msg_debug "PCT_OSTYPE=$PCT_OSTYPE"
msg_debug "PCT_OSVERSION=${PCT_OSVERSION:-default}"

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

# This checks for the presence of valid Container Storage and Template Storage locations
if ! check_storage_support "rootdir"; then
  msg_error "No valid storage found for 'rootdir' [Container]"
  exit 1
fi
if ! check_storage_support "vztmpl"; then
  msg_error "No valid storage found for 'vztmpl' [Template]"
  exit 1
fi

# Template storage selection
if resolve_storage_preselect template "${TEMPLATE_STORAGE}"; then
  TEMPLATE_STORAGE="$STORAGE_RESULT"
  TEMPLATE_STORAGE_INFO="$STORAGE_INFO"
  msg_ok "Storage ${BL}${TEMPLATE_STORAGE}${CL} (${TEMPLATE_STORAGE_INFO}) [Template]"
else
  while true; do
    if select_storage template; then
      TEMPLATE_STORAGE="$STORAGE_RESULT"
      TEMPLATE_STORAGE_INFO="$STORAGE_INFO"
      msg_ok "Storage ${BL}${TEMPLATE_STORAGE}${CL} (${TEMPLATE_STORAGE_INFO}) [Template]"
      break
    fi
  done
fi

# Container storage selection
if resolve_storage_preselect container "${CONTAINER_STORAGE}"; then
  CONTAINER_STORAGE="$STORAGE_RESULT"
  CONTAINER_STORAGE_INFO="$STORAGE_INFO"
  msg_ok "Storage ${BL}${CONTAINER_STORAGE}${CL} (${CONTAINER_STORAGE_INFO}) [Container]"
else
  while true; do
    if select_storage container; then
      CONTAINER_STORAGE="$STORAGE_RESULT"
      CONTAINER_STORAGE_INFO="$STORAGE_INFO"
      msg_ok "Storage ${BL}${CONTAINER_STORAGE}${CL} (${CONTAINER_STORAGE_INFO}) [Container]"
      break
    fi
  done
fi

# Storage Content Validation
msg_info "Validating content types of storage '$CONTAINER_STORAGE'"
STORAGE_CONTENT=$(grep -A4 -E "^(zfspool|dir|lvmthin|lvm): $CONTAINER_STORAGE" /etc/pve/storage.cfg | grep content | awk '{$1=""; print $0}' | xargs)

msg_debug "Storage '$CONTAINER_STORAGE' has content types: $STORAGE_CONTENT"

# check if rootdir supported
if ! grep -qw "rootdir" <<<"$STORAGE_CONTENT"; then
  msg_error "Storage '$CONTAINER_STORAGE' does not support 'rootdir'. Cannot create LXC."
  exit 217
fi
msg_ok "Storage '$CONTAINER_STORAGE' supports 'rootdir'"

# check if template storage is compatible
msg_info "Validating content types of template storage '$TEMPLATE_STORAGE'"
TEMPLATE_CONTENT=$(grep -A4 -E "^[^:]+: $TEMPLATE_STORAGE" /etc/pve/storage.cfg | grep content | awk '{$1=""; print $0}' | xargs)

msg_debug "Template storage '$TEMPLATE_STORAGE' has content types: $TEMPLATE_CONTENT"

if ! grep -qw "vztmpl" <<<"$TEMPLATE_CONTENT"; then
  msg_warn "Template storage '$TEMPLATE_STORAGE' does not declare 'vztmpl'. This may cause pct create to fail."
else
  msg_ok "Template storage '$TEMPLATE_STORAGE' supports 'vztmpl'"
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
  msg_info "Checking cluster quorum"
  if ! pvecm status | awk -F':' '/^Quorate/ { exit ($2 ~ /Yes/) ? 0 : 1 }'; then
    msg_error "Cluster is not quorate. Start all nodes or configure quorum device (QDevice)."
    exit 210
  fi
  msg_ok "Cluster is quorate"
fi

# Update LXC template list
TEMPLATE_SEARCH="${PCT_OSTYPE}-${PCT_OSVERSION:-}"
case "$PCT_OSTYPE" in
debian | ubuntu) TEMPLATE_PATTERN="-standard_" ;;
alpine | fedora | rocky | centos) TEMPLATE_PATTERN="-default_" ;;
*) TEMPLATE_PATTERN="" ;;
esac

msg_info "Searching for template '$TEMPLATE_SEARCH'"

# 1. get / check local templates
mapfile -t LOCAL_TEMPLATES < <(
  pveam list "$TEMPLATE_STORAGE" 2>/dev/null |
    awk -v s="$TEMPLATE_SEARCH" -v p="$TEMPLATE_PATTERN" '$1 ~ s && $1 ~ p {print $1}' |
    sed 's/.*\///' | sort -t - -k 2 -V
)

# 2. get online templates
pveam update >/dev/null 2>&1 || msg_warn "Could not update template catalog (pveam update failed)."
mapfile -t ONLINE_TEMPLATES < <(
  pveam available -section system 2>/dev/null |
    sed -n "s/.*\($TEMPLATE_SEARCH.*$TEMPLATE_PATTERN.*\)/\1/p" |
    sort -t - -k 2 -V
)
if [ ${#ONLINE_TEMPLATES[@]} -gt 0 ]; then
  ONLINE_TEMPLATE="${ONLINE_TEMPLATES[-1]}"
else
  ONLINE_TEMPLATE=""
fi

# 3. Local vs Online
if [ ${#LOCAL_TEMPLATES[@]} -gt 0 ]; then
  TEMPLATE="${LOCAL_TEMPLATES[-1]}"
  TEMPLATE_SOURCE="local"
else
  TEMPLATE="$ONLINE_TEMPLATE"
  TEMPLATE_SOURCE="online"
fi

# 4. Getting Path (universal, also for nfs/cifs)
TEMPLATE_PATH="$(pvesm path $TEMPLATE_STORAGE:vztmpl/$TEMPLATE 2>/dev/null || true)"
if [[ -z "$TEMPLATE_PATH" ]]; then
  TEMPLATE_BASE=$(awk -v s="$TEMPLATE_STORAGE" '$1==s {f=1} f && /path/ {print $2; exit}' /etc/pve/storage.cfg)
  if [[ -n "$TEMPLATE_BASE" ]]; then
    TEMPLATE_PATH="$TEMPLATE_BASE/template/cache/$TEMPLATE"
  fi
fi

if [[ -z "$TEMPLATE_PATH" ]]; then
  msg_error "Unable to resolve template path for $TEMPLATE_STORAGE. Check storage type and permissions."
  exit 220
fi

msg_ok "Template ${BL}$TEMPLATE${CL} [$TEMPLATE_SOURCE]"
msg_debug "Resolved TEMPLATE_PATH=$TEMPLATE_PATH"

# 5. Validation
NEED_DOWNLOAD=0
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  msg_info "Template not present locally – will download."
  NEED_DOWNLOAD=1
elif [[ ! -r "$TEMPLATE_PATH" ]]; then
  msg_error "Template file exists but is not readable – check permissions."
  exit 221
elif [[ "$(stat -c%s "$TEMPLATE_PATH")" -lt 1000000 ]]; then
  if [[ -n "$ONLINE_TEMPLATE" ]]; then
    msg_warn "Template file too small (<1MB) – re-downloading."
    NEED_DOWNLOAD=1
  else
    msg_warn "Template looks too small, but no online version exists. Keeping local file."
  fi
elif ! tar -tf "$TEMPLATE_PATH" &>/dev/null; then
  if [[ -n "$ONLINE_TEMPLATE" ]]; then
    msg_warn "Template appears corrupted – re-downloading."
    NEED_DOWNLOAD=1
  else
    msg_warn "Template appears corrupted, but no online version exists. Keeping local file."
  fi
else
  msg_ok "Template $TEMPLATE is present and valid."
fi

# 6. Update-Check (if local exist)
if [[ "$TEMPLATE_SOURCE" == "local" && -n "$ONLINE_TEMPLATE" && "$TEMPLATE" != "$ONLINE_TEMPLATE" ]]; then
  msg_warn "Local template is outdated: $TEMPLATE (latest available: $ONLINE_TEMPLATE)"
  if whiptail --yesno "A newer template is available:\n$ONLINE_TEMPLATE\n\nDo you want to download and use it instead?" 12 70; then
    TEMPLATE="$ONLINE_TEMPLATE"
    NEED_DOWNLOAD=1
  else
    msg_info "Continuing with local template $TEMPLATE"
  fi
fi

# 7. Download if needed
if [[ "$NEED_DOWNLOAD" -eq 1 ]]; then
  [[ -f "$TEMPLATE_PATH" ]] && rm -f "$TEMPLATE_PATH"
  for attempt in {1..3}; do
    msg_info "Attempt $attempt: Downloading template $TEMPLATE to $TEMPLATE_STORAGE"
    if pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null 2>&1; then
      msg_ok "Template download successful."
      break
    fi
    if [ $attempt -eq 3 ]; then
      msg_error "Failed after 3 attempts. Please check network access, permissions, or manually run:\n  pveam download $TEMPLATE_STORAGE $TEMPLATE"
      exit 222
    fi
    sleep $((attempt * 5))
  done
fi

# 8. Final Check – Template usability
if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q "$TEMPLATE"; then
  msg_error "Template $TEMPLATE not available in storage $TEMPLATE_STORAGE after download."
  exit 223
fi
msg_ok "Template $TEMPLATE is ready for container creation."

# ------------------------------------------------------------------------------
# Create LXC Container with validation, recovery and debug option
# ------------------------------------------------------------------------------

msg_info "Creating LXC container"

# Ensure subuid/subgid entries exist
grep -q "root:100000:65536" /etc/subuid || echo "root:100000:65536" >>/etc/subuid
grep -q "root:100000:65536" /etc/subgid || echo "root:100000:65536" >>/etc/subgid

# Assemble pct options
PCT_OPTIONS=(${PCT_OPTIONS[@]:-${DEFAULT_PCT_OPTIONS[@]}})
[[ " ${PCT_OPTIONS[*]} " =~ " -rootfs " ]] || PCT_OPTIONS+=(-rootfs "$CONTAINER_STORAGE:${PCT_DISK_SIZE:-8}")

# Secure with lockfile
lockfile="/tmp/template.${TEMPLATE}.lock"
exec 9>"$lockfile" || {
  msg_error "Failed to create lock file '$lockfile'."
  exit 200
}
flock -w 60 9 || {
  msg_error "Timeout while waiting for template lock."
  exit 211
}

LOGFILE="/tmp/pct_create_${CTID}.log"
msg_debug "pct create command: pct create $CTID ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE} ${PCT_OPTIONS[*]}"
msg_debug "Logfile: $LOGFILE"

# First attempt
if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" >"$LOGFILE" 2>&1; then
  msg_error "Container creation failed on ${TEMPLATE_STORAGE}. Checking template..."

  # Validate template file
  if [[ ! -s "$TEMPLATE_PATH" || "$(stat -c%s "$TEMPLATE_PATH")" -lt 1000000 ]]; then
    msg_warn "Template file too small or missing – re-downloading."
    rm -f "$TEMPLATE_PATH"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
  elif ! tar -tf "$TEMPLATE_PATH" &>/dev/null; then
    if [[ -n "$ONLINE_TEMPLATE" ]]; then
      msg_warn "Template appears corrupted – re-downloading."
      rm -f "$TEMPLATE_PATH"
      pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
    else
      msg_warn "Template appears corrupted, but no online version exists. Skipping re-download."
    fi
  fi

  # Retry after repair
  if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" >>"$LOGFILE" 2>&1; then
    # Fallback to local storage
    if [[ "$TEMPLATE_STORAGE" != "local" ]]; then
      msg_warn "Retrying container creation with fallback to local storage..."
      LOCAL_TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"
      if [ ! -f "$LOCAL_TEMPLATE_PATH" ]; then
        msg_info "Downloading template to local..."
        pveam download local "$TEMPLATE" >/dev/null 2>&1
      fi
      if pct create "$CTID" "local:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" >>"$LOGFILE" 2>&1; then
        msg_ok "Container successfully created using local fallback."
      else
        msg_error "Container creation failed even with local fallback. See $LOGFILE"
        # Ask user if they want debug output
        if whiptail --yesno "pct create failed.\nDo you want to enable verbose debug mode and view detailed logs?" 12 70; then
          set -x
          bash -x -c "pct create $CTID local:vztmpl/${TEMPLATE} ${PCT_OPTIONS[*]}" 2>&1 | tee -a "$LOGFILE"
          set +x
        fi
        exit 209
      fi
    else
      msg_error "Container creation failed on local storage. See $LOGFILE"
      if whiptail --yesno "pct create failed.\nDo you want to enable verbose debug mode and view detailed logs?" 12 70; then
        set -x
        bash -x -c "pct create $CTID local:vztmpl/${TEMPLATE} ${PCT_OPTIONS[*]}" 2>&1 | tee -a "$LOGFILE"
        set +x
      fi
      exit 209
    fi
  fi
fi

# Verify container exists
if ! pct list | awk '{print $1}' | grep -qx "$CTID"; then
  msg_error "Container ID $CTID not listed in 'pct list'. See $LOGFILE"
  exit 215
fi

# Verify config rootfs
if ! grep -q '^rootfs:' "/etc/pve/lxc/$CTID.conf"; then
  msg_error "RootFS entry missing in container config. See $LOGFILE"
  exit 216
fi

msg_ok "LXC Container ${BL}$CTID${CL} ${GN}was successfully created."

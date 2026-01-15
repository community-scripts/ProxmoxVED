#!/usr/bin/env bash
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# Co-Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# ------------------------------------------------------------------------------
# Optional verbose mode (debug tracing)
# ------------------------------------------------------------------------------
if [[ "${CREATE_LXC_VERBOSE:-no}" == "yes" ]]; then set -x; fi

# ------------------------------------------------------------------------------
# Load core functions (msg_info/msg_ok/msg_error/…)
# ------------------------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  # Achtung: bewusst exakt diese URL-Struktur
  source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
  load_functions
elif command -v wget >/dev/null 2>&1; then
  source <(wget -qO- https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
  load_functions
fi

# ------------------------------------------------------------------------------
# Strict error handling
# ------------------------------------------------------------------------------
# set -Eeuo pipefail
# trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR
# trap on_exit EXIT
# trap on_interrupt INT
# trap on_terminate TERM

# error_handler() {
#   local exit_code="$1"
#   local line_number="$2"
#   local command="${3:-}"

#   if [[ "$exit_code" -eq 0 ]]; then
#     return 0
#   fi

#   printf "\e[?25h"
#   echo -e "\n${RD}[ERROR]${CL} in line ${RD}${line_number}${CL}: exit code ${RD}${exit_code}${CL}: while executing command ${YW}${command}${CL}\n"
#   exit "$exit_code"
# }

# on_exit() {
#   local exit_code="$?"
#   [[ -n "${lockfile:-}" && -e "$lockfile" ]] && rm -f "$lockfile"
#   exit "$exit_code"
# }

# on_interrupt() {
#   echo -e "\n${RD}Interrupted by user (SIGINT)${CL}"
#   exit 130
# }

# on_terminate() {
#   echo -e "\n${RD}Terminated by signal (SIGTERM)${CL}"
#   exit 143
# }

exit_script() {
  clear
  printf "\e[?25h"
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  kill 0
  exit 1
}

# ------------------------------------------------------------------------------
# Helpers (dynamic versioning / template parsing)
# ------------------------------------------------------------------------------
pkg_ver() { dpkg-query -W -f='${Version}\n' "$1" 2>/dev/null || echo ""; }
pkg_cand() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}'; }

ver_ge() { dpkg --compare-versions "$1" ge "$2"; }
ver_gt() { dpkg --compare-versions "$1" gt "$2"; }
ver_lt() { dpkg --compare-versions "$1" lt "$2"; }

# Extract Debian OS minor from template name: debian-13-standard_13.1-1_amd64.tar.zst => "13.1"
parse_template_osver() { sed -n 's/.*_\([0-9][0-9]*\(\.[0-9]\+\)\?\)-.*/\1/p' <<<"$1"; }

# Offer upgrade for pve-container/lxc-pve if candidate > installed; optional auto-retry pct create
# Returns:
#   0 = no upgrade needed
#   1 = upgraded (and if do_retry=yes and retry succeeded, creation done)
#   2 = user declined
#   3 = upgrade attempted but failed OR retry failed
offer_lxc_stack_upgrade_and_maybe_retry() {
  local do_retry="${1:-no}" # yes|no
  local _pvec_i _pvec_c _lxcp_i _lxcp_c need=0

  _pvec_i="$(pkg_ver pve-container)"
  _lxcp_i="$(pkg_ver lxc-pve)"
  _pvec_c="$(pkg_cand pve-container)"
  _lxcp_c="$(pkg_cand lxc-pve)"

  if [[ -n "$_pvec_c" && "$_pvec_c" != "none" ]]; then
    ver_gt "$_pvec_c" "${_pvec_i:-0}" && need=1
  fi
  if [[ -n "$_lxcp_c" && "$_lxcp_c" != "none" ]]; then
    ver_gt "$_lxcp_c" "${_lxcp_i:-0}" && need=1
  fi
  if [[ $need -eq 0 ]]; then
    msg_debug "No newer candidate for pve-container/lxc-pve (installed=$_pvec_i/$_lxcp_i, cand=$_pvec_c/$_lxcp_c)"
    return 0
  fi

  echo
  echo "An update for the Proxmox LXC stack is available:"
  echo "  pve-container: installed=${_pvec_i:-n/a}  candidate=${_pvec_c:-n/a}"
  echo "  lxc-pve     : installed=${_lxcp_i:-n/a}  candidate=${_lxcp_c:-n/a}"
  echo
  read -rp "Do you want to upgrade now? [y/N] " _ans
  case "${_ans,,}" in
  y | yes)
    msg_info "Upgrading Proxmox LXC stack (pve-container, lxc-pve)"
    if apt-get update -qq >/dev/null && apt-get install -y --only-upgrade pve-container lxc-pve >/dev/null; then
      msg_ok "LXC stack upgraded."
      if [[ "$do_retry" == "yes" ]]; then
        msg_info "Retrying container creation after upgrade"
        if pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" >>"$LOGFILE" 2>&1; then
          msg_ok "Container created successfully after upgrade."
          return 1
        else
          msg_error "pct create still failed after upgrade. See $LOGFILE"
          return 3
        fi
      fi
      return 1
    else
      msg_error "Upgrade failed. Please check APT output."
      return 3
    fi
    ;;
  *) return 2 ;;
  esac
}

# ------------------------------------------------------------------------------
# Storage discovery / selection helpers
# ------------------------------------------------------------------------------
resolve_storage_preselect() {
  local class="$1" preselect="$2" required_content=""
  case "$class" in
  template) required_content="vztmpl" ;;
  container) required_content="rootdir" ;;
  *) return 1 ;;
  esac
  [[ -z "$preselect" ]] && return 1
  if ! pvesm status -content "$required_content" | awk 'NR>1{print $1}' | grep -qx -- "$preselect"; then
    msg_warn "Preselected storage '${preselect}' does not support content '${required_content}' (or not found)"
    return 1
  fi

  local line total used free
  line="$(pvesm status | awk -v s="$preselect" 'NR>1 && $1==s {print $0}')"
  if [[ -z "$line" ]]; then
    STORAGE_INFO="n/a"
  else
    total="$(awk '{print $4}' <<<"$line")"
    used="$(awk '{print $5}' <<<"$line")"
    free="$(awk '{print $6}' <<<"$line")"
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
  STORAGE_RESULT="$preselect"
  return 0
}

check_storage_support() {
  local CONTENT="$1" VALID=0
  while IFS= read -r line; do
    local STORAGE_NAME
    STORAGE_NAME=$(awk '{print $1}' <<<"$line")
    [[ -n "$STORAGE_NAME" ]] && VALID=1
  done < <(pvesm status -content "$CONTENT" 2>/dev/null | awk 'NR>1')
  [[ $VALID -eq 1 ]]
}

select_storage() {
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

  if [[ "$CONTENT" == "rootdir" && -n "${STORAGE:-}" ]]; then
    if pvesm status -content "$CONTENT" | awk 'NR>1 {print $1}' | grep -qx "$STORAGE"; then
      STORAGE_RESULT="$STORAGE"
      msg_info "Using preset storage: $STORAGE_RESULT for $CONTENT_LABEL"
      return 0
    else
      msg_error "Preset storage '$STORAGE' is not valid for content type '$CONTENT'."
      return 2
    fi
  fi

  declare -A STORAGE_MAP
  local -a MENU=()
  local COL_WIDTH=0

  while read -r TAG TYPE _ TOTAL USED FREE _; do
    [[ -n "$TAG" && -n "$TYPE" ]] || continue
    local DISPLAY="${TAG} (${TYPE})"
    local USED_FMT=$(numfmt --to=iec --from-unit=K --format %.1f <<<"$USED")
    local FREE_FMT=$(numfmt --to=iec --from-unit=K --format %.1f <<<"$FREE")
    local INFO="Free: ${FREE_FMT}B  Used: ${USED_FMT}B"
    STORAGE_MAP["$DISPLAY"]="$TAG"
    MENU+=("$DISPLAY" "$INFO" "OFF")
    ((${#DISPLAY} > COL_WIDTH)) && COL_WIDTH=${#DISPLAY}
  done < <(pvesm status -content "$CONTENT" | awk 'NR>1')

  if [[ ${#MENU[@]} -eq 0 ]]; then
    msg_error "No storage found for content type '$CONTENT'."
    return 2
  fi

  if [[ $((${#MENU[@]} / 3)) -eq 1 ]]; then
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
      16 "$WIDTH" 6 "${MENU[@]}" 3>&1 1>&2 2>&3) || exit_script

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

# ------------------------------------------------------------------------------
# Required input variables
# ------------------------------------------------------------------------------
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

# ID checks
[[ "$CTID" -ge 100 ]] || {
  msg_error "ID cannot be less than 100."
  exit 205
}
if qm status "$CTID" &>/dev/null || pct status "$CTID" &>/dev/null; then
  echo -e "ID '$CTID' is already in use."
  unset CTID
  msg_error "Cannot use ID that is already in use."
  exit 206
fi

# Storage capability check
check_storage_support "rootdir" || {
  msg_error "No valid storage found for 'rootdir' [Container]"
  exit 1
}
check_storage_support "vztmpl" || {
  msg_error "No valid storage found for 'vztmpl' [Template]"
  exit 1
}

# Template storage selection
if resolve_storage_preselect template "${TEMPLATE_STORAGE:-}"; then
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
if resolve_storage_preselect container "${CONTAINER_STORAGE:-}"; then
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

# Validate content types
msg_info "Validating content types of storage '$CONTAINER_STORAGE'"
STORAGE_CONTENT=$(grep -A4 -E "^(zfspool|dir|lvmthin|lvm): $CONTAINER_STORAGE" /etc/pve/storage.cfg | grep content | awk '{$1=""; print $0}' | xargs)
msg_debug "Storage '$CONTAINER_STORAGE' has content types: $STORAGE_CONTENT"
grep -qw "rootdir" <<<"$STORAGE_CONTENT" || {
  msg_error "Storage '$CONTAINER_STORAGE' does not support 'rootdir'. Cannot create LXC."
  exit 217
}
$STD msg_ok "Storage '$CONTAINER_STORAGE' supports 'rootdir'"

msg_info "Validating content types of template storage '$TEMPLATE_STORAGE'"
TEMPLATE_CONTENT=$(grep -A4 -E "^[^:]+: $TEMPLATE_STORAGE" /etc/pve/storage.cfg | grep content | awk '{$1=""; print $0}' | xargs)
msg_debug "Template storage '$TEMPLATE_STORAGE' has content types: $TEMPLATE_CONTENT"
if ! grep -qw "vztmpl" <<<"$TEMPLATE_CONTENT"; then
  msg_warn "Template storage '$TEMPLATE_STORAGE' does not declare 'vztmpl'. This may cause pct create to fail."
else
  $STD msg_ok "Template storage '$TEMPLATE_STORAGE' supports 'vztmpl'"
fi

# Free space check
STORAGE_FREE=$(pvesm status | awk -v s="$CONTAINER_STORAGE" '$1 == s { print $6 }')
REQUIRED_KB=$((${PCT_DISK_SIZE:-8} * 1024 * 1024))
[[ "$STORAGE_FREE" -ge "$REQUIRED_KB" ]] || {
  msg_error "Not enough space on '$CONTAINER_STORAGE'. Needed: ${PCT_DISK_SIZE:-8}G."
  exit 214
}

# Cluster quorum (if cluster)
if [[ -f /etc/pve/corosync.conf ]]; then
  msg_info "Checking cluster quorum"
  if ! pvecm status | awk -F':' '/^Quorate/ { exit ($2 ~ /Yes/) ? 0 : 1 }'; then
    msg_error "Cluster is not quorate. Start all nodes or configure quorum device (QDevice)."
    exit 210
  fi
  msg_ok "Cluster is quorate"
fi

# ------------------------------------------------------------------------------
# Template discovery & validation
# ------------------------------------------------------------------------------
TEMPLATE_SEARCH="${PCT_OSTYPE}-${PCT_OSVERSION:-}"
case "$PCT_OSTYPE" in
debian | ubuntu) TEMPLATE_PATTERN="-standard_" ;;
alpine | fedora | rocky | centos) TEMPLATE_PATTERN="-default_" ;;
*) TEMPLATE_PATTERN="" ;;
esac

msg_info "Searching for template '$TEMPLATE_SEARCH'"

mapfile -t LOCAL_TEMPLATES < <(
  pveam list "$TEMPLATE_STORAGE" 2>/dev/null |
    awk -v s="$TEMPLATE_SEARCH" -v p="$TEMPLATE_PATTERN" '$1 ~ s && $1 ~ p {print $1}' |
    sed 's|.*/||' | sort -t - -k 2 -V
)

pveam update >/dev/null 2>&1 || msg_warn "Could not update template catalog (pveam update failed)."
mapfile -t ONLINE_TEMPLATES < <(
  pveam available -section system 2>/dev/null |
    sed -n "s/.*\($TEMPLATE_SEARCH.*$TEMPLATE_PATTERN.*\)/\1/p" |
    sort -t - -k 2 -V
)
ONLINE_TEMPLATE=""
[[ ${#ONLINE_TEMPLATES[@]} -gt 0 ]] && ONLINE_TEMPLATE="${ONLINE_TEMPLATES[-1]}"

if [[ ${#LOCAL_TEMPLATES[@]} -gt 0 ]]; then
  TEMPLATE="${LOCAL_TEMPLATES[-1]}"
  TEMPLATE_SOURCE="local"
else
  TEMPLATE="$ONLINE_TEMPLATE"
  TEMPLATE_SOURCE="online"
fi

TEMPLATE_PATH="$(pvesm path $TEMPLATE_STORAGE:vztmpl/$TEMPLATE 2>/dev/null || true)"
if [[ -z "$TEMPLATE_PATH" ]]; then
  TEMPLATE_BASE=$(awk -v s="$TEMPLATE_STORAGE" '$1==s {f=1} f && /path/ {print $2; exit}' /etc/pve/storage.cfg)
  [[ -n "$TEMPLATE_BASE" ]] && TEMPLATE_PATH="$TEMPLATE_BASE/template/cache/$TEMPLATE"
fi
[[ -n "$TEMPLATE_PATH" ]] || {
  msg_error "Unable to resolve template path for $TEMPLATE_STORAGE. Check storage type and permissions."
  exit 220
}

msg_ok "Template ${BL}$TEMPLATE${CL} [$TEMPLATE_SOURCE]"
msg_debug "Resolved TEMPLATE_PATH=$TEMPLATE_PATH"

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
  $STD msg_ok "Template $TEMPLATE is present and valid."
fi

if [[ "$TEMPLATE_SOURCE" == "local" && -n "$ONLINE_TEMPLATE" && "$TEMPLATE" != "$ONLINE_TEMPLATE" ]]; then
  msg_warn "Local template is outdated: $TEMPLATE (latest available: $ONLINE_TEMPLATE)"
  if whiptail --yesno "A newer template is available:\n$ONLINE_TEMPLATE\n\nDo you want to download and use it instead?" 12 70; then
    TEMPLATE="$ONLINE_TEMPLATE"
    NEED_DOWNLOAD=1
  else
    msg_info "Continuing with local template $TEMPLATE"
  fi
fi

if [[ "$NEED_DOWNLOAD" -eq 1 ]]; then
  [[ -f "$TEMPLATE_PATH" ]] && rm -f "$TEMPLATE_PATH"
  for attempt in {1..3}; do
    msg_info "Attempt $attempt: Downloading template $TEMPLATE to $TEMPLATE_STORAGE"
    if pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null 2>&1; then
      msg_ok "Template download successful."
      break
    fi
    if [[ $attempt -eq 3 ]]; then
      msg_error "Failed after 3 attempts. Please check network access, permissions, or manually run:\n  pveam download $TEMPLATE_STORAGE $TEMPLATE"
      exit 222
    fi
    sleep $((attempt * 5))
  done
fi

if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q "$TEMPLATE"; then
  msg_error "Template $TEMPLATE not available in storage $TEMPLATE_STORAGE after download."
  exit 223
fi

# ------------------------------------------------------------------------------
# Dynamic preflight for Debian 13.x: offer upgrade if available (no hard mins)
# ------------------------------------------------------------------------------
if [[ "$PCT_OSTYPE" == "debian" ]]; then
  OSVER="$(parse_template_osver "$TEMPLATE")"
  if [[ -n "$OSVER" ]]; then
    # Proactive, aber ohne Abbruch – nur Angebot
    offer_lxc_stack_upgrade_and_maybe_retry "no" || true
  fi
fi

# ------------------------------------------------------------------------------
# Create LXC Container
# ------------------------------------------------------------------------------
msg_info "Creating LXC container"

# Ensure subuid/subgid entries exist
grep -q "root:100000:65536" /etc/subuid || echo "root:100000:65536" >>/etc/subuid
grep -q "root:100000:65536" /etc/subgid || echo "root:100000:65536" >>/etc/subgid

# Assemble pct options
PCT_OPTIONS=(${PCT_OPTIONS[@]:-${DEFAULT_PCT_OPTIONS[@]}})
[[ " ${PCT_OPTIONS[*]} " =~ " -rootfs " ]] || PCT_OPTIONS+=(-rootfs "$CONTAINER_STORAGE:${PCT_DISK_SIZE:-8}")

# Lock by template file (avoid concurrent downloads/creates)
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
      if [[ ! -f "$LOCAL_TEMPLATE_PATH" ]]; then
        msg_info "Downloading template to local..."
        pveam download local "$TEMPLATE" >/dev/null 2>&1
      fi
      if pct create "$CTID" "local:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" >>"$LOGFILE" 2>&1; then
        msg_ok "Container successfully created using local fallback."
      else
        # --- Dynamic stack upgrade + auto-retry on the well-known error pattern ---
        if grep -qiE 'unsupported .* version' "$LOGFILE"; then
          echo
          echo "pct reported 'unsupported ... version' – your LXC stack might be too old for this template."
          echo "We can try to upgrade 'pve-container' and 'lxc-pve' now and retry automatically."
          if offer_lxc_stack_upgrade_and_maybe_retry "yes"; then
            : # success after retry
          else
            rc=$?
            case $rc in
            2) echo "Upgrade was declined. Please update and re-run:
  apt update && apt install --only-upgrade pve-container lxc-pve" ;;
            3) echo "Upgrade and/or retry failed. Please inspect: $LOGFILE" ;;
            esac
            exit 231
          fi
        else
          msg_error "Container creation failed even with local fallback. See $LOGFILE"
          if whiptail --yesno "pct create failed.\nDo you want to enable verbose debug mode and view detailed logs?" 12 70; then
            set -x
            bash -x -c "pct create $CTID local:vztmpl/${TEMPLATE} ${PCT_OPTIONS[*]}" 2>&1 | tee -a "$LOGFILE"
            set +x
          fi
          exit 209
        fi
      fi
    else
      msg_error "Container creation failed on local storage. See $LOGFILE"
      # --- Dynamic stack upgrade + auto-retry on the well-known error pattern ---
      if grep -qiE 'unsupported .* version' "$LOGFILE"; then
        echo
        echo "pct reported 'unsupported ... version' – your LXC stack might be too old for this template."
        echo "We can try to upgrade 'pve-container' and 'lxc-pve' now and retry automatically."
        if offer_lxc_stack_upgrade_and_maybe_retry "yes"; then
          : # success after retry
        else
          rc=$?
          case $rc in
          2) echo "Upgrade was declined. Please update and re-run:
  apt update && apt install --only-upgrade pve-container lxc-pve" ;;
          3) echo "Upgrade and/or retry failed. Please inspect: $LOGFILE" ;;
          esac
          exit 231
        fi
      else
        if whiptail --yesno "pct create failed.\nDo you want to enable verbose debug mode and view detailed logs?" 12 70; then
          set -x
          bash -x -c "pct create $CTID local:vztmpl/${TEMPLATE} ${PCT_OPTIONS[*]}" 2>&1 | tee -a "$LOGFILE"
          set +x
        fi
        exit 209
      fi
    fi
  fi
fi

# Verify container exists
pct list | awk '{print $1}' | grep -qx "$CTID" || {
  msg_error "Container ID $CTID not listed in 'pct list'. See $LOGFILE"
  exit 215
}

# Verify config rootfs
grep -q '^rootfs:' "/etc/pve/lxc/$CTID.conf" || {
  msg_error "RootFS entry missing in container config. See $LOGFILE"
  exit 216
}

msg_ok "LXC Container ${BL}$CTID${CL} ${GN}was successfully created."

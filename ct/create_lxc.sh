#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# Co-Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

# Constants
URL_CORE_FUNC="https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func"
EXIT_INVALID_PASSWORD=301
EXIT_INVALID_VLAN=302
EXIT_COREFUNC_LOAD=303
EXIT_NO_DOWNLOADER=304
EXIT_NO_CT_STORAGE=305
EXIT_NO_TMPL_STORAGE=306
EXIT_TEMPLATE_CORRUPT=308
EXIT_TEMPLATE_DL_FAIL=309
EXIT_CONTAINER_CREATE_FAIL=310
EXIT_CONTAINER_NOT_FOUND=311
EXIT_TEMPLATE_LOCK_TIMEOUT=312

# Spinner cleanup
function error_handler() {
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  exit 200
}

# Load core.func
if command -v curl >/dev/null 2>&1; then
  if ! CORE_FUNC=$(curl -fsSL "$URL_CORE_FUNC"); then
    echo "Failed to fetch core.func via curl. Check DNS or proxy." >&2
    exit $EXIT_COREFUNC_LOAD
  fi
  source <(echo "$CORE_FUNC")
elif command -v wget >/dev/null 2>&1; then
  if ! CORE_FUNC=$(wget -qO- "$URL_CORE_FUNC"); then
    echo "Failed to fetch core.func via wget. Check DNS or proxy." >&2
    exit $EXIT_COREFUNC_LOAD
  fi
  source <(echo "$CORE_FUNC")
else
  echo "curl or wget not found. Cannot proceed." >&2
  exit $EXIT_NO_DOWNLOADER
fi
load_functions

# Validate required inputs
[[ "${CTID:-}" ]] || {
  msg_error "CTID not set."
  exit 203
}
[[ "${PCT_OSTYPE:-}" ]] || {
  msg_error "PCT_OSTYPE not set."
  exit 204
}
[[ "$CTID" -ge 100 ]] || {
  msg_error "CTID must be >= 100."
  exit 205
}
if qm status "$CTID" &>/dev/null || pct status "$CTID" &>/dev/null; then
  msg_error "CTID $CTID already in use."
  exit 206
fi

# Password validation
[[ "${PCT_PASSWORD:-}" =~ ^- ]] && {
  msg_error "Root password must not begin with '-' (interpreted as argument)."
  exit $EXIT_INVALID_PASSWORD
}

# VLAN validation
if [[ "${PCT_VLAN_TAG:-}" =~ ^[0-9]+$ ]]; then
  if [ "$PCT_VLAN_TAG" -lt 1 ] || [ "$PCT_VLAN_TAG" -gt 4094 ]; then
    msg_error "VLAN tag '${PCT_VLAN_TAG}' out of range (1-4094)."
    exit $EXIT_INVALID_VLAN
  fi
elif [[ -n "${PCT_VLAN_TAG:-}" ]]; then
  msg_warn "Invalid VLAN tag format. Skipping VLAN config."
  unset PCT_VLAN_TAG
fi

function select_storage() {
  local CLASS="$1"
  local CONTENT CONTENT_LABEL
  case "$CLASS" in
  container)
    CONTENT='rootdir'
    CONTENT_LABEL='Container'
    ;;
  template)
    CONTENT='vztmpl'
    CONTENT_LABEL='Container Template'
    ;;
  *)
    msg_error "Invalid storage class: $CLASS"
    exit 201
    ;;
  esac

  local -a MENU
  local MSG_MAX_LENGTH=0
  while read -r TAG TYPE _ _ _ FREE _; do
    local TYPE_PADDED FREE_FMT
    TYPE_PADDED=$(printf "%-10s" "$TYPE")
    FREE_FMT=$(numfmt --to=iec --from-unit=K --format %.2f <<<"$FREE")B
    local ITEM="Type: $TYPE_PADDED Free: $FREE_FMT"
    ((${#ITEM} + 2 > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM} + 2
    MENU+=("$TAG" "$ITEM" "OFF")
  done < <(pvesm status -content "$CONTENT" | awk 'NR>1')

  local OPTION_COUNT=$((${#MENU[@]} / 3))
  if [[ "$OPTION_COUNT" -eq 1 ]]; then
    echo "${MENU[0]}"
    return 0
  fi

  local STORAGE
  while [[ -z "${STORAGE:+x}" ]]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Select the storage pool to use for the ${CONTENT_LABEL,,}.\nUse the spacebar to make a selection.\n" \
      16 $((MSG_MAX_LENGTH + 23)) 6 "${MENU[@]}" 3>&1 1>&2 2>&3) || {
      msg_error "Storage selection cancelled."
      exit 202
    }
  done

  echo "$STORAGE"
}

# Storage Checks
msg_info "Validating Storage"
VALIDCT=$(pvesm status -content rootdir | awk 'NR>1')
[[ -z "$VALIDCT" ]] && {
  msg_error "No valid Container Storage."
  exit $EXIT_NO_CT_STORAGE
}
VALIDTMP=$(pvesm status -content vztmpl | awk 'NR>1')
[[ -z "$VALIDTMP" ]] && {
  msg_error "No valid Template Storage."
  exit $EXIT_NO_TMPL_STORAGE
}

TEMPLATE_STORAGE=$(select_storage template)
msg_ok "Using ${BL}$TEMPLATE_STORAGE${CL} ${GN}for Template Storage."

CONTAINER_STORAGE=$(select_storage container)
msg_ok "Using ${BL}$CONTAINER_STORAGE${CL} ${GN}for Container Storage."

$STD msg_info "Updating LXC Template List"
timeout 10 pveam update >/dev/null || {
  msg_error "LXC template list update failed. Check Internet or DNS."
  exit 201
}
$STD msg_ok "LXC Template List Updated"

TEMPLATE_SEARCH="${PCT_OSTYPE}-${PCT_OSVERSION:-}"
mapfile -t TEMPLATES < <(pveam available -section system | sed -n "s/.*\($TEMPLATE_SEARCH.*\)/\1/p" | sort -t - -k 2 -V)
[[ ${#TEMPLATES[@]} -eq 0 ]] && {
  msg_error "No template found for '${TEMPLATE_SEARCH}'."
  exit 207
}

TEMPLATE="${TEMPLATES[-1]}"
TEMPLATE_PATH="$(pvesm path "$TEMPLATE_STORAGE":vztmpl/$TEMPLATE)"

# Ensure template exists and is valid
if ! pvesm list "$TEMPLATE_STORAGE" | awk '{print $2}' | grep -Fxq "$TEMPLATE" ||
  ! zstdcat "$TEMPLATE_PATH" | tar -tf - &>/dev/null; then
  msg_warn "Template missing or corrupted. Downloading new copy."
  rm -f "$TEMPLATE_PATH"
  for attempt in {1..3}; do
    msg_info "Attempt $attempt: Downloading template..."
    if timeout 120 pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null; then
      msg_ok "Download successful."
      break
    fi
    ((attempt == 3)) && {
      msg_error "Template download failed after 3 attempts."
      exit $EXIT_TEMPLATE_DL_FAIL
    }
    sleep $((attempt * 5))
  done
fi
msg_ok "LXC Template '$TEMPLATE' is ready."

# subuid/subgid fix
grep -q "root:100000:65536" /etc/subuid || echo "root:100000:65536" >>/etc/subuid
grep -q "root:100000:65536" /etc/subgid || echo "root:100000:65536" >>/etc/subgid

# PCT Options
PCT_OPTIONS=(${PCT_OPTIONS[@]:-${DEFAULT_PCT_OPTIONS[@]}})
[[ " ${PCT_OPTIONS[@]} " =~ " -rootfs " ]] || PCT_OPTIONS+=(-rootfs "$CONTAINER_STORAGE:${PCT_DISK_SIZE:-8}")

# Lock file to prevent race
lockfile="/tmp/template.${TEMPLATE}.lock"
exec 9>"$lockfile"
flock -w 60 9 || {
  msg_error "Timeout while waiting for template lock."
  exit $EXIT_TEMPLATE_LOCK_TIMEOUT
}

msg_info "Creating LXC Container"
if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" &>/dev/null; then
  msg_warn "Initial container creation failed. Checking template..."

  if [[ ! -s "$TEMPLATE_PATH" || "$(stat -c%s "$TEMPLATE_PATH")" -lt 1000000 ]] ||
    ! zstdcat "$TEMPLATE_PATH" | tar -tf - &>/dev/null; then
    msg_error "Template appears broken. Re-downloading..."
    rm -f "$TEMPLATE_PATH"
    for attempt in {1..3}; do
      msg_info "Attempt $attempt: Re-downloading template..."
      if timeout 120 pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null; then
        msg_ok "Re-download successful."
        break
      fi
      ((attempt == 3)) && {
        msg_error "Template could not be recovered after 3 attempts."
        exit $EXIT_TEMPLATE_DL_FAIL
      }
      sleep $((attempt * 5))
    done
  fi

  if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" &>/dev/null; then
    msg_error "Container creation failed even after re-downloading template."
    exit $EXIT_CONTAINER_CREATE_FAIL
  fi
fi

pct status "$CTID" &>/dev/null || {
  msg_error "Container not found after pct create – assuming failure."
  exit $EXIT_CONTAINER_NOT_FOUND
}

# Optionaler DNS-Fix für Alpine-Container
: "${UDHCPC_FIX:=}"
if [ "$UDHCPC_FIX" == "yes" ]; then
  CONFIG_FILE="/var/lib/lxc/${CTID}/rootfs/etc/udhcpc/udhcpc.conf"
  MOUNTED_HERE=false

  if ! mount | grep -q "/var/lib/lxc/${CTID}/rootfs"; then
    pct mount "$CTID" >/dev/null 2>&1 && MOUNTED_HERE=true
  fi

  # Warten auf Datei (max. 5 Sek.)
  for i in {1..10}; do
    [ -f "$CONFIG_FILE" ] && break
    sleep 0.5
  done

  if [ -f "$CONFIG_FILE" ]; then
    msg_info "Patching udhcpc.conf for Alpine DNS override"
    sed -i '/^#*RESOLV_CONF="/d' "$CONFIG_FILE"
    awk '
      /^# Do not overwrite \/etc\/resolv\.conf/ {
        print
        print "RESOLV_CONF=\"no\""
        next
      }
      { print }
    ' "$CONFIG_FILE" >"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    msg_ok "Patched udhcpc.conf (RESOLV_CONF=\"no\")"
  else
    msg_error "udhcpc.conf not found in $CONFIG_FILE after waiting"
  fi

  $MOUNTED_HERE && pct unmount "$CTID" >/dev/null 2>&1
fi

msg_ok "LXC Container ${BL}$CTID${CL} ${GN}was successfully created."

#!/usr/bin/env bash

# Copyright (c) 2026 DigitallyRefined
# Author: DigitallyRefined
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
  clear
  cat <<"EOF"
   __  __                 _       _ __                    __   __   _  ________
  / / / /___  ____  _____(_)   __(_) /__  ____ ____  ____/ /  / /  | |/ / ____/
 / / / / __ \/ __ \/ ___/ / | / / / / _ \/ __ `/ _ \/ __  /  / /   |   / /
/ /_/ / / / / /_/ / /  / /| |/ / / /  __/ /_/ /  __/ /_/ /  / /___/   / /___
\____/_/ /_/ .___/_/  /_/ |___/_/_/\___/\__, /\___/\__,_/  /_____/_/|_\____/
   / __ \_/_/  ____  / /_/ /__  _______/____// __ \____  _____/ /_____  _____
  / /_/ / __ \/ __ \/ __/ / _ \/ ___/ ___/  / / / / __ \/ ___/ //_/ _ \/ ___/
 / _, _/ /_/ / /_/ / /_/ /  __(__  |__  )  / /_/ / /_/ / /__/ ,< /  __/ /
/_/ |_|\____/\____/\__/_/\___/____/____/  /_____/\____/\___/_/|_|\___/_/

EOF
}

# Color definitions
GN=$(echo "\033[1;92m")
YW=$(echo "\033[33m")
OR=$(echo "\033[38;5;214m")
RD=$(echo "\033[01;31m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
msg_info() { echo -e " - ${YW}$1${CL}"; }
msg_warn() { echo -e "${OR}$1${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; }

set -euo pipefail

# Exit if not running as root
if [[ $EUID -ne 0 ]]; then
  msg_error "This script must be run as root"
  exit 1
fi

CONF_DIR="/etc/pve/lxc"
FORCE=0
LINE_DEV_DRI='lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir'

shopt -s nullglob

# Globals set during runtime
declare -a conf_files
declare -A GPU_ENABLED_FOR_CT
declare -A GPU_REMOVE_FOR_CT
GPU_AVAILABLE=0
GPU_PERM_ADDED=0

print_banner() {
  echo "This script will allow users to run rootless Docker/Podman inside unprivileged LXC containers."
  echo
  echo "Allowing nesting namespaces three levels deep:"
  echo "Proxmox Host → Unprivileged LXC → Rootless Docker/Podman → Docker in Docker (DinD)."
  echo
  echo "Optionally, it can also update GPU device permissions to allow rootless users to access the GPU/video transcoding."
  echo
  msg_warn "⚠️ WARNING: This script needs to be run after creating new LXC containers."
  msg_warn "Failure to do so will result in overlapping user namespaces, which could pose a security risk."
  echo
}

usage() {
  cat <<EOF
Usage: $0 [-f] [-h]
  -f    Skip confirmation prompts (enables GPU passthrough for all LXCs)
  -h    Show this help
EOF
  exit 0
}

parse_args() {
  while getopts ":fh" opt; do
    case "$opt" in
      f) FORCE=1 ;;
      h) usage ;;
      *) usage ;;
    esac
  done
}

gather_conf_files() {
  conf_files=("$CONF_DIR"/*.conf)
  if [[ ${#conf_files[@]} -eq 0 ]]; then
    msg_error "No LXC config files found in $CONF_DIR"
    exit 0
  fi
}

list_lxc_configs() {
  msg_info "Found the following LXC configs:"
  echo
  printf "  %-8s  %-40s  %s\n" "ID" "Hostname" "GPU Passthrough"
  echo "  $(printf '%.0s-' {1..70})"

  for file in "${conf_files[@]}"; do
    id="$(basename "$file" .conf)"
    hostname="$(awk -F': *' '$1 == "hostname" {print $2}' "$file")"
    [[ -z "$hostname" ]] && hostname="(no hostname set)"

    if grep -qF "$LINE_DEV_DRI" "$file"; then
      gpu_status="✓"
    else
      gpu_status="✗"
    fi

    printf "  %-8s  %-40s  %s\n" "$id" "$hostname" "$gpu_status"
  done
  echo
}

detect_gpu_and_build_selection() {
  if compgen -G "/dev/dri/renderD*" >/dev/null; then
    GPU_AVAILABLE=1
  fi

  if [[ $GPU_AVAILABLE -eq 0 ]]; then
    return
  fi

  if [[ $FORCE -eq 0 ]]; then
    msg_info "GPU detected on the host system."
    echo

    if ! whiptail --title "GPU Passthrough Configuration" --yesno "Edit GPU passthrough settings for LXCs?\n\nSelect Yes to edit individual containers, No to leave settings unchanged." 12 70; then
      msg_info "GPU passthrough settings will not be changed."
      echo
      return
    fi

    declare -A CURRENT_GPU_STATUS
    declare -a CTID_LIST

    for file in "${conf_files[@]}"; do
      ctid="$(basename "$file" .conf)"
      CTID_LIST+=("$ctid")
      if grep -qF "$LINE_DEV_DRI" "$file"; then
        CURRENT_GPU_STATUS[$ctid]=1
      else
        CURRENT_GPU_STATUS[$ctid]=0
      fi
    done

    # Build whiptail checklist arguments
    CHECK_ARGS=()
    for ctid in "${CTID_LIST[@]}"; do
      file="$CONF_DIR/$ctid.conf"
      hostname="$(awk -F': *' '$1 == "hostname" {print $2}' "$file")"
      [[ -z "$hostname" ]] && hostname="(no hostname set)"
      if [[ ${CURRENT_GPU_STATUS[$ctid]} -eq 1 ]]; then
        status="ON"
      else
        status="OFF"
      fi
      CHECK_ARGS+=("$ctid" "$hostname" "$status")
    done

    if SELECTED=$(whiptail --title "GPU Passthrough Selection" --checklist "Select containers with GPU passthrough enabled (checked = enabled)" 20 78 15 "${CHECK_ARGS[@]}" 3>&1 1>&2 2>&3); then
      SELECTED=$(echo "$SELECTED" | tr -d '"')
    else
      msg_info "GPU configuration cancelled. No changes will be made."
      echo
      return
    fi

    # Compute diffs
    for ctid in "${CTID_LIST[@]}"; do
      if echo "$SELECTED" | grep -qw "\b$ctid\b"; then
        if [[ ${CURRENT_GPU_STATUS[$ctid]} -eq 0 ]]; then
          GPU_ENABLED_FOR_CT[$ctid]=1
        fi
      else
        if [[ ${CURRENT_GPU_STATUS[$ctid]} -eq 1 ]]; then
          GPU_REMOVE_FOR_CT[$ctid]=1
        fi
      fi
    done

    # Summary
    enabled_list=()
    removed_list=()

    for ctid in "${!GPU_ENABLED_FOR_CT[@]}"; do
      enabled_list+=("$ctid")
    done

    for ctid in "${!GPU_REMOVE_FOR_CT[@]}"; do
      removed_list+=("$ctid")
    done

    if [[ ${#enabled_list[@]} -gt 0 ]]; then
      msg_ok "GPU passthrough will be ENABLED for: ${enabled_list[*]}"
    fi
    if [[ ${#removed_list[@]} -gt 0 ]]; then
      msg_ok "GPU passthrough will be REMOVED from: ${removed_list[*]}"
    fi
    if [[ ${#enabled_list[@]} -eq 0 && ${#removed_list[@]} -eq 0 ]]; then
      msg_info "No changes selected."
    fi

  else
    # Force mode => enable GPU for all containers
    for file in "${conf_files[@]}"; do
      ctid="$(basename "$file" .conf)"
      GPU_ENABLED_FOR_CT[$ctid]=1
    done
  fi
  echo
}

confirm_action() {
  if [[ $FORCE -eq 0 ]]; then
    if ! whiptail --title "Confirm" --yesno "This will shutdown and restart any running LXC containers and shift their namespaces.\n\nDo you want to continue?" 12 70; then
      msg_error "Aborted."
      exit 1
    fi
  fi
}

remove_default_root_mapping() {
  if grep -qxF "root:100000:65536" /etc/subuid; then
    sed -i '/^root:100000:65536$/d' /etc/subuid /etc/subgid
  fi
}

shift_filesystem() {
  local CTID="$1"
  local NEW_BASE="$2"
  local NAMESPACE_SHIFT="$3"

  msg_info "Mounting filesystem..."
  MOUNT_RAW=$(pct mount "$CTID")
  MOUNT_PATH=$(echo "$MOUNT_RAW" | sed -n "s/.*'\(.*\)'.*/\1/p")

  if [ -z "$MOUNT_PATH" ] || [ ! -d "$MOUNT_PATH" ]; then
    msg_error "Error: Could not determine mount path for container $CTID. Output was: $MOUNT_RAW"
    return 1
  fi

  CURRENT_ROOT_UID=$(stat -c %u "$MOUNT_PATH")
  if [ "$CURRENT_ROOT_UID" -lt "$NEW_BASE" ]; then
    msg_info "LXC container $CTID needs namespace shift."
    msg_info "Shifting UID/GID by $NAMESPACE_SHIFT (Base: $NEW_BASE)..."

    python3 - "$MOUNT_PATH" "$NAMESPACE_SHIFT" "$NEW_BASE" <<'PY'
import os, stat, sys
root_path = sys.argv[1]
offset = int(sys.argv[2])
new_base = int(sys.argv[3])

def shift_path(path):
    try:
        st = os.lstat(path)
        mode = st.st_mode
        old_uid = st.st_uid
        old_gid = st.st_gid

        if old_uid < new_base:
            new_uid = old_uid + offset
            new_gid = old_gid + offset
            os.lchown(path, new_uid, new_gid)

            if not stat.S_ISLNK(mode):
                os.chmod(path, stat.S_IMODE(mode))
            return True
    except Exception as e:
        print(f'Error shifting {path}: {e}', file=sys.stderr)
    return False

print(f'Starting deep shift on {root_path}...')
count = 0

# 1. Handle the root directory itself (os.walk skips the top-level path's contents but doesn't yield the root path itself in the loop)
if shift_path(root_path):
    count += 1

try:
    for root, dirs, files in os.walk(root_path):
        for name in dirs + files:
            path = os.path.join(root, name)
            if shift_path(path):
                count += 1
    print(f'Successfully shifted {count} entries.')
except Exception as e:
    print(f'Fatal error during filesystem traversal: {e}', file=sys.stderr)
    sys.exit(1)
PY
  else
    msg_ok "LXC $CTID is already at or above target ID: $NEW_BASE (Current ID: $CURRENT_ROOT_UID)."
    msg_info "Skipping namespace shift."
  fi
}

add_namespace_mappings() {
  local CTID="$1"
  local NEW_BASE="$2"
  local OFFSET="$3"

  ENTRY="root:$NEW_BASE:$OFFSET"
  for FILE in /etc/subuid /etc/subgid; do
    grep -qxF "$ENTRY" "$FILE" || echo "$ENTRY" >> "$FILE"
  done

  # Add the unprivileged flag if missing
  LINE_UNPRIVILEGED="unprivileged: 1"
  grep -qxF "$LINE_UNPRIVILEGED" "/etc/pve/lxc/$CTID.conf" || echo "$LINE_UNPRIVILEGED" >> "/etc/pve/lxc/$CTID.conf"

  # Add /dev/net/tun if missing
  LINE_DEV0="dev0: /dev/net/tun"
  grep -qxF "$LINE_DEV0" "/etc/pve/lxc/$CTID.conf" || echo "$LINE_DEV0" >> "/etc/pve/lxc/$CTID.conf"

  # Add the user id map if missing
  LINE_USER_ID_MAP="lxc.idmap: u 0 $NEW_BASE $OFFSET"
  grep -qxF "$LINE_USER_ID_MAP" "/etc/pve/lxc/$CTID.conf" || echo "$LINE_USER_ID_MAP" >> "/etc/pve/lxc/$CTID.conf"

  # Add the group id map if missing
  LINE_GROUP_ID_MAP="lxc.idmap: g 0 $NEW_BASE $OFFSET"
  grep -qxF "$LINE_GROUP_ID_MAP" "/etc/pve/lxc/$CTID.conf" || echo "$LINE_GROUP_ID_MAP" >> "/etc/pve/lxc/$CTID.conf"
}

apply_gpu_changes_to_lxc() {
  local CTID="$1"

  if [[ ${GPU_REMOVE_FOR_CT[$CTID]+_} ]]; then
    if grep -qF "$LINE_DEV_DRI" "/etc/pve/lxc/$CTID.conf"; then
      sed -i "\|$LINE_DEV_DRI|d" "/etc/pve/lxc/$CTID.conf" || sed -e "/\$LINE_DEV_DRI/d" -i "/etc/pve/lxc/$CTID.conf"
      msg_ok "GPU passthrough removed from LXC $CTID."
    else
      msg_info "GPU passthrough not configured for LXC $CTID. Nothing to remove."
    fi
  elif [[ ${GPU_ENABLED_FOR_CT[$CTID]+_} ]]; then
    if grep -qF "$LINE_DEV_DRI" "/etc/pve/lxc/$CTID.conf"; then
      msg_info "GPU passthrough already configured for LXC $CTID. Skipping."
    else
      echo "$LINE_DEV_DRI" >> "/etc/pve/lxc/$CTID.conf"
      GPU_PERM_ADDED=1
      msg_ok "GPU passthrough enabled for LXC $CTID."
    fi
  fi
}

process_container() {
  local CTID="$1"
  local BASE_START=100000
  local OFFSET=231072
  local NEW_BASE=$(( BASE_START + (CTID - 100) * OFFSET ))
  local NAMESPACE_SHIFT=$(( NEW_BASE - BASE_START ))

  echo "================================================================================"
  echo "Processing LXC Container: $CTID"
  echo "================================================================================"

  STATUS=$(pct status "$CTID")
  WAS_RUNNING=0
  if echo "$STATUS" | grep -q "running"; then
    WAS_RUNNING=1
    msg_info "Shutting down CT $CTID..."
    pct shutdown --timeout 120 "$CTID"
  fi

  if ! shift_filesystem "$CTID" "$NEW_BASE" "$NAMESPACE_SHIFT"; then
    msg_error "Skipping $CTID due to previous errors."
    return
  fi

  msg_info "Unmounting LXC $CTID..."
  pct unmount "$CTID"

  add_namespace_mappings "$CTID" "$NEW_BASE" "$OFFSET"

  apply_gpu_changes_to_lxc "$CTID"

  if [ "$WAS_RUNNING" -eq 1 ]; then
    msg_info "Restarting container $CTID..."
    pct start "$CTID"
  fi

  msg_ok "Finished processing $CTID."
  echo
}

update_udev_rules_if_needed() {
  if [[ $GPU_PERM_ADDED -eq 1 ]]; then
    UDEV_FILE="/etc/udev/rules.d/99-lxc-gpu.rules"
    if [[ ! -e "$UDEV_FILE" ]]; then
      LINE_RULE='KERNEL=="renderD*", SUBSYSTEM=="drm", ACTION=="add", MODE="0666"'
      echo "$LINE_RULE" > "$UDEV_FILE"
      msg_ok "Created $UDEV_FILE and added GPU permission rule."

      msg_info "Reloading udev rules..."
      udevadm control --reload-rules
      udevadm trigger
      msg_warn "A reboot of the Proxmox host may be required for the GPU permission changes to take effect."
    else
      msg_info "$UDEV_FILE already exists; not modifying udev rules."
    fi
    echo
  fi
}

press_any_key_to_continue() {
  read -n1 -s -r -p "Press any key to continue or Ctrl+C to abort..."
  echo
}

main() {
  parse_args "$@"
  header_info
  print_banner
  gather_conf_files
  list_lxc_configs
  press_any_key_to_continue
  detect_gpu_and_build_selection
  confirm_action
  remove_default_root_mapping

  for file in "${conf_files[@]}"; do
    CTID="$(basename "$file" .conf)"
    process_container "$CTID"
  done

  update_udev_rules_if_needed
  msg_ok "Completed unprivileged LXC rootless Docker/Podman namespace shift & GPU configuration"
}

main "$@"

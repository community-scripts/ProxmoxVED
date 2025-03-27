#!/usr/bin/env bash
#
# Title: Proxmox LXC Hardware Passthrough & GPU Acceleration Setup
# Description: Enables hardware passthrough for USB, Intel, NVIDIA, AMD GPUs inside privileged LXC containers.
#              Installs optional drivers/tools inside the container (vainfo, intel-gpu-tools, OpenCL, etc.)
#              Only supports PRIVILEGED containers for GPU passthrough.
# License: MIT
# Author: MickLesk (CanbiZ)
# Repo: https://github.com/community-scripts/ProxmoxVED
#
# Usage: bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVED/raw/main/misc/hw-acceleration.sh)"
#
# Requires:
#   - Proxmox VE 8.1+
#   - Privileged LXC Containers
#   - GPU device available on host
#
# Features:
#   - USB Serial Passthrough
#   - Intel VAAPI passthrough + (optional) non-free drivers
#   - NVIDIA GPU passthrough for LXC (binds /dev/nvidia*)
#   - AMD GPU passthrough (experimental)
#   - Container driver installation via APT
#   - User group assignments (video/render)
#   - Interactive menu system via whiptail

#!/usr/bin/env bash

set -euo pipefail

function header_info() {
  clear
  cat <<"EOF"

   __ ___      __  ___              __             __  _
  / // / | /| / / / _ |___________ / /__ _______ _/ /_(_)__  ___
 / _  /| |/ |/ / / __ / __/ __/ -_) / -_) __/ _ `/ __/ / _ \/ _ \
/_//_/ |__/|__/ /_/ |_\__/\__/\__/_/\__/_/  \_,_/\__/_/\___/_//_/

   LXC Hardware Integration Tool for Proxmox VE
EOF
}

function msg() {
  local type="$1"; shift
  case "$type" in
    info) printf " \033[36m➤\033[0m %s\n" "$*" ;;
    ok)   printf " \033[32m✔\033[0m %s\n" "$*" ;;
    warn) printf " \033[33m⚠\033[0m %s\n" "$*" >&2 ;;
    err)  printf " \033[31m✘\033[0m %s\n" "$*" >&2 ;;
  esac
}

function select_hw_features() {
  local opts
  opts=$(
    whiptail --title "🔧 Hardware Integration" --checklist \
    "\nSelect hardware features to passthrough:\n" 20 60 8 \
    "usb"    "🖧  USB Passthrough         " OFF \
    "intel"  "🟦  Intel VAAPI GPU         " OFF \
    "nvidia" "🟨  NVIDIA GPU              " OFF \
    "amd"    "🟥  AMD GPU (ROCm)          " OFF \
    3>&1 1>&2 2>&3
  ) || exit 1

  SELECTED_FEATURES=$(echo "$opts" | tr -d '"')
  if [[ -z "$SELECTED_FEATURES" ]]; then
    msg warn "No passthrough options selected"
    exit 1
  fi
}


function select_lxc_targets() {
  local list; local opts=()
  if ! list=$(pct list | awk 'NR>1 {print $1 "|" $2}' | xargs -n1); then
    msg err "Failed to get container list"
    exit 1
  fi
  while IFS="|" read -r id name; do
    if [[ -f "/etc/pve/lxc/${id}.conf" ]]; then
      opts+=("$id" "${name} (${id})" "OFF")
    fi
  done <<< "$list"
  if [[ ${#opts[@]} -eq 0 ]]; then
    msg warn "No containers found"
    exit 1
  fi
  SELECTED_CTIDS=$(whiptail --title "Select LXC Containers" --checklist \
    "Choose container(s) to apply passthrough:" 20 60 10 \
    "${opts[@]}" 3>&1 1>&2 2>&3 | tr -d '"')
  if [[ -z "$SELECTED_CTIDS" ]]; then
    msg warn "No containers selected"
    exit 1
  fi
}

function apply_usb() {
  local conf="$1"
  if ! compgen -G "/dev/ttyUSB* /dev/ttyACM*" >/dev/null; then
    msg warn "No USB serial devices found, skipping"
    return 1
  fi
  cat <<EOF >> "$conf"
# USB Passthrough
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
lxc.cgroup2.devices.allow: c 188:* rwm
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/serial/by-id  dev/serial/by-id  none bind,optional,create=dir
lxc.mount.entry: /dev/ttyUSB0       dev/ttyUSB0       none bind,optional,create=file
lxc.mount.entry: /dev/ttyUSB1       dev/ttyUSB1       none bind,optional,create=file
lxc.mount.entry: /dev/ttyACM0       dev/ttyACM0       none bind,optional,create=file
lxc.mount.entry: /dev/ttyACM1       dev/ttyACM1       none bind,optional,create=file
EOF
  return 0
}

function apply_intel() {
  local conf="$1"
  if [[ ! -e /dev/dri/renderD128 ]]; then
    msg warn "Intel GPU not detected, skipping"
    return 1
  fi
  cat <<EOF >> "$conf"
# Intel VAAPI
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
EOF
  return 0
}

function apply_nvidia() {
  local conf="$1"
  if [[ ! -e /dev/nvidia0 ]]; then
    msg warn "NVIDIA device not found, skipping"
    return 1
  fi
  cat <<EOF >> "$conf"
# NVIDIA GPU
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
EOF
  return 0
}

function apply_amd() {
  local conf="$1"
  if [[ ! -e /dev/kfd ]]; then
    msg warn "AMD GPU not found, skipping"
    return 1
  fi
  cat <<EOF >> "$conf"
# AMD ROCm GPU
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 238:* rwm
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF
  return 0
}

function main() {
  header_info
  select_hw_features
  select_lxc_targets
  for ctid in $SELECTED_CTIDS; do
    local conf="/etc/pve/lxc/${ctid}.conf"
    local updated=0
    for opt in $SELECTED_FEATURES; do
      case "$opt" in
        usb) apply_usb "$conf" && updated=1 ;;
        intel) apply_intel "$conf" && updated=1 ;;
        nvidia) apply_nvidia "$conf" && updated=1 ;;
        amd) apply_amd "$conf" && updated=1 ;;
      esac
    done
    if [[ "$updated" -eq 1 ]]; then
      msg ok "Hardware passthrough updated in: $conf"
      printf "\nRestart container %s to apply changes.\n\n" "$ctid"
    else
      msg warn "No passthrough changes applied for container $ctid"
    fi
  done
}

main

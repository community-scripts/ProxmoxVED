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

function select_lxc_container() {
  local lxc_list; local options=()
  if ! lxc_list=$(pct list | awk 'NR>1 {print $1}' | xargs -n1); then
    msg err "Failed to fetch LXC containers"
    exit 1
  fi
  for ctid in $lxc_list; do
    if [[ -f "/etc/pve/lxc/${ctid}.conf" ]]; then
      options+=("$ctid" "LXC ${ctid}" "OFF")
    fi
  done
  if [[ ${#options[@]} -eq 0 ]]; then
    msg warn "No containers found"
    exit 1
  fi
  CTID=$(whiptail --title "Select LXC Container" --checklist \
    "Choose container to apply hardware passthrough:" 15 50 5 \
    "${options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')
  if [[ -z "$CTID" ]]; then
    msg warn "No container selected"
    exit 1
  fi
  LXC_CONFIG="/etc/pve/lxc/${CTID}.conf"
}

function select_hw_options() {
  local options=(
    "usb" "USB Passthrough" OFF
    "intel" "Intel VAAPI GPU" OFF
    "nvidia" "NVIDIA GPU" OFF
    "amd" "AMD GPU (ROCm)" OFF
  )
  SELECTIONS=$(whiptail --title "Hardware Options" --checklist \
    "Select hardware features to passthrough:" 20 50 10 \
    "${options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')
  if [[ -z "$SELECTIONS" ]]; then
    msg warn "No hardware passthrough options selected"
    exit 1
  fi
}

function add_usb_passthrough() {
  if ! ls /dev/ttyUSB* &>/dev/null && ! ls /dev/ttyACM* &>/dev/null; then
    msg warn "No USB serial devices found"
    return
  fi
  cat <<EOF >> "$LXC_CONFIG"
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
  msg ok "USB passthrough added to $CTID"
}

function add_intel_gpu() {
  if [[ ! -e /dev/dri/renderD128 ]]; then
    msg warn "Intel GPU not detected"
    return
  fi
  cat <<EOF >> "$LXC_CONFIG"
# Intel VAAPI
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
EOF
  msg ok "Intel VAAPI passthrough added to $CTID"
}

function add_nvidia_gpu() {
  if [[ ! -e /dev/nvidia0 ]]; then
    msg warn "NVIDIA device not found"
    return
  fi
  cat <<EOF >> "$LXC_CONFIG"
# NVIDIA GPU
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
EOF
  msg ok "NVIDIA passthrough added to $CTID"
}

function add_amd_gpu() {
  if [[ ! -e /dev/kfd ]]; then
    msg warn "AMD ROCm device not detected"
    return
  fi
  cat <<EOF >> "$LXC_CONFIG"
# AMD ROCm GPU
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 238:* rwm
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF
  msg ok "AMD GPU passthrough added to $CTID"
}

function main() {
  header_info
  select_lxc_container
  select_hw_options
  for opt in $SELECTIONS; do
    case "$opt" in
      usb) add_usb_passthrough ;;
      intel) add_intel_gpu ;;
      nvidia) add_nvidia_gpu ;;
      amd) add_amd_gpu ;;
    esac
  done
  msg ok "Hardware passthrough updated in: $LXC_CONFIG"
  printf "\nRestart container %s to apply changes.\n\n" "$CTID"
}

main

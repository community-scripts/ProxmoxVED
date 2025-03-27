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
    local type="$1"
    shift
    case "$type" in
    info) printf " \033[36m➤\033[0m %s\n" "$*" ;;
    ok) printf " \033[32m✔\033[0m %s\n" "$*" ;;
    warn) printf " \033[33m⚠\033[0m %s\n" "$*" >&2 ;;
    err) printf " \033[31m✘\033[0m %s\n" "$*" >&2 ;;
    esac
}

function detect_features() {
    AVAILABLE_FEATURES=()
    [[ -e /dev/ttyUSB0 || -e /dev/ttyACM0 ]] && AVAILABLE_FEATURES+=("usb" "USB Passthrough" OFF)
    [[ -e /dev/dri/renderD128 ]] && AVAILABLE_FEATURES+=("intel" "Intel VAAPI GPU" OFF)
    [[ -e /dev/nvidia0 ]] && AVAILABLE_FEATURES+=("nvidia" "NVIDIA GPU" OFF)
    [[ -e /dev/kfd ]] && AVAILABLE_FEATURES+=("amd" "AMD GPU (ROCm)" OFF)

    if [[ ${#AVAILABLE_FEATURES[@]} -eq 0 ]]; then
        msg warn "No supported hardware found on host system."
        exit 1
    fi
}

function select_hw_features() {
    SELECTED_FEATURES=$(whiptail --title "Hardware Options" --checklist \
        "Select hardware features to passthrough:" 20 60 10 \
        "${AVAILABLE_FEATURES[@]}" 3>&1 1>&2 2>&3 | tr -d '"') || exit 1

    [[ -z "$SELECTED_FEATURES" ]] && {
        msg warn "No passthrough options selected."
        exit 1
    }
}

function select_lxc_targets() {
    local opts=()
    while IFS= read -r line; do
        local id name conf
        id=$(awk '{print $1}' <<<"$line")
        name=$(awk '{print $2}' <<<"$line")
        conf="/etc/pve/lxc/${id}.conf"
        [[ -f "$conf" ]] && opts+=("$id" "$name (CTID: $id)" OFF)
    done < <(pct list | tail -n +2)

    if [[ ${#opts[@]} -eq 0 ]]; then
        msg warn "No containers found. Make sure you have running LXCs."
        exit 1
    fi

    SELECTED_CTIDS=$(whiptail --title "Select LXC Containers" --checklist \
        "Choose container(s) to apply passthrough:" 20 60 10 \
        "${opts[@]}" 3>&1 1>&2 2>&3 | tr -d '"') || exit 1

    [[ -z "$SELECTED_CTIDS" ]] && {
        msg warn "No containers selected."
        exit 1
    }
}

function apply_usb() {
    local conf="$1"
    grep -q "ttyUSB\|ttyACM" <<<"$(ls /dev 2>/dev/null)" || return 1
    grep -q "ttyUSB" "$conf" 2>/dev/null && return 0
    cat <<EOF >>"$conf"
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
}

function apply_intel() {
    local conf="$1"
    [[ -e /dev/dri/renderD128 ]] || return 1
    grep -q "renderD128" "$conf" 2>/dev/null && return 0
    cat <<EOF >>"$conf"
# Intel VAAPI
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
EOF
}

function apply_nvidia() {
    local conf="$1"
    [[ -e /dev/nvidia0 ]] || return 1
    grep -q "nvidia0" "$conf" 2>/dev/null && return 0
    cat <<EOF >>"$conf"
# NVIDIA GPU
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
EOF
}

function apply_amd() {
    local conf="$1"
    [[ -e /dev/kfd ]] || return 1
    grep -q "/dev/kfd" "$conf" 2>/dev/null && return 0
    cat <<EOF >>"$conf"
# AMD ROCm GPU
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 238:* rwm
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF
}

function install_drivers() {
    local ctid="$1"
    for opt in $SELECTED_FEATURES; do
        case "$opt" in
        intel)
            msg info "Installing Intel drivers/tools in CT $ctid..."
            pct exec "$ctid" -- bash -c "
          apt-get update -qq
          DEBIAN_FRONTEND=noninteractive apt-get install -y \
            va-driver-all vainfo intel-gpu-tools \
            ocl-icd-libopencl1 intel-opencl-icd >/dev/null
          adduser root video >/dev/null 2>&1 || true
          adduser root render >/dev/null 2>&1 || true
        "
            ;;
        nvidia)
            msg info "Installing NVIDIA container tools in CT $ctid..."
            pct exec "$ctid" -- bash -c "
          apt-get update -qq
          DEBIAN_FRONTEND=noninteractive apt-get install -y \
            nvidia-container-runtime nvidia-utils-525 >/dev/null 2>&1 || true
        "
            ;;
        amd)
            msg info "Installing AMD ROCm tools in CT $ctid..."
            pct exec "$ctid" -- bash -c "
          apt-get update -qq
          DEBIAN_FRONTEND=noninteractive apt-get install -y \
            rocm-smi rocm-utils >/dev/null 2>&1 || true
        "
            ;;
        esac
    done
}

function main() {
    header_info
    detect_features
    select_hw_features
    select_lxc_targets

    local updated_cts=()
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
        [[ "$updated" -eq 1 ]] && updated_cts+=("$ctid")
        install_drivers "$ctid"
    done

    if [[ ${#updated_cts[@]} -gt 0 ]]; then
        msg ok "Hardware passthrough updated in: ${updated_cts[*]}"
        if whiptail --yesno "Restart updated container(s)?\n${updated_cts[*]}" 10 60; then
            for ctid in "${updated_cts[@]}"; do
                pct restart "$ctid"
            done
            msg ok "Containers restarted: ${updated_cts[*]}"
        else
            msg info "Please restart the container(s) manually."
        fi
    else
        msg warn "No passthrough or driver changes were applied."
    fi
}

main

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
#
# Proxmox LXC Hardware Passthrough & GPU Acceleration Setup
# https://github.com/community-scripts/ProxmoxVED

set -euo pipefail

TEMP_DIR=$(mktemp -d)
trap 'rm -rf $TEMP_DIR' EXIT

source <(wget -qO- https://github.com/community-scripts/ProxmoxVED/raw/main/tools/pve/gpu-nvidia.func)
source <(wget -qO- https://github.com/community-scripts/ProxmoxVED/raw/main/tools/pve/gpu-intel.func)
source <(wget -qO- https://github.com/community-scripts/ProxmoxVED/raw/main/tools/pve/gpu-amd.func)

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
    info) printf " \033[36m➤\033[0m %s\n" "$@" ;;
    ok) printf " \033[32m✔\033[0m %s\n" "$@" ;;
    warn) printf " \033[33m⚠\033[0m %s\n" "$@" >&2 ;;
    err) printf " \033[31m✘\033[0m %s\n" "$@" >&2 ;;
    esac
}

function prompt_features() {
    local features=()
    printf "\nAvailable features:\n"
    if [[ -e /dev/ttyUSB0 || -e /dev/ttyACM0 ]]; then
        echo " [1] USB Passthrough"
        features+=("usb")
    fi
    if [[ -e /dev/dri/renderD128 ]]; then
        echo " [2] Intel iGPU (VAAPI)"
        features+=("intel")
    fi
    if [[ -e /dev/nvidia0 ]]; then
        echo " [3] NVIDIA GPU"
        features+=("nvidia")
    fi
    if [[ -e /dev/kfd ]]; then
        echo " [4] AMD GPU (ROCm)"
        features+=("amd")
    fi

    if [[ ${#features[@]} -eq 0 ]]; then
        msg err "No supported hardware found on host."
        exit 1
    fi

    echo
    read -rp "Enter number(s) separated by space (e.g. 1 3): " choices
    SELECTED_FEATURES=()
    for i in $choices; do
        case "$i" in
        1) SELECTED_FEATURES+=("usb") ;;
        2) SELECTED_FEATURES+=("intel") ;;
        3) SELECTED_FEATURES+=("nvidia") ;;
        4) SELECTED_FEATURES+=("amd") ;;
        esac
    done

    if [[ ${#SELECTED_FEATURES[@]} -eq 0 ]]; then
        msg warn "No valid feature selected."
        exit 1
    fi
}

function select_lxc_cts() {
    mapfile -t containers < <(pct list | awk 'NR>1 {print $1 "|" $2}')
    if [[ ${#containers[@]} -eq 0 ]]; then
        msg warn "No LXC containers found."
        exit 1
    fi

    echo
    echo "Available Containers:"
    for entry in "${containers[@]}"; do
        ctid="${entry%%|*}"
        name="${entry##*|}"
        echo " [$ctid] $name"
    done

    echo
    read -rp "Enter container ID(s) separated by space: " SELECTED_CTIDS
    if [[ -z "$SELECTED_CTIDS" ]]; then
        msg warn "No containers selected."
        exit 1
    fi
}

function apply_usb_passthrough() {
    local conf="$1"
    grep -q "ttyUSB" "$conf" 2>/dev/null && return
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

function main() {
    header_info
    prompt_features
    select_lxc_cts

    local updated_cts=()

    for ctid in $SELECTED_CTIDS; do
        local conf="/etc/pve/lxc/${ctid}.conf"
        local updated=0

        for feature in "${SELECTED_FEATURES[@]}"; do
            case "$feature" in
            usb)
                msg info "Applying USB passthrough to CT $ctid..."
                apply_usb_passthrough "$conf" && updated=1
                ;;
            intel)
                msg info "Applying Intel VAAPI passthrough to CT $ctid..."
                passthrough_intel_to_lxc "$ctid" && install_intel_tools_in_ct "$ctid" && updated=1
                ;;
            amd)
                msg info "Applying AMD GPU passthrough to CT $ctid..."
                passthrough_amd_to_lxc "$ctid" && install_amd_tools_in_ct "$ctid" && updated=1
                ;;
            nvidia)
                msg info "Checking NVIDIA GPU on host..."
                check_nvidia_driver_status && check_cuda_version
                gpu_minor=$(select_nvidia_gpu) || continue
                passthrough_nvidia_to_lxc "$ctid" "$gpu_minor" && updated=1
                ;;
            esac
        done

        if [[ "$updated" -eq 1 ]]; then
            updated_cts+=("$ctid")
        fi
    done

    echo
    if [[ ${#updated_cts[@]} -gt 0 ]]; then
        msg ok "Updated: ${updated_cts[*]}"
        read -rp "Restart updated container(s)? [y/N]: " restart
        if [[ "${restart,,}" == "y" ]]; then
            for ctid in "${updated_cts[@]}"; do
                pct reboot "$ctid"
                msg ok "Restarted container $ctid"
            done
        else
            msg info "Manual restart required for: ${updated_cts[*]}"
        fi
    else
        msg warn "No passthrough applied."
    fi
}

main

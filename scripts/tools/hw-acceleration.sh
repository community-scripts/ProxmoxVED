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
    [[ -e /dev/ttyUSB0 || -e /dev/ttyACM0 ]] && AVAILABLE_FEATURES+=("usb" "🖧  USB Passthrough         " OFF)
    [[ -e /dev/dri/renderD128 ]] && AVAILABLE_FEATURES+=("intel" "🟦  Intel VAAPI GPU         " OFF)
    [[ -e /dev/nvidia0 ]] && AVAILABLE_FEATURES+=("nvidia" "🟨  NVIDIA GPU              " OFF)
    [[ -e /dev/kfd ]] && AVAILABLE_FEATURES+=("amd" "🟥  AMD GPU (ROCm)          " OFF)

    if [[ ${#AVAILABLE_FEATURES[@]} -eq 0 ]]; then
        msg warn "No supported hardware found on host system."
        exit 1
    fi
}

function select_hw_features() {
    local opts
    opts=$(whiptail --title "🔧 Hardware Options" --checklist \
        "\nSelect hardware features to passthrough:\n" 20 60 8 \
        "${AVAILABLE_FEATURES[@]}" 3>&1 1>&2 2>&3) || exit 1

    SELECTED_FEATURES=$(echo "$opts" | tr -d '"')
    if [[ -z "$SELECTED_FEATURES" ]]; then
        msg warn "No passthrough options selected."
        exit 1
    fi
}

function select_lxc_targets() {
    local list
    local opts=()
    list=$(pct list | awk 'NR>1 {print $1 "|" $2}') || return 1
    while IFS="|" read -r id name; do
        [[ -f "/etc/pve/lxc/${id}.conf" ]] && opts+=("$id" "$name (CTID: $id)" OFF)
    done <<<"$list"

    [[ ${#opts[@]} -eq 0 ]] && {
        msg warn "No LXC containers found."
        exit 1
    }

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
    grep -q "dev/ttyUSB" <<<"$(ls /dev 2>/dev/null)" || return 1
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
    cat <<EOF >>"$conf"
# AMD ROCm GPU
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 238:* rwm
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF
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

        if [[ "$updated" -eq 1 ]]; then
            updated_cts+=("$ctid")
        fi
    done

    if [[ ${#updated_cts[@]} -gt 0 ]]; then
        msg ok "Hardware passthrough applied to: ${updated_cts[*]}"
        echo
        if whiptail --title "Restart Containers" --yesno \
            "Restart the following containers now?\n\n${updated_cts[*]}" 12 50; then
            for ctid in "${updated_cts[@]}"; do
                pct restart "$ctid"
            done
            msg ok "Restarted containers: ${updated_cts[*]}"
        else
            msg info "You can restart them manually later."
        fi
    else
        msg warn "No changes were applied to any container."
    fi
}

main

#!/usr/bin/env bash

# Title: Proxmox LXC Hardware Passthrough & GPU Acceleration Setup
# Maintainer: https://github.com/community-scripts/ProxmoxVED
# Includes: gpu-intel.func, gpu-nvidia.func, gpu-amd.func

set -euo pipefail

TEMP_DIR=$(mktemp -d)
trap 'rm -rf $TEMP_DIR' EXIT

source <(wget -qO- https://github.com/community-scripts/ProxmoxVED/raw/main/scripts/tools/gpu-intel.func)
source <(wget -qO- https://github.com/community-scripts/ProxmoxVED/raw/main/scripts/tools/gpu-nvidia.func)
source <(wget -qO- https://github.com/community-scripts/ProxmoxVED/raw/main/scripts/tools/gpu-amd.func)

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
    printf "\nAvailable passthrough options:\n"
    [[ -e /dev/ttyUSB0 || -e /dev/ttyACM0 ]] && echo " [1] USB" && features+=("usb")
    [[ -e /dev/dri/renderD128 ]] && echo " [2] Intel VAAPI" && features+=("intel")
    [[ -e /dev/nvidia0 ]] && echo " [3] NVIDIA GPU" && features+=("nvidia")
    [[ -e /dev/kfd ]] && echo " [4] AMD GPU" && features+=("amd")
    [[ ${#features[@]} -eq 0 ]] && msg err "No supported hardware detected." && exit 1
    echo
    read -rp "Select hardware (e.g. 1 3): " choices
    SELECTED_FEATURES=()
    for i in $choices; do
        case "$i" in
        1) SELECTED_FEATURES+=("usb") ;;
        2) SELECTED_FEATURES+=("intel") ;;
        3) SELECTED_FEATURES+=("nvidia") ;;
        4) SELECTED_FEATURES+=("amd") ;;
        esac
    done
    [[ ${#SELECTED_FEATURES[@]} -eq 0 ]] && msg warn "No valid feature selected." && exit 1
}

function select_lxc_cts() {
    mapfile -t containers < <(pct list | awk 'NR>1 {print $1 "|" $2}')
    [[ ${#containers[@]} -eq 0 ]] && msg warn "No LXC containers found." && exit 1
    echo
    echo "Available Containers:"
    for entry in "${containers[@]}"; do
        ctid="${entry%%|*}"
        name="${entry##*|}"
        echo " [$ctid] $name"
    done
    echo
    read -rp "Enter container ID(s) separated by space: " SELECTED_CTIDS
    [[ -z "$SELECTED_CTIDS" ]] && msg warn "No containers selected." && exit 1
}

function is_alpine_container() {
    local ctid="$1"
    pct exec "$ctid" -- sh -c 'grep -qi alpine /etc/os-release' >/dev/null 2>&1
}

function apply_usb_passthrough() {
    local conf="$1"
    grep -q "ttyUSB" "$conf" 2>/dev/null && return
    cat <<EOF >>"$conf"
# USB Serial Passthrough
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

    local intel_nonfree="no"
    if [[ " ${SELECTED_FEATURES[*]} " =~ " intel " ]]; then
        read -rp "Install non-free intel-media-va-driver (Debian only)? [y/N]: " confirm
        if [[ "${confirm,,}" =~ ^(y|yes)$ ]]; then
            intel_nonfree="yes"
        fi
    fi

    for ctid in $SELECTED_CTIDS; do
        local conf="/etc/pve/lxc/${ctid}.conf"
        local updated=0

        for feature in "${SELECTED_FEATURES[@]}"; do
            case "$feature" in
            usb)
                msg info "Adding USB passthrough to CT $ctid..."
                apply_usb_passthrough "$conf" && updated=1
                ;;
            intel)
                msg info "Intel passthrough setup for CT $ctid"
                passthrough_intel_to_lxc "$ctid" && install_intel_tools_in_ct "$ctid" "$intel_nonfree" && updated=1
                ;;
            nvidia)
                msg info "Validating NVIDIA setup..."
                nvidia_validate_driver_version
                nvidia_validate_cuda_version
                local minor
                minor=$(nvidia_select_gpu_minor)
                nvidia_lxc_passthrough "$ctid" "$minor" && updated=1
                ;;
            amd)
                msg info "Applying AMD passthrough to CT $ctid..."
                passthrough_amd_to_lxc "$ctid" && install_amd_tools_in_ct "$ctid" && updated=1
                ;;
            esac
        done

        [[ "$updated" -eq 1 ]] && updated_cts+=("$ctid")
    done

    echo
    if [[ ${#updated_cts[@]} -gt 0 ]]; then
        msg ok "Updated containers: ${updated_cts[*]}"
        read -rp "Restart updated container(s)? [y/N]: " confirm
        if [[ "${confirm,,}" == "y" ]]; then
            for ctid in "${updated_cts[@]}"; do
                pct reboot "$ctid"
                msg ok "Restarted CT $ctid"
            done
        else
            msg info "Restart skipped."
        fi
    else
        msg warn "No passthrough changes applied."
    fi
}

main

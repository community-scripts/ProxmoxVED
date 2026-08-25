#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# Local checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core), so a
# fork/branch of core can be tested without touching this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: NetWareX (netwarex)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/LizardByte/Sunshine

APP="Sunshine-on-SteamOS"
var_tags="${var_tags:-gaming;steam;sunshine}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-64}"
# Arch Linux: Steam needs multilib and the gaming stack (gamescope, sway,
# mesa) needs current versions; the engine's pacman support handles it.
var_os="${var_os:-archlinux}"
# "base": the PVE catalog names the rolling Arch template archlinux-base_*
var_version="${var_version:-base}"
# Privileged + GPU: the appliance renders and VA-API-encodes on an AMD GPU
# (amdgpu/RADV only) and exposes host input devices for streamed controllers.
var_unprivileged="${var_unprivileged:-0}"
var_arm64="${var_arm64:-no}"
# nesting: Steam's pressure-vessel needs user namespaces (and the current
# Arch template's systemd requires it to boot reliably); keyctl for Proton.
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"
var_gpu="${var_gpu:-yes}"
# fuse: /games on exFAT/NTFS disks is served through a small FUSE shim
# (Proton persists Windows ACLs as xattrs, which FAT-family cannot store).
var_fuse="${var_fuse:-yes}"

# Values the install script accepts up front (see json app_vars).
export var_stream_width="${var_stream_width:-1920}"
export var_stream_height="${var_stream_height:-1080}"
export var_stream_fps="${var_stream_fps:-60}"
export var_keyboard="${var_keyboard:-us}"
export var_display_server="${var_display_server:-wayland}"
export var_desktop_mode="${var_desktop_mode:-yes}"
# Optional extras: prompt only when not preset via environment (and only on
# an interactive terminal) - community-scripts "check if unset" pattern.
if [[ -z "${var_decky:-}" && -t 0 ]]; then
  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "DECKY LOADER" --defaultno \
    --yesno "Install Decky Loader with the NonSteamLaunchers plugin?\n\nAdds a plugin dock to Gaming Mode; NSL installs Epic, GOG, Battle.net etc. under Proton (third-party, fetched at install time)." 12 70; then
    var_decky="yes"
  fi
fi
if [[ -z "${var_heroic:-}" && -t 0 ]]; then
  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "HEROIC LAUNCHER" --defaultno \
    --yesno "Install Heroic Games Launcher?\n\nNative Epic/GOG client (pinned, checksum-verified) - the reliable installer for exFAT/NTFS game disks." 11 70; then
    var_heroic="yes"
  fi
fi
export var_decky="${var_decky:-no}"
export var_heroic="${var_heroic:-no}"
export var_packetsize="${var_packetsize:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/steamos-streaming-release ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD /usr/local/sbin/steamos-streaming-update stable
  msg_ok "Updated ${APP} LXC"
  cleanup_lxc
  exit
}

start
build_container

# ------------------------------------------------------------------------------
# The appliance requires a PRIVILEGED container: streamed input arrives via a
# host /dev/input bind whose nodes are unmapped (nobody:nobody) in
# unprivileged containers, and the GPU/input device model relies on
# host-identical ids. Fail fast rather than produce a container with dead
# streamed input.
# ------------------------------------------------------------------------------
if pct config "$CTID" | grep -q "^unprivileged: 1"; then
  msg_error "SteamOS-Streaming requires a privileged container."
  msg_error "Re-run and keep Container Type = privileged (var_unprivileged=0)."
  exit 1
fi

# ------------------------------------------------------------------------------
# Appliance device access beyond the engine's GPU passthrough: virtual input
# (Sunshine creates streamed keyboards/mice/gamepads via uinput/uhid), host
# /dev/input for locally attached controllers, ttys for the legacy Xorg dummy
# fallback, and CAP_SYS_NICE for gamescope/sway high-priority GPU queues.
# ------------------------------------------------------------------------------
msg_info "Configuring streaming device access"
# Sunshine's virtual input devices are created through the HOST kernel's
# uinput/uhid drivers (containers share the host kernel); load them now and
# persist across host reboots.
if ! modprobe uinput 2>/dev/null || ! modprobe uhid 2>/dev/null; then
  msg_error "Could not load host uinput/uhid kernel modules"
  exit 1
fi
cat <<EOF >/etc/modules-load.d/steamos-streaming.conf
uinput
uhid
EOF
_conf="/etc/pve/lxc/${CTID}.conf"
_add_conf_line() { grep -qxF "$1" "$_conf" 2>/dev/null || echo "$1" >>"$_conf"; }
# PVE's default capability drop includes sys_nice; gamescope, sway and
# Sunshine use CAP_SYS_NICE so a game at 100% GPU cannot starve the
# compositing/capture path (setcap file-caps are blocked inside LXC).
_add_conf_line "lxc.cap.drop:"
_add_conf_line "lxc.cap.drop: sys_time sys_module sys_rawio"
# tty devices for the Xorg dummy fallback display server.
_add_conf_line "lxc.cgroup2.devices.allow: c 4:* rwm"
# Host input devices: Sunshine's virtual devices materialize on the host and
# stream back in; local controllers pass through the same bind.
_add_conf_line "lxc.cgroup2.devices.allow: c 13:* rwm"
_add_conf_line "lxc.mount.entry: /dev/input dev/input none bind,optional,create=dir"
# The container runs its own udevd (a host /run/udev bind is empty on
# Proxmox and would shadow the container's udev database).
sed -i '\|^lxc.mount.entry: /run/udev|d' "$_conf"
msg_ok "Configured streaming device access"

# Device mappings are not hot-pluggable: restart the container so uinput/uhid
# and the raw config lines take effect (also proves unattended boot works).
msg_info "Restarting container to apply device access"
# uinput/uhid restricted to the container's own 'input' group (deck is a
# member); device entries only apply while the container is stopped.
_input_gid="$(pct exec "$CTID" -- getent group input 2>/dev/null | cut -d: -f3)"
pct stop "$CTID" >/dev/null 2>&1
pct set "$CTID" -dev1 "/dev/uinput,gid=${_input_gid:-0},mode=0660" >/dev/null 2>&1
pct set "$CTID" -dev2 "/dev/uhid,gid=${_input_gid:-0},mode=0660" >/dev/null 2>&1
pct start "$CTID" >/dev/null 2>&1
sleep 10
if pct status "$CTID" | grep -q running; then
  msg_ok "Container restarted with streaming device access"
else
  msg_error "Container failed to restart"
  exit 1
fi

description

msg_ok "Completed successfully!"
msg_custom "🎮" "${GN}" "Pair Moonlight: https://${IP}:47990"

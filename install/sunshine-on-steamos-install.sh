#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: NetWareX (netwarex)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/LizardByte/Sunshine

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ------------------------------------------------------------------------------
# SteamOS Streaming appliance payload, grafted from the standalone installer
# (github.com/netwarex/sunshine-on-steamos, install/sunshine-on-steamos-install.sh).
# The payload's local helpers map onto the framework message API so the call
# sites below stay unchanged; command output goes to the payload's log file.
# ------------------------------------------------------------------------------
MODE="${1:-install}"
LOG_DIR="/var/log/steamos-streaming"
LOG_FILE="${LOG_DIR}/install.log"
RELEASE_FILE="/etc/steamos-streaming-release"
LIB_DIR="/usr/local/lib/steamos-streaming"
CURRENT_PHASE="Starting container installer"

mkdir -p "$LOG_DIR" "$LIB_DIR"
rm -f "${LOG_DIR}/.install-ok"

cmsg() { msg_ok "$1"; echo "[$(date '+%F %T')] $1" >>"$LOG_FILE"; }
cwarn() { echo "[WARN] $1"; echo "[$(date '+%F %T')] [WARN] $1" >>"$LOG_FILE"; }
cerr() { msg_error "$1"; echo "[$(date '+%F %T')] [ERROR] $1" >>"$LOG_FILE"; }
run() { echo "[$(date '+%F %T')] [CMD] $*" >>"$LOG_FILE"; "$@" >>"$LOG_FILE" 2>&1; }

# The standalone host script pushes /etc/steamos-streaming-release into the
# container; under the community-scripts engine the same values arrive as
# exported var_* environment variables - generate the release file from them.
if [[ ! -f "$RELEASE_FILE" ]]; then
  _gpu_node=""
  for _n in /dev/dri/renderD*; do
    [[ -e "$_n" ]] && _gpu_node="$_n" && break
  done
  # Network intent: PVE writes the container network config to
  # /etc/systemd/network/eth0.network (Address/Gateway for static, DHCP=yes
  # otherwise). The payload switches the container to NetworkManager (Steam
  # Gaming Mode reads network state from NM over D-Bus) and rebuilds the
  # config from these release values - without them a static assignment
  # would silently degrade to a DHCP lease.
  _net_cfg="dhcp" _net_gw="" _net_dns=""
  if [[ -r /etc/systemd/network/eth0.network ]]; then
    _addr="$(sed -n 's/^Address *= *//p' /etc/systemd/network/eth0.network | head -n1)"
    if [[ -n "$_addr" ]]; then
      _net_cfg="$_addr"
      _net_gw="$(sed -n 's/^Gateway *= *//p' /etc/systemd/network/eth0.network | head -n1)"
      _net_dns="$(sed -n 's/^DNS *= *//p' /etc/systemd/network/eth0.network | head -n1)"
    fi
  fi
  cat >"$RELEASE_FILE" <<RELEASE_EOF
INSTALLER_VERSION="1.0.0-proxmoxved"
INSTALL_DATE="$(date +%Y-%m-%d)"
# Sunshine is deliberately PINNED (not fetch_and_deploy_gh_release "latest"):
# every release after v2026.516 currently ships a wlroots capture that fails
# against sway at stream time (black screen). The pin is functional, with a
# verifying checksum; bump both together once upstream capture is fixed.
SUNSHINE_VERSION="2026.516.143833"
SUNSHINE_URL="https://github.com/LizardByte/Sunshine/releases/download/v2026.516.143833/sunshine.AppImage"
SUNSHINE_SHA256="d0ee0a9cfb66f27869b559455f84622d21615047ccf3443c9a2f572ca971c7a2"
RELEASE_CHANNEL="stable"
GPU_RENDER_NODE="${_gpu_node}"
NET_CONFIG="${_net_cfg}"
NET_GATEWAY="${_net_gw}"
NET_DNS="${_net_dns}"
STREAM_WIDTH="${var_stream_width:-1920}"
STREAM_HEIGHT="${var_stream_height:-1080}"
STREAM_FPS="${var_stream_fps:-60}"
KEYBOARD_LAYOUT="${var_keyboard:-us}"
INSTALL_DESKTOP="${var_desktop_mode:-yes}"
INSTALL_DECKY="${var_decky:-no}"
INSTALL_HEROIC="${var_heroic:-no}"
SUNSHINE_PACKETSIZE="${var_packetsize:-}"
DISPLAY_SERVER="${var_display_server:-wayland}"
MULTI_GPU="no"
ENABLE_SSH="no"
GAMES_MOUNT_ENABLED="no"
RELEASE_EOF
fi
# shellcheck disable=SC1090
source "$RELEASE_FILE"
STREAM_WIDTH="${STREAM_WIDTH:-1920}"
STREAM_HEIGHT="${STREAM_HEIGHT:-1080}"
STREAM_FPS="${STREAM_FPS:-60}"
GPU_RENDER_NODE="${GPU_RENDER_NODE:-/dev/dri/renderD128}"
SUNSHINE_VERSION="${SUNSHINE_VERSION:?SUNSHINE_VERSION missing from release file}"
SUNSHINE_URL="${SUNSHINE_URL:?SUNSHINE_URL missing from release file}"
SUNSHINE_SHA256="${SUNSHINE_SHA256:?SUNSHINE_SHA256 missing from release file}"
HOST_INPUT_GID="${HOST_INPUT_GID:-}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-us}"
ENABLE_SSH="${ENABLE_SSH:-no}"
INSTALL_DESKTOP="${INSTALL_DESKTOP:-yes}"
INSTALL_DECKY="${INSTALL_DECKY:-no}"
INSTALL_HEROIC="${INSTALL_HEROIC:-no}"
SUNSHINE_PACKETSIZE="${SUNSHINE_PACKETSIZE:-}"
DISPLAY_SERVER="${DISPLAY_SERVER:-wayland}"

REQUIRED_PACKAGES=(
  steam gamescope
  mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
  libva-mesa-driver lib32-libva-mesa-driver
  vulkan-tools libva-utils
  xorg-server xf86-video-dummy xf86-input-libinput
  xorg-xrandr xorg-xauth xorg-xinit xorg-xdpyinfo xorg-xset xorg-xwd xorg-setxkbmap
  sway grim xdg-desktop-portal xdg-desktop-portal-wlr
  pipewire pipewire-pulse wireplumber lib32-pipewire
  networkmanager
  dbus seatd gamemode lib32-gamemode mangohud lib32-mangohud
  libinput libei
  # jq/git/sudo are NOT pre-installed on the Arch template (unlike Debian);
  # sudo is used to run the deck user session, not for privilege escalation.
  jq git sudo unzip zstd which procps-ng iproute2 inetutils
  noto-fonts ttf-liberation
)
if [[ "$INSTALL_DESKTOP" == "yes" ]]; then
  # Desktop Mode: KDE Plasma X11 session inside a rootful Xwayland window
  # (Steam Deck's desktop). plasma-x11-session pulls kwin-x11 and startplasma.
  REQUIRED_PACKAGES+=(
    plasma-desktop plasma-x11-session plasma-pa
    konsole dolphin firefox
  )
fi

# ------------------------------------------------------------------------------
init_pacman() {
  CURRENT_PHASE="Initializing pacman"
  cmsg "Initializing pacman keyring and multilib"
  # pacman >= 7 sandboxes downloads with Landlock and a dedicated 'alpm' user;
  # neither works inside an LXC container. Disable the download sandbox or
  # every database/package download fails.
  if ! grep -q '^DisableSandbox' /etc/pacman.conf; then
    sed -i 's/^#\s*DisableSandbox.*/DisableSandbox/' /etc/pacman.conf
    grep -q '^DisableSandbox' /etc/pacman.conf ||
      sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
  fi
  sed -i 's/^DownloadUser/#DownloadUser/' /etc/pacman.conf
  if [[ ! -d /etc/pacman.d/gnupg ]]; then
    run pacman-key --init
    run pacman-key --populate archlinux
  fi
  if ! grep -q '^Server' /etc/pacman.d/mirrorlist 2>/dev/null; then
    # shellcheck disable=SC2016  # $repo/$arch are pacman placeholders, not shell vars
    echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' >>/etc/pacman.d/mirrorlist
  fi
  if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
  fi
  run pacman -Sy --noconfirm archlinux-keyring
  if ! grep -q '^en_US.UTF-8' /etc/locale.gen 2>/dev/null; then
    echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
  fi
  run locale-gen
  echo 'LANG=en_US.UTF-8' >/etc/locale.conf
  cmsg "pacman ready (multilib enabled)"
}

system_update() {
  CURRENT_PHASE="Updating Arch Linux base system"
  cmsg "Updating base system (pacman -Su), this can take a while"
  run pacman -Su --noconfirm
  cmsg "Base system updated"
}

install_packages() {
  CURRENT_PHASE="Installing Steam, Gamescope, Mesa, PipeWire and tools"
  cmsg "Installing gaming and streaming packages (large download)"
  run pacman -S --noconfirm --needed "${REQUIRED_PACKAGES[@]}"
  cmsg "Packages installed"
}

verify_packages() {
  CURRENT_PHASE="Verifying installed packages"
  local missing=() pkg
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    cmsg "Reinstalling missing packages: ${missing[*]}"
    # Full sync first: installing new packages against a stale database would
    # be an Arch partial upgrade and can break the container.
    run pacman -Syu --noconfirm
    run pacman -S --noconfirm --needed "${missing[@]}"
  fi
}

create_user() {
  CURRENT_PHASE="Creating deck user"
  if ! id deck >/dev/null 2>&1; then
    cmsg "Creating user deck (uid 1000)"
    run useradd -m -u 1000 -s /bin/bash deck
  fi
  run usermod -aG wheel,video,render,input,audio deck
  # Match the host 'input' group GID so bind-mounted /dev/input nodes stay
  # readable by deck (privileged CT = identical numeric IDs).
  if [[ -n "$HOST_INPUT_GID" ]] && ! getent group "$HOST_INPUT_GID" >/dev/null 2>&1; then
    run groupadd -g "$HOST_INPUT_GID" hostinput
  fi
  if [[ -n "$HOST_INPUT_GID" ]]; then
    local gid_name
    gid_name="$(getent group "$HOST_INPUT_GID" | cut -d: -f1 || true)"
    [[ -n "$gid_name" ]] && run usermod -aG "$gid_name" deck
  fi
  # Passwordless sudo: documented appliance convenience and hardening target.
  echo 'deck ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/deck
  chmod 0440 /etc/sudoers.d/deck
  mkdir -p /home/deck
  chown deck:deck /home/deck
  if [[ -d /games ]]; then
    chown deck:deck /games || true
  fi
  cmsg "User deck configured (wheel,video,render,input,audio)"
}

enable_linger() {
  CURRENT_PHASE="Enabling user session lingering"
  if ! loginctl enable-linger deck >>"$LOG_FILE" 2>&1; then
    mkdir -p /var/lib/systemd/linger
    touch /var/lib/systemd/linger/deck
  fi
  # PipeWire runs in the deck user manager; enable it for all users globally so
  # it starts with the lingering user session at boot.
  run systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
  cmsg "Lingering enabled for deck; PipeWire user services enabled"
}

write_display_helpers() {
  CURRENT_PHASE="Installing display helpers"
  cat >"${LIB_DIR}/ensure-tty" <<'ENSURE_TTY_EOF'
#!/usr/bin/env bash
# Xorg needs a virtual terminal device even with the dummy driver.
set -euo pipefail
[[ -e /dev/tty0 ]] || mknod -m 620 /dev/tty0 c 4 0
[[ -e /dev/tty7 ]] || mknod -m 620 /dev/tty7 c 4 7
exit 0
ENSURE_TTY_EOF
  chmod 0755 "${LIB_DIR}/ensure-tty"

  cat >"${LIB_DIR}/wait-display" <<'WAIT_DISPLAY_EOF'
#!/usr/bin/env bash
# Bounded display-server readiness check (no fixed sleep as the only mechanism).
if [[ -e /var/lib/steamos-streaming/display-server-wayland ]]; then
  for _ in $(seq 1 30); do
    sock="$(ls -t /run/user/1000/sway-ipc.* 2>/dev/null | head -n1)"
    if [[ -S "${sock:-/nonexistent}" ]] &&
      swaymsg -s "$sock" -t get_outputs >/dev/null 2>&1; then
      exit 0
    fi
    sleep 1
  done
  echo "sway headless display did not become ready within 30 seconds" >&2
  exit 1
fi
for _ in $(seq 1 30); do
  DISPLAY=:0 xdpyinfo >/dev/null 2>&1 && exit 0
  sleep 1
done
echo "Xorg on :0 did not become ready within 30 seconds" >&2
exit 1
WAIT_DISPLAY_EOF
  chmod 0755 "${LIB_DIR}/wait-display"

  cat >"${LIB_DIR}/gen-sway-config" <<'GEN_SWAY_CONFIG_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - generate the headless sway config (phase-4 stack).
# Regenerated on every steamos-wayland start; reads the installed defaults
# and the set-display-mode override.
set -euo pipefail
# shellcheck disable=SC1091
source /etc/steamos-streaming-release
W="${STREAM_WIDTH:-1920}"
H="${STREAM_HEIGHT:-1080}"
F="${STREAM_FPS:-60}"
KB="${KEYBOARD_LAYOUT:-}"
# Fall back to the layout already configured for the Xorg stack.
if [[ -z "$KB" && -r /etc/X11/xorg.conf.d/00-keyboard.conf ]]; then
  KB="$(awk -F'"' '/XkbLayout/ {print $4; exit}' /etc/X11/xorg.conf.d/00-keyboard.conf)"
fi
KB="${KB:-us}"
MODE_FILE=/var/lib/steamos-streaming/display-mode
if [[ -r "$MODE_FILE" ]]; then
  _req="$(head -n1 "$MODE_FILE" | tr -d '[:space:]')"
  if [[ "$_req" =~ ^([0-9]{3,5})x([0-9]{3,5})(@([0-9]{2,3}))?$ ]]; then
    W="${BASH_REMATCH[1]}"
    H="${BASH_REMATCH[2]}"
    [[ -n "${BASH_REMATCH[4]:-}" ]] && F="${BASH_REMATCH[4]}"
  fi
fi
mkdir -p /var/lib/steamos-streaming
cat >/var/lib/steamos-streaming/sway.conf <<SWAY_CONF_EOF
# Generated by SteamOS Streaming LXC - do not edit (regenerated on start)
# Headless compositor hosting gamescope; Sunshine captures the output.
xwayland disable
default_border none
focus_follows_mouse yes
output HEADLESS-1 mode --custom ${W}x${H}@${F}Hz
output HEADLESS-1 render_bit_depth 8
input type:keyboard xkb_layout ${KB}
SWAY_CONF_EOF
chown deck:deck /var/lib/steamos-streaming/sway.conf
echo "sway config generated: ${W}x${H}@${F} layout ${KB}"
GEN_SWAY_CONFIG_EOF
  chmod 0755 "${LIB_DIR}/gen-sway-config"

  cat >"${LIB_DIR}/gen-display-env" <<'GEN_DISPLAY_ENV_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - write the display environment for streaming
# consumers (session wrapper, Sunshine). The wayland socket name is not
# fixed, so detect the live one; falls back to the Xorg display.
set -euo pipefail
ENVF=/run/user/1000/steamos-display.env
SUNSHINE_CONF=/home/deck/.config/sunshine/sunshine.conf

# Sunshine's capture backend is pinned in sunshine.conf; keep it aligned
# with the active display server (x11 <-> wlr).
set_capture() {
  [[ -w "$SUNSHINE_CONF" ]] || return 0
  if grep -q '^capture = ' "$SUNSHINE_CONF"; then
    sed -i "s/^capture = .*/capture = ${1}/" "$SUNSHINE_CONF"
  else
    printf 'capture = %s\n' "$1" >>"$SUNSHINE_CONF"
  fi
}

# The VA-API encode device follows the GPU selection (set-gpu): encoding on
# the GPU that renders keeps the capture path zero-copy.
set_adapter() {
  [[ -w "$SUNSHINE_CONF" ]] || return 0
  if grep -q '^adapter_name = ' "$SUNSHINE_CONF"; then
    sed -i "s|^adapter_name = .*|adapter_name = ${1}|" "$SUNSHINE_CONF"
  else
    printf 'adapter_name = %s\n' "$1" >>"$SUNSHINE_CONF"
  fi
}
GPU_ENVF=/run/steamos-streaming/gpu.env
if [[ -r "$GPU_ENVF" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$GPU_ENVF"
  [[ -n "${STEAMOS_RENDER_NODE:-}" ]] && set_adapter "$STEAMOS_RENDER_NODE"
fi

if [[ -e /var/lib/steamos-streaming/display-server-wayland ]]; then
  # wlr: zero-copy dmabuf capture of the sway (gles2) output - the proven
  # daily-driver path. The portal/vulkan alternate (capture=portal +
  # WLR_RENDERER=vulkan) survives GPU-saturating games but adds PipeWire
  # buffering latency and paces below the display rate; see README.
  set_capture wlr
  # Wait for the portals so Sunshine's capture probe finds a ScreenCast.
  for _ in $(seq 1 20); do
    systemctl --user is-active --quiet xdg-desktop-portal-wlr.service && break
    sleep 1
  done
  wl=""
  for _ in $(seq 1 30); do
    for s in /run/user/1000/wayland-*; do
      if [[ -S "$s" ]]; then
        wl="${s##*/}"
        break 2
      fi
    done
    sleep 1
  done
  if [[ -z "$wl" ]]; then
    echo "gen-display-env: no wayland socket appeared within 30 seconds" >&2
    exit 1
  fi
  # No DISPLAY on purpose: an X connection ties Sunshine's life to
  # gamescope's Xwayland, so stopping the session (desktop-mode switch)
  # kills Sunshine and drops the stream. The stable release runs trayless
  # without a display. The prerelease Qt tray aborts without one - when
  # running the prerelease, add QT_QPA_PLATFORM=xcb and DISPLAY=:0 back
  # here and accept that mode switches restart Sunshine.
  {
    printf 'WAYLAND_DISPLAY=%s\n' "$wl"
    printf 'DBUS_SESSION_BUS_ADDRESS=unix:path=%s/bus\n' "${XDG_RUNTIME_DIR:-/run/user/1000}"
    printf 'XDG_CURRENT_DESKTOP=sway\n'
    printf 'XDG_SESSION_TYPE=wayland\n'
  } >"$ENVF"
  exit 0
fi
set_capture x11
printf 'DISPLAY=:0\n' >"$ENVF"
GEN_DISPLAY_ENV_EOF
  chmod 0755 "${LIB_DIR}/gen-display-env"

  # GPU selection resolver. Installed unconditionally: on single-GPU installs
  # the stable symlinks are absent and the fallback picks the only render
  # node, which also repairs installs whose node name drifted from the
  # release-file default.
  cat >"${LIB_DIR}/gen-gpu-env" <<'GEN_GPU_ENV_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - resolve the GPU selection (set-gpu marker) into an
# env file consumed by the display server, the session and Sunshine.
#
# With the multi-GPU selector the host bind-mounts the whole /dev/dri,
# including udev-maintained stable symlinks (render-egpu/render-igpu) keyed
# to PCI device IDs, so the names survive node renumbering when a GPU is
# attached/detached/reset.
set -euo pipefail
MARKER=/var/lib/steamos-streaming/gpu
RUN_DIR=/run/steamos-streaming
ENVF="$RUN_DIR/gpu.env"

sel="auto"
[[ -r "$MARKER" ]] && sel="$(head -n1 "$MARKER" | tr -d '[:space:]')"

node_for() { # egpu|igpu -> resolved render node path, or empty when absent
  local link="/dev/dri/render-$1"
  { [[ -e "$link" ]] && readlink -f "$link"; } || true
}

egpu="$(node_for egpu)"
igpu="$(node_for igpu)"

case "$sel" in
egpu) node="$egpu" ;;
igpu) node="$igpu" ;;
*)
  sel="auto"
  node="${egpu:-$igpu}"
  ;;
esac
if [[ -z "$node" ]]; then
  # Requested GPU absent (eGPU detached, or forced igpu with no symlink):
  # fall back to whatever exists rather than leaving the stack displayless.
  echo "gen-gpu-env: requested GPU '${sel}' not present, falling back" >&2
  node="${egpu:-$igpu}"
fi
if [[ -z "$node" ]]; then
  # No stable symlinks at all (single-GPU install): first render node.
  for n in /dev/dri/renderD*; do
    [[ -e "$n" ]] && node="$n" && break
  done
fi
[[ -n "${node:-}" ]] || {
  echo "gen-gpu-env: no render node found in /dev/dri" >&2
  exit 1
}

base="${node##*/}"
vid="$(cat "/sys/class/drm/${base}/device/vendor" 2>/dev/null || echo 0x0)"
did="$(cat "/sys/class/drm/${base}/device/device" 2>/dev/null || echo 0x0)"
vid="${vid#0x}"
did="${did#0x}"

mkdir -p "$RUN_DIR"
chown deck:deck "$RUN_DIR" 2>/dev/null || true
{
  printf 'STEAMOS_GPU=%s\n' "$sel"
  printf 'STEAMOS_RENDER_NODE=%s\n' "$node"
  # sway/wlroots: render on the chosen node (headless backend).
  printf 'WLR_RENDER_DRM_DEVICE=%s\n' "$node"
  # Mesa Vulkan device-select layer: gamescope, Steam and games follow the
  # chosen GPU; '!' forces it even when an app tries to pick another device.
  # Without it gamescope can enumerate GPU B while sway renders on GPU A -
  # vkGetPhysicalDeviceSurfaceCapabilitiesKHR then fails and the session
  # crash-loops into its start limit.
  printf 'MESA_VK_DEVICE_SELECT=%s:%s!\n' "$vid" "$did"
  # GL apps (steamwebhelper): keep them on the same GPU so their buffers can
  # be dmabuf-imported by the compositor without a cross-device copy.
  printf 'DRI_PRIME=%s:%s\n' "$vid" "$did"
} >"$ENVF"
chmod 0644 "$ENVF"
echo "gen-gpu-env: ${sel} -> ${node} (${vid}:${did})"
GEN_GPU_ENV_EOF
  chmod 0755 "${LIB_DIR}/gen-gpu-env"

  cat >"${LIB_DIR}/setup-portals" <<'SETUP_PORTALS_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - point the deck user's xdg-desktop-portal at the
# live sway instance and (re)start the portal services. Runs as deck from
# steamos-wayland ExecStartPost; the portals hold a wayland connection and
# must follow compositor restarts.
set -euo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
wl=""
for _ in $(seq 1 15); do
  for s in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [[ -S "$s" ]]; then
      wl="${s##*/}"
      break 2
    fi
  done
  sleep 1
done
[[ -n "$wl" ]] || { echo "setup-portals: no wayland socket" >&2; exit 1; }
systemctl --user set-environment \
  WAYLAND_DISPLAY="$wl" XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland
systemctl --user restart xdg-desktop-portal-wlr.service xdg-desktop-portal.service
for _ in $(seq 1 15); do
  if systemctl --user is-active --quiet xdg-desktop-portal.service &&
    systemctl --user is-active --quiet xdg-desktop-portal-wlr.service; then
    echo "setup-portals: portals active on ${wl}"
    exit 0
  fi
  sleep 1
done
echo "setup-portals: portals did not become active" >&2
exit 1
SETUP_PORTALS_EOF
  chmod 0755 "${LIB_DIR}/setup-portals"

  # wlroots never requests a GPU context priority; this shim injects a
  # high-priority EGL context into sway (gles2 renderer) so compositing
  # degrades less while a game saturates the GPU. Compiled only when a
  # compiler is present; a missing .so makes LD_PRELOAD a harmless no-op.
  cat >"${LIB_DIR}/egl-highprio.c" <<'EGL_SHIM_EOF'
/* Inject EGL_CONTEXT_PRIORITY_HIGH_IMG into eglCreateContext for hosts
 * (sway/wlroots) that never request GPU priority themselves. Requires the
 * process to hold CAP_SYS_NICE or the driver silently falls back. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
typedef void *EGLDisplay; typedef void *EGLConfig; typedef void *EGLContext;
typedef int32_t EGLint;
#define EGL_NONE 0x3038
#define EGL_CONTEXT_PRIORITY_LEVEL_IMG 0x3100
#define EGL_CONTEXT_PRIORITY_HIGH_IMG 0x3101
typedef EGLContext (*create_fn)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig cfg, EGLContext share,
                            const EGLint *attribs) {
  static create_fn real;
  if (!real) real = (create_fn)dlsym(RTLD_NEXT, "eglCreateContext");
  EGLint buf[64];
  int i = 0, has_prio = 0;
  if (attribs) {
    while (attribs[i] != EGL_NONE && i < 58) {
      if (attribs[i] == EGL_CONTEXT_PRIORITY_LEVEL_IMG) has_prio = 1;
      buf[i] = attribs[i]; buf[i + 1] = attribs[i + 1];
      i += 2;
    }
  }
  if (!has_prio) {
    buf[i++] = EGL_CONTEXT_PRIORITY_LEVEL_IMG;
    buf[i++] = EGL_CONTEXT_PRIORITY_HIGH_IMG;
  }
  buf[i] = EGL_NONE;
  return real(dpy, cfg, share, buf);
}
EGL_SHIM_EOF
  if command -v gcc >/dev/null 2>&1; then
    gcc -shared -fPIC -O2 -o "${LIB_DIR}/egl-highprio.so" "${LIB_DIR}/egl-highprio.c" -ldl || true
  fi

  # Headless screencast portal for the optional portal/vulkan capture
  # path (and future Sunshine builds); inert unless capture=portal.
  mkdir -p /home/deck/.config/xdg-desktop-portal-wlr /home/deck/.config/xdg-desktop-portal
  cat >/home/deck/.config/xdg-desktop-portal-wlr/config <<'XDPW_EOF'
[screencast]
chooser_type = none
output_name = HEADLESS-1
max_fps = 0
XDPW_EOF
  cat >/home/deck/.config/xdg-desktop-portal/portals.conf <<'PORTALS_EOF'
[preferred]
default=wlr
org.freedesktop.impl.portal.ScreenCast=wlr
PORTALS_EOF
  chown -R deck:deck /home/deck/.config/xdg-desktop-portal-wlr /home/deck/.config/xdg-desktop-portal

  # Host-side gids on the bind-mounted /dev/input do not map to container
  # groups (observed as group 'utmp' after CT restarts), leaving the
  # compositor unable to read Sunshine's virtual devices (dead mouse).
  cat >/etc/udev/rules.d/99-steamos-input-group.rules <<'INPUT_RULE_EOF'
KERNEL=="event*", SUBSYSTEM=="input", GROUP="input", MODE="0660"
INPUT_RULE_EOF

  cat >"${LIB_DIR}/wait-audio" <<'WAIT_AUDIO_EOF'
#!/usr/bin/env bash
# Wait for the deck user PipeWire instance and the GameStream sink.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
for _ in $(seq 1 60); do
  if pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -qx "GameStream"; then
    pactl set-default-sink GameStream >/dev/null 2>&1 || true
    exit 0
  fi
  sleep 1
done
echo "PipeWire GameStream sink did not appear within 60 seconds" >&2
exit 1
WAIT_AUDIO_EOF
  chmod 0755 "${LIB_DIR}/wait-audio"

  # gen-xorg regenerates the dummy-display Xorg configuration from a selected
  # resolution/refresh and records it in the release file. Used by the
  # installer, repair mode and steamos-streaming-config.
  cat >"${LIB_DIR}/gen-xorg" <<'GEN_XORG_EOF'
#!/usr/bin/env bash
set -euo pipefail
W="${1:?usage: gen-xorg WIDTH HEIGHT FPS}"
H="${2:?usage: gen-xorg WIDTH HEIGHT FPS}"
FPS="${3:?usage: gen-xorg WIDTH HEIGHT FPS}"
MODE="${W}x${H}"
case "${MODE}@${FPS}" in
1920x1080@60) MODELINE='Modeline "1920x1080" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync' ;;
2560x1440@60) MODELINE='Modeline "2560x1440" 312.25 2560 2752 3024 3488 1440 1443 1448 1493 -hsync +vsync' ;;
3840x2160@60) MODELINE='Modeline "3840x2160" 712.75 3840 4160 4576 5312 2160 2163 2168 2237 -hsync +vsync' ;;
*)
  if command -v cvt >/dev/null 2>&1; then
    # Prefer reduced blanking: the dummy driver caps the pixel clock at
    # ~300 MHz and standard CVT timings exceed it at high refresh rates
    # (blanking intervals are meaningless on a virtual display anyway).
    MODELINE="$(cvt -r "$W" "$H" "$FPS" 2>/dev/null | grep -E '^Modeline' | sed "s/\"[^\"]*\"/\"${MODE}\"/")"
    [[ -n "$MODELINE" ]] || MODELINE="$(cvt "$W" "$H" "$FPS" | grep -E '^Modeline' | sed "s/\"[^\"]*\"/\"${MODE}\"/")"
  else
    echo "cvt not available and no built-in modeline for ${MODE}@${FPS}" >&2
    exit 1
  fi
  ;;
esac
mkdir -p /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/20-steamos-virtual-display.conf <<XORG_CONF_EOF
# Generated by SteamOS Streaming LXC - do not edit (regenerated on repair)
Section "ServerLayout"
    Identifier "SteamOSLayout"
    Screen 0 "DummyScreen"
    Option "AutoAddDevices" "true"
    Option "AutoAddGPU" "false"
EndSection

Section "ServerFlags"
    Option "DontVTSwitch" "true"
    Option "AllowMouseOpenFail" "true"
    Option "AutoEnableDevices" "true"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection

Section "Device"
    Identifier "DummyDevice"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Monitor"
    Identifier "DummyMonitor"
    HorizSync 5.0 - 1000.0
    VertRefresh 5.0 - 200.0
    # Accept reduced-blanking modes (needed to stay under the dummy driver's
    # 300 MHz pixel clock at high refresh rates).
    Option "ReducedBlanking" "true"
    ${MODELINE}
    Option "PreferredMode" "${MODE}"
EndSection

Section "Screen"
    Identifier "DummyScreen"
    Device "DummyDevice"
    Monitor "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "${MODE}"
        Virtual ${W} ${H}
    EndSubSection
EndSection
XORG_CONF_EOF
sed -i "s/^STREAM_WIDTH=.*/STREAM_WIDTH=${W}/" /etc/steamos-streaming-release
sed -i "s/^STREAM_HEIGHT=.*/STREAM_HEIGHT=${H}/" /etc/steamos-streaming-release
sed -i "s/^STREAM_FPS=.*/STREAM_FPS=${FPS}/" /etc/steamos-streaming-release
echo "Xorg virtual display configured: ${MODE} @ ${FPS} Hz"
GEN_XORG_EOF
  chmod 0755 "${LIB_DIR}/gen-xorg"
  "${LIB_DIR}/gen-xorg" "$STREAM_WIDTH" "$STREAM_HEIGHT" "$STREAM_FPS" >>"$LOG_FILE"
  # Streamed keyboards send raw key positions; map them through the user's
  # layout (Moonlight/Sunshine have no layout translation of their own).
  cat >/etc/X11/xorg.conf.d/00-keyboard.conf <<KEYBOARD_CONF_EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${KEYBOARD_LAYOUT:-us}"
EndSection
KEYBOARD_CONF_EOF
  cmsg "Xorg dummy display configured (${STREAM_WIDTH}x${STREAM_HEIGHT} @ ${STREAM_FPS} Hz, kb: ${KEYBOARD_LAYOUT:-us})"
}

write_pipewire_sink() {
  CURRENT_PHASE="Configuring PipeWire GameStream sink"
  mkdir -p /etc/pipewire/pipewire.conf.d
  cat >/etc/pipewire/pipewire.conf.d/10-steamos-gamestream.conf <<'PW_SINK_EOF'
# Generated by SteamOS Streaming LXC - virtual stereo sink for Sunshine capture.
# Recreated automatically on every PipeWire start (survives reboots).
context.objects = [
    { factory = adapter
        args = {
            factory.name            = support.null-audio-sink
            node.name               = "GameStream"
            node.description        = "SteamOS Streaming Audio"
            media.class             = Audio/Sink
            audio.position          = [ FL FR ]
            monitor.channel-volumes = true
            monitor.passthrough     = true
        }
    }
]
PW_SINK_EOF
  cmsg "PipeWire GameStream sink configured"
}

write_gaming_mode_wrapper() {
  CURRENT_PHASE="Installing Steam Gaming Mode wrapper"
  cat >/usr/local/bin/steamos-gaming-mode <<'GAMING_MODE_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - Steam Gaming Mode session wrapper.
# Kept in a readable wrapper instead of being embedded in the systemd unit.
set -euo pipefail
# shellcheck disable=SC1090,SC1091
source /etc/steamos-streaming-release

export XDG_RUNTIME_DIR=/run/user/1000
export STEAM_GAMESCOPE_SESSION=1
export STEAM_USE_MANGOAPP=1
export PULSE_SERVER=unix:/run/user/1000/pulse/native
export HOME="${HOME:-/home/deck}"

# Gamescope builds the XKB keymap for its clients (Steam, games on its
# nested Xwayland) from the XKB_DEFAULT_* environment, NOT from the host
# compositor's layout - without this it defaults to 'us' even though sway
# and the Xorg stack are configured for the installed layout.
_kb="${KEYBOARD_LAYOUT:-}"
if [[ -z "$_kb" && -r /etc/X11/xorg.conf.d/00-keyboard.conf ]]; then
  _kb="$(awk -F'"' '/XkbLayout/ {print $4; exit}' /etc/X11/xorg.conf.d/00-keyboard.conf)"
fi
export XKB_DEFAULT_LAYOUT="${_kb:-us}"

# Expose the shared game library inside Proton's pressure-vessel sandbox.
# Without this, anything running under Proton (NSL launchers: Epic, GOG,
# ...) cannot see /games at all - the sandbox only shares Steam libraries
# and STEAM_COMPAT_MOUNTS paths, so the launchers' install-location pickers
# show no such drive.
if [[ -d /games ]]; then
  export STEAM_COMPAT_MOUNTS="${STEAM_COMPAT_MOUNTS:+${STEAM_COMPAT_MOUNTS}:}/games"
fi

STREAM_WIDTH="${STREAM_WIDTH:-1920}"
STREAM_HEIGHT="${STREAM_HEIGHT:-1080}"
STREAM_FPS="${STREAM_FPS:-60}"

# A runtime mode set with set-display-mode overrides the installed default
# until "set-display-mode default" removes it.
MODE_FILE=/var/lib/steamos-streaming/display-mode
if [[ -r "$MODE_FILE" ]]; then
  _req="$(head -n1 "$MODE_FILE" | tr -d '[:space:]')"
  if [[ "$_req" =~ ^([0-9]{3,5})x([0-9]{3,5})(@([0-9]{2,3}))?$ ]]; then
    STREAM_WIDTH="${BASH_REMATCH[1]}"
    STREAM_HEIGHT="${BASH_REMATCH[2]}"
    [[ -n "${BASH_REMATCH[4]:-}" ]] && STREAM_FPS="${BASH_REMATCH[4]}"
    echo "steamos-gaming-mode: display-mode override: ${STREAM_WIDTH}x${STREAM_HEIGHT}@${STREAM_FPS}"
  else
    echo "steamos-gaming-mode: ignoring invalid ${MODE_FILE}: '${_req}'"
  fi
fi

MODE="${STREAM_WIDTH}x${STREAM_HEIGHT}"

# Cap D3D games (dxvk/vkd3d-proton) at the stream rate: uncapped menus and
# lightweight scenes otherwise present thousands of frames/second, flooding
# the iGPU's queues and starving compositing/capture (observed: AoM Retold
# menu -> 3 FPS stream). Frames above the stream rate are pure waste anyway.
export DXVK_FRAME_RATE="${STREAM_FPS}"
export VKD3D_FRAME_RATE="${STREAM_FPS}"

# The session service grants CAP_SYS_NICE (high-priority GPU queues for
# gamescope), but Steam's pressure-vessel/bwrap refuses to run with
# unexpected inherited capabilities - clear them for the Steam child only.
STEAM_CMD=(steam -gamepadui -steamos3 -steampal)
if command -v setpriv >/dev/null 2>&1; then
  STEAM_CMD=(setpriv --ambient-caps -all steam -gamepadui -steamos3 -steampal)
fi

if [[ -e /var/lib/steamos-streaming/display-server-wayland ]]; then
  # ---------- Phase-4 path: sway headless + gamescope wayland backend ------
  # gamescope presents real GPU dmabuf frames to the compositor (no
  # MESA_VK_WSI_DEBUG software copy) and Sunshine captures the compositor
  # output zero-copy; presents are paced by sway's frame clock.
  export XDG_SESSION_TYPE=wayland
  /usr/local/lib/steamos-streaming/gen-display-env
  # shellcheck disable=SC1091
  source /run/user/1000/steamos-display.env
  export WAYLAND_DISPLAY
  unset DISPLAY
  SWAYSOCK="$(ls -t /run/user/1000/sway-ipc.* 2>/dev/null | head -n1)"
  if [[ -S "${SWAYSOCK:-/nonexistent}" ]]; then
    # "--" stops swaymsg's own option parsing: getopt permutation otherwise
    # grabs "--custom" out of the command ("unrecognized option").
    swaymsg -s "$SWAYSOCK" -- output HEADLESS-1 mode --custom "${MODE}@${STREAM_FPS}Hz" >/dev/null ||
      echo "steamos-gaming-mode: could not set ${MODE}@${STREAM_FPS}Hz on HEADLESS-1"
  fi
  echo "steamos-gaming-mode: gamescope version: $(pacman -Q gamescope 2>/dev/null | awk '{print $2}' || echo 'unknown')"
  # gamescope's native wayland backend requires a primary DRM node (card0),
  # which the container does not have; the SDL backend on SDL's wayland video
  # driver reaches the same zero-copy present path (vulkan wayland WSI ->
  # linux-dmabuf into sway) with only the render node.
  export SDL_VIDEODRIVER=wayland
  launch=(gamescope
    --backend sdl
    -W "${STREAM_WIDTH}" -H "${STREAM_HEIGHT}"
    -w "${STREAM_WIDTH}" -h "${STREAM_HEIGHT}"
    -r "${STREAM_FPS}"
    -f
    -e
    --
    "${STEAM_CMD[@]}")
  echo "steamos-gaming-mode: launching (wayland): ${launch[*]}"
  exec "${launch[@]}"
fi

# ------------------------- v1 path: Xorg dummy ---------------------------
export DISPLAY=:0
export XDG_SESSION_TYPE=x11
export SDL_VIDEODRIVER=x11

# The Xorg dummy driver has no DRI3, so Mesa cannot do direct Vulkan
# presentation to the X11 window. Force the software presentation path for
# gamescope's own output only: rendering and compositing stay on the GPU; the
# final frame is copied to the dummy framebuffer, which is exactly where
# Sunshine's X11 capture reads it. Steam and the games run WITHOUT this
# variable (env -u below) and keep zero-copy GPU presentation into gamescope.
export MESA_VK_WSI_DEBUG=sw

# Put the virtual display into the requested mode before gamescope starts.
# xorg.conf only carries the boot mode: the dummy driver validates config-file
# modelines against its 300 MHz pixel-clock cap at startup, but runtime RandR
# modes skip that check, so e.g. 3440x1440@120 (a 658 MHz modeline) works
# here. The refresh is nominal anyway - there is no scanout on a dummy
# display; gamescope paces itself from -r.
XMODE="${MODE}_${STREAM_FPS}"
if command -v xrandr >/dev/null 2>&1; then
  # END-block awk: an early "exit" would SIGPIPE xrandr/xdpyinfo under pipefail.
  OUTPUT="$(xrandr --query 2>/dev/null | awk '/ connected/ && !v {v=$1} END {print v}')"
  TIMINGS="$(cvt -r "$STREAM_WIDTH" "$STREAM_HEIGHT" "$STREAM_FPS" 2>/dev/null | sed -n 's/^Modeline "[^"]*"[[:space:]]*//p')"
  [[ -n "$TIMINGS" ]] || TIMINGS="$(cvt "$STREAM_WIDTH" "$STREAM_HEIGHT" "$STREAM_FPS" 2>/dev/null | sed -n 's/^Modeline "[^"]*"[[:space:]]*//p')"
  if [[ -n "$OUTPUT" && -n "$TIMINGS" ]]; then
    # shellcheck disable=SC2086
    xrandr --newmode "$XMODE" $TIMINGS 2>/dev/null || true
    xrandr --addmode "$OUTPUT" "$XMODE" 2>/dev/null || true
    if xrandr --fb "$MODE" --output "$OUTPUT" --mode "$XMODE" 2>/dev/null ||
      xrandr --fb "$MODE" --output "$OUTPUT" --mode "$MODE" 2>/dev/null; then
      echo "steamos-gaming-mode: virtual display set to ${MODE} (mode ${XMODE})"
    else
      echo "steamos-gaming-mode: could not set ${MODE}; staying at $(xdpyinfo 2>/dev/null | awk '/dimensions:/ && !v {v=$2} END {print v}')"
    fi
  fi
fi

echo "steamos-gaming-mode: gamescope version: $(pacman -Q gamescope 2>/dev/null | awk '{print $2}' || echo 'unknown')"

launch=(gamescope
  --backend sdl
  --force-grab-cursor
  -W "${STREAM_WIDTH}" -H "${STREAM_HEIGHT}"
  -w "${STREAM_WIDTH}" -h "${STREAM_HEIGHT}"
  -r "${STREAM_FPS}"
  -f
  -e
  --
  env -u MESA_VK_WSI_DEBUG "${STEAM_CMD[@]}")

if command -v gamescope >/dev/null 2>&1 &&
  gamescope --help 2>&1 | grep -q -- '--backend'; then
  echo "steamos-gaming-mode: launching: ${launch[*]}"
  exec "${launch[@]}"
fi

# Compatibility fallback if Gamescope is missing or its flags changed.
echo "steamos-gaming-mode: gamescope unavailable or incompatible; falling back to: steam -gamepadui"
exec steam -gamepadui
GAMING_MODE_EOF
  chmod 0755 /usr/local/bin/steamos-gaming-mode
  # Manual display-mode switching for clients with different screens (e.g. an
  # ultrawide monitor next to a 16:9 Apple TV). Steam Remote Play/Sunshine
  # always stream the virtual display's current mode, so switching it is the
  # way to change the streamed resolution/aspect ratio.
  cat >/usr/local/bin/set-display-mode <<'SET_DISPLAY_MODE_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - switch the virtual display resolution/refresh rate.
#
# Applying a mode RESTARTS Steam Gaming Mode (a running game will be closed).
# Runtime RandR modes bypass the dummy driver's 300 MHz pixel-clock limit,
# so modes impossible in xorg.conf (e.g. 3440x1440@120) work here.
#
# usage: set-display-mode              show current mode and usage
#        set-display-mode WxH[@FPS]    e.g. 3440x1440@120 (FPS defaults to
#                                      the installed STREAM_FPS)
#        set-display-mode default      return to the installed default
set -euo pipefail
# shellcheck disable=SC1090,SC1091
source /etc/steamos-streaming-release 2>/dev/null || true
MODE_FILE=/var/lib/steamos-streaming/display-mode
DEFAULT_MODE="${STREAM_WIDTH:-1920}x${STREAM_HEIGHT:-1080}@${STREAM_FPS:-60}"

# The END-block form avoids awk exiting early, which would SIGPIPE xdpyinfo
# and turn a successful read into a pipefail failure.
current() {
  if [[ -e /var/lib/steamos-streaming/display-server-wayland ]]; then
    local sock
    sock="$(ls -t /run/user/1000/sway-ipc.* 2>/dev/null | head -n1)"
    [[ -S "${sock:-/nonexistent}" ]] || return 0
    swaymsg -s "$sock" -t get_outputs 2>/dev/null |
      jq -r '.[0].current_mode | "\(.width)x\(.height)"' 2>/dev/null
    return 0
  fi
  DISPLAY=:0 xdpyinfo 2>/dev/null | awk '/dimensions:/ && !v {v=$2} END {print v}'
}

if [[ $# -eq 0 ]]; then
  res="$(current)"
  echo "current X resolution : ${res:-display not running}"
  echo "installed default    : ${DEFAULT_MODE}"
  if [[ -r "$MODE_FILE" ]]; then
    echo "session override     : $(head -n1 "$MODE_FILE") (${MODE_FILE})"
  else
    echo "session override     : none"
  fi
  echo
  echo "usage: set-display-mode WxH[@FPS] | default"
  echo "examples: set-display-mode 3440x1440@120"
  echo "          set-display-mode 1920x1080@120"
  echo "          set-display-mode default"
  exit 0
fi

req="$1"
case "$req" in
default | reset)
  rm -f "$MODE_FILE"
  echo "Session override removed; returning to the default ${DEFAULT_MODE}."
  ;;
*)
  if [[ ! "$req" =~ ^([0-9]{3,5})x([0-9]{3,5})(@([0-9]{2,3}))?$ ]]; then
    echo "invalid mode '${req}' (expected WxH or WxH@FPS, e.g. 3440x1440@120)" >&2
    exit 2
  fi
  [[ -n "${BASH_REMATCH[4]:-}" ]] || req="${req}@${STREAM_FPS:-60}"
  mkdir -p "$(dirname "$MODE_FILE")"
  printf '%s\n' "$req" >"$MODE_FILE"
  echo "Requested mode: ${req}"
  ;;
esac

echo "Restarting Steam Gaming Mode to apply (a running game is closed) ..."
if [[ -e /var/lib/steamos-streaming/display-server-wayland ]]; then
  # Headless sway outputs ignore runtime custom-mode changes; the mode is
  # baked into the generated config at compositor start. Session and
  # Sunshine follow via PartOf.
  systemctl restart steamos-wayland.service
else
  systemctl restart steamos-session.service
fi
for _ in $(seq 1 30); do
  sleep 1
  pgrep -u deck '^gamescope' >/dev/null 2>&1 && break
done
sleep 2
res="$(current)"
echo "Steam session restarted; X resolution is now: ${res:-unknown}"
SET_DISPLAY_MODE_EOF
  chmod 0755 /usr/local/bin/set-display-mode
  # Reachable under lxc-attach's minimal PATH ("pct exec CTID -- set-display-mode").
  ln -sf /usr/local/bin/set-display-mode /usr/bin/set-display-mode

  # Phase-4 toggle between the Xorg dummy stack and the wayland/sway stack.
  cat >/usr/local/bin/set-display-server <<'SET_DISPLAY_SERVER_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - toggle between the Xorg dummy stack (v1) and the
# headless Wayland/sway stack (phase 4, GPU zero-copy capture).
#
# Switching RESTARTS the streaming stack (a running game will be closed).
set -euo pipefail
MARKER=/var/lib/steamos-streaming/display-server-wayland
cur() { if [[ -e "$MARKER" ]]; then echo wayland; else echo xorg; fi; }

case "${1:-status}" in
wayland)
  mkdir -p "$(dirname "$MARKER")"
  touch "$MARKER"
  ;;
xorg)
  rm -f "$MARKER"
  ;;
status)
  echo "display server: $(cur)"
  exit 0
  ;;
*)
  echo "usage: set-display-server [wayland|xorg|status]" >&2
  exit 2
  ;;
esac

echo "Switching display server to: ${1} (restarting streaming stack ...)"
systemctl daemon-reload
systemctl restart steamos-xorg.service steamos-wayland.service 2>/dev/null || true
systemctl restart steamos-session.service sunshine.service
sleep 3
systemctl --no-pager --plain --all list-units "steamos-xorg.service" "steamos-wayland.service" "steamos-session.service" "sunshine.service" | sed -n '1,6p'
echo "display server now: $(cur)"
SET_DISPLAY_SERVER_EOF
  chmod 0755 /usr/local/bin/set-display-server
  ln -sf /usr/local/bin/set-display-server /usr/bin/set-display-server

  # Multi-GPU selector (also installed on single-GPU systems, where only
  # status/auto are useful - the stable role symlinks do not exist there).
  cat >/usr/local/bin/set-gpu <<'SET_GPU_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - select which GPU runs the streaming stack.
#   egpu / igpu : pin to the external(discrete) / integrated GPU
#   auto        : prefer the eGPU when attached, else the iGPU (default)
#
# Switching RESTARTS the streaming stack (a running game will be closed).
set -euo pipefail
MARKER=/var/lib/steamos-streaming/gpu
ENVF=/run/steamos-streaming/gpu.env

have() { if [[ -e "/dev/dri/render-$1" ]]; then echo yes; else echo no; fi; }
cur() { if [[ -r "$MARKER" ]]; then head -n1 "$MARKER"; else echo auto; fi; }

case "${1:-status}" in
egpu | igpu)
  if [[ ! -e "/dev/dri/render-$1" ]]; then
    echo "set-gpu: /dev/dri/render-$1 not present" >&2
    [[ "$1" == egpu ]] && echo "hint: is the eGPU attached (and the host udev rule installed)?" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$MARKER")"
  printf '%s\n' "$1" >"$MARKER"
  ;;
auto)
  rm -f "$MARKER"
  ;;
status)
  echo "selection: $(cur)   (auto prefers the eGPU when present)"
  echo "present  : egpu=$(have egpu) igpu=$(have igpu)"
  if [[ -r "$ENVF" ]]; then
    sed 's/^/active   : /' "$ENVF"
  else
    echo "active   : (stack not started since boot)"
  fi
  exit 0
  ;;
*)
  echo "usage: set-gpu [egpu|igpu|auto|status]" >&2
  exit 2
  ;;
esac

echo "GPU selection: $(cur) (restarting streaming stack ...)"
systemctl restart steamos-xorg.service steamos-wayland.service 2>/dev/null || true
systemctl restart steamos-session.service sunshine.service
sleep 3
if [[ -r "$ENVF" ]]; then
  sed 's/^/active: /' "$ENVF"
fi
SET_GPU_EOF
  chmod 0755 /usr/local/bin/set-gpu
  ln -sf /usr/local/bin/set-gpu /usr/bin/set-gpu

  # Sunshine app-grid entry: switch the display to the connecting
  # client's requested mode (ask-or-keep UX from the Moonlight UI).
  cat >/usr/local/bin/match-display-mode <<'MATCH_DISPLAY_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - Sunshine app hook: switch the virtual display to
# the connecting client's requested mode (SUNSHINE_CLIENT_* environment).
# If the display already matches, this is a no-op and the client returns to
# the Moonlight app grid immediately. Switching restarts the streaming
# stack, so the client is disconnected and reconnects to the new mode.
set -euo pipefail
W="${SUNSHINE_CLIENT_WIDTH:-}"
H="${SUNSHINE_CLIENT_HEIGHT:-}"
F="${SUNSHINE_CLIENT_FPS:-60}"
if ! [[ "$W" =~ ^[0-9]{3,5}$ && "$H" =~ ^[0-9]{3,5}$ && "$F" =~ ^[0-9]{2,3}$ ]]; then
  echo "match-display-mode: client did not provide a mode; keeping current"
  exit 0
fi
req="${W}x${H}@${F}"
SOCK="$(ls -t /run/user/1000/sway-ipc.* 2>/dev/null | head -n1)"
cur=""
if [[ -S "${SOCK:-/nonexistent}" ]]; then
  cur="$(swaymsg -s "$SOCK" -t get_outputs 2>/dev/null |
    jq -r '.[0].current_mode | "\(.width)x\(.height)@\(.refresh/1000|floor)"' 2>/dev/null || true)"
fi
if [[ "$cur" == "$req" ]]; then
  echo "match-display-mode: display already at ${req}; nothing to do"
  exit 0
fi
echo "match-display-mode: switching ${cur:-unknown} -> ${req}; stream will drop, reconnect afterwards"
# Detach into a system unit: the switch restarts Sunshine itself (PartOf),
# which would otherwise kill this very command mid-flight.
exec sudo /usr/bin/systemd-run --collect --unit="steamos-display-switch-$$" \
  /usr/local/bin/set-display-mode "$req"
MATCH_DISPLAY_EOF
  chmod 0755 /usr/local/bin/match-display-mode

  # Session dispatcher: one unit hosts Gaming Mode or Desktop Mode, so the
  # two can never run at once (a two-unit Conflicts= design is racy under
  # restart: both sessions ended up active in testing).
  cat >/usr/local/bin/steamos-session-launcher <<'SESSION_LAUNCHER_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - session dispatcher for steamos-session.service.
# One unit hosts either session, so Gaming Mode and Desktop Mode can never
# run at the same time (a two-unit Conflicts= design is racy under restart).
# steamos-session-select writes the marker; /run resets on reboot, so the
# container always boots into Gaming Mode (Steam Deck behavior).
if [[ -e /run/steamos-streaming/session-mode-desktop ]]; then
  # The unit grants ambient CAP_SYS_NICE for gamescope; Steam's bwrap
  # refuses to start with inherited ambient capabilities, so shed them for
  # the desktop branch (the gaming wrapper does the same around Steam).
  exec setpriv --ambient-caps -all /usr/local/bin/steamos-desktop-mode
fi
exec /usr/local/bin/steamos-gaming-mode
SESSION_LAUNCHER_EOF
  chmod 0755 /usr/local/bin/steamos-session-launcher

  cat >/usr/local/bin/steamos-desktop-mode <<'DESKTOP_MODE_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - Desktop Mode (KDE Plasma, Steam Deck style).
# Runs a rootful fullscreen Xwayland window on the headless sway compositor
# and starts a Plasma X11 session inside it. Sunshine's zero-copy wlr capture
# streams the compositor output, so switching sessions keeps the stream up.
#
# Invoked by steamos-session-launcher when the desktop marker is set.
# Exit protocol: if Plasma ends on its own (logout or crash) the marker is
# cleared, so the service's auto-restart lands back in Gaming Mode; a
# service stop/restart (SIGTERM) keeps the marker, so display-mode switches
# preserve the desktop session.
set -uo pipefail
MODE_MARKER=/run/steamos-streaming/session-mode-desktop
export XDG_RUNTIME_DIR=/run/user/1000
# Compositor connection details (WAYLAND_DISPLAY, session bus).
set -a
# shellcheck disable=SC1091
source /run/user/1000/steamos-display.env
set +a
# The env file targets Sunshine; the desktop session gets its own X server
# and identity.
export DISPLAY=:1
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
# Expose the shared game library inside Proton's pressure-vessel sandbox for
# Steam started from the desktop too (see the gaming-mode wrapper).
if [[ -d /games ]]; then
  export STEAM_COMPAT_MOUNTS="${STEAM_COMPAT_MOUNTS:+${STEAM_COMPAT_MOUNTS}:}/games"
fi

cleanup() {
  [[ -n "${SESSION_PID:-}" ]] && kill "$SESSION_PID" 2>/dev/null
  [[ -n "${XWL_PID:-}" ]] && kill "$XWL_PID" 2>/dev/null
  exit 0
}
TERMED=0
on_term() {
  TERMED=1
  [[ -n "${SESSION_PID:-}" ]] && kill -TERM "$SESSION_PID" 2>/dev/null
}
trap cleanup EXIT
trap on_term TERM INT

# Rootful Xwayland defaults to a 640x480 root that fullscreen would stretch;
# size it to the compositor's current mode instead.
SWAYSOCK="$(ls -t /run/user/1000/sway-ipc.* 2>/dev/null | head -n1)"
export SWAYSOCK
GEOM="$(swaymsg -t get_outputs 2>/dev/null |
  jq -r '.[0].current_mode | "\(.width)x\(.height)"' 2>/dev/null || true)"
[[ "$GEOM" =~ ^[0-9]+x[0-9]+$ ]] || GEOM=1920x1080

# Rootful fullscreen Xwayland: one wayland surface sized to HEADLESS-1; sway
# focuses it as the only window, so input flows to the desktop.
Xwayland "$DISPLAY" -fullscreen -geometry "$GEOM" -noreset &
XWL_PID=$!
for _ in $(seq 1 50); do
  [[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]] && break
  kill -0 "$XWL_PID" 2>/dev/null || { echo "Xwayland died" >&2; exit 1; }
  sleep 0.2
done
[[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]] || { echo "Xwayland socket never appeared" >&2; exit 1; }

# Plasma's systemd-boot mode would scatter the session across user-manager
# units, escaping this service's cgroup (breaks stop/restart cleanup).
mkdir -p "$HOME/.config"
cat >"$HOME/.config/startkderc" <<'EOF'
[General]
systemdBoot=false
EOF
# kwin's GLX compositing never presents through rootful Xwayland (black
# output); sway composites the display anyway, so run X11 uncomposited.
kwriteconfig6 --file "$HOME/.config/kwinrc" --group Compositing --key Enabled false || true
# Never lock the streamed desktop: the deck account has no password, so a
# lock screen (Plasma autolocks after idle by default) is a dead end that
# looks like a mystery password prompt in Moonlight.
kwriteconfig6 --file "$HOME/.config/kscreenlockerrc" --group Daemon --key Autolock false || true
kwriteconfig6 --file "$HOME/.config/kscreenlockerrc" --group Daemon --key LockOnResume false || true

# Make sure sway focuses the desktop window (input routing) even if focus
# was elsewhere when gamescope went away.
(
  sleep 3
  swaymsg '[title="^Xwayland"]' focus >/dev/null 2>&1 || true
) &

# The wayland socket was only for Xwayland and swaymsg: with it visible,
# Qt/KDE clients attach to sway directly (invisible surfaces, black X
# desktop) instead of the X server that Sunshine's capture actually shows.
unset WAYLAND_DISPLAY
export QT_QPA_PLATFORM=xcb

# Isolated session bus: everything Plasma spawns dies with this service.
dbus-run-session startplasma-x11 &
SESSION_PID=$!
RC=0
while :; do
  if wait "$SESSION_PID" 2>/dev/null; then
    RC=0
    break
  else
    RC=$?
    kill -0 "$SESSION_PID" 2>/dev/null || break
    # wait was interrupted by a trapped signal while the session lives on
  fi
done
if [[ "$TERMED" -eq 0 ]]; then
  # Plasma ended on its own (logout or crash): drop the marker so the
  # service auto-restart returns to Gaming Mode.
  rm -f "$MODE_MARKER"
fi
exit "$RC"
DESKTOP_MODE_EOF
  chmod 0755 /usr/local/bin/steamos-desktop-mode

  cat >/usr/local/bin/steamos-session-select <<'SESSION_SELECT_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - switch between Steam Gaming Mode and Desktop Mode
# (the Steam Deck's steamos-session-select, reimagined for this container).
# The stream survives the switch: Sunshine captures the compositor output,
# and both sessions render into the same headless display. One service
# hosts both sessions; a marker in /run picks the branch and resets on
# reboot, so the container always boots into Gaming Mode.
set -euo pipefail
MODE_MARKER=/run/steamos-streaming/session-mode-desktop
mode="${1:-status}"
# SteamOS session names: Steam's own "Power -> Switch to Desktop" menu entry
# executes "steamos-session-select plasma"; accept the whole native family.
case "$mode" in
plasma | plasma-x11-persistent | plasma-wayland-persistent) mode=desktop ;;
gamescope) mode=gaming ;;
esac
case "$mode" in gaming | desktop | status) ;; *)
  echo "usage: steamos-session-select gaming|desktop|status (or SteamOS names: gamescope|plasma)" >&2
  exit 2
  ;;
esac
if [[ "$mode" == desktop && ! -x /usr/bin/startplasma-x11 ]]; then
  echo "Desktop Mode is not installed (installer option INSTALL_DESKTOP=no)." >&2
  exit 1
fi
if [[ "$mode" != status && $(id -u) -ne 0 ]]; then
  exec sudo /usr/local/bin/steamos-session-select "$mode"
fi
current() { [[ -e "$MODE_MARKER" ]] && echo desktop || echo gaming; }
case "$mode" in
gaming | desktop)
  if [[ "$(current)" == "$mode" ]] && systemctl is-active --quiet steamos-session.service; then
    echo "Already in ${mode} mode; nothing to do."
    exit 0
  fi
  if [[ "$mode" == desktop ]]; then
    # deck-owned: the desktop wrapper (running as deck) clears the marker
    # on Plasma logout, which needs write access to the directory.
    install -d -m 0755 -o deck -g deck "$(dirname "$MODE_MARKER")"
    : >"$MODE_MARKER"
    chown deck:deck "$MODE_MARKER"
  else
    rm -f "$MODE_MARKER"
  fi
  echo "Switching to ${mode} mode ..."
  # --no-block: the restart stops the session this command may be running
  # inside of (desktop icon, Moonlight tile); enqueue the job and get out.
  systemctl restart --no-block steamos-session.service
  ;;
status)
  printf 'selected mode : %s\n' "$(current)"
  printf 'session       : %s\n' "$(systemctl is-active steamos-session.service 2>/dev/null || true)"
  ;;
esac
SESSION_SELECT_EOF
  chmod 0755 /usr/local/bin/steamos-session-select
  # Reachable under lxc-attach's minimal PATH ("pct exec CTID -- steamos-session-select").
  ln -sf /usr/local/bin/steamos-session-select /usr/bin/steamos-session-select

  if [[ "$INSTALL_DESKTOP" == "yes" ]]; then
    # Steam Deck desktop parity: "Return to Gaming Mode" and Steam icons.
    cat >/usr/share/applications/return-to-gaming-mode.desktop <<'RETURN_DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=Return to Gaming Mode
Comment=Close the desktop and return to Steam Gaming Mode
Exec=/usr/local/bin/steamos-session-select gaming
Icon=go-previous
Terminal=false
Categories=System;
RETURN_DESKTOP_EOF
    mkdir -p /home/deck/Desktop
    cp /usr/share/applications/return-to-gaming-mode.desktop /home/deck/Desktop/
    cp /usr/share/applications/steam.desktop /home/deck/Desktop/ 2>/dev/null || true
    chmod +x /home/deck/Desktop/*.desktop
    chown -R deck:deck /home/deck/Desktop
  fi
  # Steam Gaming Mode has no folder browser: a game-library mount at
  # /games/SteamLibrary must be registered in libraryfolders.vdf. Runs as deck
  # before each Steam start (Steam must not be running while the file is
  # edited) and is a no-op once registered or when /games is absent.
  cat >"${LIB_DIR}/register-library" <<'REGISTER_LIB_EOF'
#!/usr/bin/env bash
LIB=/games/SteamLibrary
VDF=/home/deck/.local/share/Steam/config/libraryfolders.vdf
LEGACY=/home/deck/.local/share/Steam/steamapps/libraryfolders.vdf
[[ -d "$LIB" && -f "$VDF" ]] || exit 0
if ! grep -q "\"${LIB}\"" "$VDF"; then
  idx="$(grep -c '"path"' "$VDF")"
  tmp="$(mktemp)"
  awk -v idx="$idx" -v lib="$LIB" '
    { lines[NR] = $0 }
    END {
      for (i = 1; i < NR; i++) print lines[i]
      printf "\t\"%s\"\n\t{\n\t\t\"path\"\t\t\"%s\"\n\t\t\"label\"\t\t\"\"\n\t\t\"contentid\"\t\t\"0\"\n\t\t\"totalsize\"\t\t\"0\"\n\t\t\"update_clean_bytes_tally\"\t\t\"0\"\n\t\t\"time_last_update_verified\"\t\t\"0\"\n\t\t\"apps\"\n\t\t{\n\t\t}\n\t}\n", idx, lib
      print lines[NR]
    }' "$VDF" >"$tmp" && cat "$tmp" >"$VDF" && rm -f "$tmp"
fi
# Steam reconciles against the legacy steamapps/libraryfolders.vdf: an entry
# present only in config/ is pruned at startup. Keep both in sync.
if [[ -d "$(dirname "$LEGACY")" ]] && ! grep -q "\"${LIB}\"" "$LEGACY" 2>/dev/null; then
  cp "$VDF" "$LEGACY"
fi
# Make the game-library mount the default install location ("Make Default" in
# the Storage UI writes LastInstallFolderIndex to the user's localconfig.vdf).
# Only set it when the user has never chosen a default themselves, and only on
# symlink-capable filesystems: Valve runtime/Proton tools are dependency
# -installed into the default library and their Linux depots need symlinks,
# which exFAT/NTFS cannot store (games can still be installed there manually).
if ! ln -s . "${LIB}/.symlinktest" 2>/dev/null; then
  exit 0
fi
rm -f "${LIB}/.symlinktest"
lib_index="$(awk '/"path"/ { i++ } /"path".*"\/games\/SteamLibrary"/ { print i - 1; exit }' "$VDF")"
if [[ -n "$lib_index" ]]; then
  for lc in /home/deck/.local/share/Steam/userdata/*/config/localconfig.vdf; do
    [[ -f "$lc" ]] || continue
    grep -q '"LastInstallFolderIndex"' "$lc" && continue
    sed -i "0,/^{\$/s//{\n\t\"LastInstallFolderIndex\"\t\t\"${lib_index}\"/" "$lc"
  done
fi
exit 0
REGISTER_LIB_EOF
  chmod 0755 "${LIB_DIR}/register-library"
  # Proton prefixes (compatdata) need symlinks and shadercache wants fast
  # native storage - neither works on exFAT/NTFS game disks. Keep game content
  # on the multiplatform filesystem and bind those two directories onto the
  # container's native root disk (no-op when /games or the library is absent).
  cat >"${LIB_DIR}/setup-game-library" <<'GAMELIB_HELPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
LIB=/games/SteamLibrary
SRC=/var/lib/steamos-streaming/gamelib
if [[ -d "$LIB" ]]; then
  mkdir -p "$SRC/compatdata" "$SRC/shadercache"
  chown -R deck:deck "$SRC"
  mkdir -p "$LIB/steamapps/compatdata" "$LIB/steamapps/shadercache" 2>/dev/null || true
  if [[ -d "$LIB/steamapps/compatdata" ]]; then
    mountpoint -q "$LIB/steamapps/compatdata" || mount --bind "$SRC/compatdata" "$LIB/steamapps/compatdata"
  fi
  if [[ -d "$LIB/steamapps/shadercache" ]]; then
    mountpoint -q "$LIB/steamapps/shadercache" || mount --bind "$SRC/shadercache" "$LIB/steamapps/shadercache"
  fi
fi
# Give named (NonSteamLaunchers-style) Wine prefixes a G: drive pointing at
# the game library, so launcher install-location pickers show it directly.
# The pressure-vessel side is handled by STEAM_COMPAT_MOUNTS in the session
# wrappers; numeric (Steam game) prefixes are left untouched.
COMPAT=/home/deck/.local/share/Steam/steamapps/compatdata
if [[ -d /games && -d "$COMPAT" ]]; then
  for pfx in "$COMPAT"/*/pfx/dosdevices; do
    [[ -d "$pfx" ]] || continue
    name="${pfx#"$COMPAT"/}"
    name="${name%%/*}"
    [[ "$name" =~ ^[0-9]+$ ]] && continue
    if [[ ! -e "$pfx/g:" ]]; then
      ln -s /games "$pfx/g:" 2>/dev/null || true
      chown -h deck:deck "$pfx/g:" 2>/dev/null || true
    fi
  done
fi
exit 0
GAMELIB_HELPER_EOF
  chmod 0755 "${LIB_DIR}/setup-game-library"
  # Gamescope's software-presentation path can wedge after long idle periods:
  # the session runs, the UI renders, but the X framebuffer stays fully black.
  # Restart the session when that state is detected twice in a row and no
  # client is streaming (a dark in-game scene can therefore never trigger it).
  cat >"${LIB_DIR}/blackscreen-watchdog" <<'WATCHDOG_EOF'
#!/usr/bin/env bash
set -uo pipefail
STATE=/run/steamos-blackscreen
if [[ -e /var/lib/steamos-streaming/display-server-wayland ]]; then
  # The sw-WSI wedge is Xorg-only, but a long-lived sway accumulates state
  # over many session/desktop switches and can wedge so a healthy
  # gamescope's window never maps (observed live: client connected,
  # swapchain created, no view in the tree, black output; session restarts
  # do not recover it). Detect: session active beyond startup grace but no
  # mapped view on the compositor - twice in a row -> restart the stack.
  systemctl is-active --quiet steamos-session.service || { rm -f "$STATE"; exit 0; }
  started="$(systemctl show steamos-session.service -p ActiveEnterTimestampMonotonic --value 2>/dev/null)"
  now="$(awk '{printf "%d", $1*1000000}' /proc/uptime)"
  if [[ -z "$started" || "$started" -le 0 || $((now - started)) -lt 90000000 ]]; then
    rm -f "$STATE"
    exit 0
  fi
  SOCK="$(ls -t /run/user/1000/sway-ipc.* 2>/dev/null | head -n1)"
  [[ -S "${SOCK:-/nonexistent}" ]] || { rm -f "$STATE"; exit 0; }
  views="$(sudo -u deck env XDG_RUNTIME_DIR=/run/user/1000 swaymsg -s "$SOCK" -t get_tree 2>/dev/null |
    jq '[.. | objects | select(.pid?)] | length' 2>/dev/null)"
  if [[ "${views:-1}" -eq 0 ]]; then
    if [[ -f "$STATE" ]]; then
      echo "blackscreen-watchdog: no mapped view on the compositor twice in a row; restarting wayland stack"
      rm -f "$STATE"
      systemctl restart steamos-wayland.service
    else
      touch "$STATE"
    fi
  else
    rm -f "$STATE"
  fi
  exit 0
fi
systemctl is-active --quiet steamos-session.service || { rm -f "$STATE"; exit 0; }
if ss -nu state established 2>/dev/null | grep -qE ':(47998|47999|48000)'; then
  rm -f "$STATE"
  exit 0
fi
nz="$(sudo -u deck env DISPLAY=:0 xwd -root -silent 2>/dev/null |
  od -An -v -tu1 -j 8192 -N 2000000 |
  awk '{ for (i = 1; i <= NF; i++) if ($i > 16 && $i < 240) c++ } END { print c + 0 }')"
if [[ "${nz:-1}" -eq 0 ]]; then
  if [[ -f "$STATE" ]]; then
    echo "blackscreen-watchdog: framebuffer black twice in a row; restarting session"
    rm -f "$STATE"
    systemctl restart steamos-session.service
  else
    touch "$STATE"
  fi
else
  rm -f "$STATE"
fi
exit 0
WATCHDOG_EOF
  chmod 0755 "${LIB_DIR}/blackscreen-watchdog"
  cmsg "Gaming Mode wrapper installed (/usr/local/bin/steamos-gaming-mode)"
}

install_sunshine() {
  CURRENT_PHASE="Installing Sunshine ${SUNSHINE_VERSION}"
  local dest="/opt/sunshine/${SUNSHINE_VERSION}"
  if [[ -x "${dest}/AppRun" ]]; then
    cmsg "Sunshine ${SUNSHINE_VERSION} already installed"
  else
    cmsg "Downloading Sunshine ${SUNSHINE_VERSION} AppImage"
    local tmpd
    tmpd="$(mktemp -d)"
    run curl -fsSL -o "${tmpd}/sunshine.AppImage" "$SUNSHINE_URL"
    local got_sha
    got_sha="$(sha256sum "${tmpd}/sunshine.AppImage" | awk '{print $1}')"
    if [[ "$got_sha" != "$SUNSHINE_SHA256" ]]; then
      cerr "Sunshine AppImage checksum mismatch (expected ${SUNSHINE_SHA256}, got ${got_sha})"
      rm -rf "$tmpd"
      exit 1
    fi
    chmod +x "${tmpd}/sunshine.AppImage"
    # Extract instead of running: no FUSE requirement inside the container.
    (cd "$tmpd" && run ./sunshine.AppImage --appimage-extract)
    mkdir -p /opt/sunshine
    rm -rf "$dest"
    mv "${tmpd}/squashfs-root" "$dest"
    rm -rf "$tmpd"
    cmsg "Sunshine ${SUNSHINE_VERSION} extracted to ${dest}"
  fi
  # The AppImage bundles a libva that is older than Arch's VA-API driver ABI
  # (the driver only exports __vaDriverInit for the libva it was built with),
  # so the bundled copy can never load the system radeonsi driver. Remove it
  # and let the loader fall back to the system libva.
  rm -f "$dest"/usr/lib/libva.so* "$dest"/usr/lib/libva-drm.so* "$dest"/usr/lib/libva-x11.so*
  ln -sfn "$dest" /opt/sunshine/current
  # A plain symlink breaks AppRun: it resolves its bundled hook scripts
  # relative to $0, which would point into /usr/local/bin. Use an exec
  # wrapper so $0 stays inside /opt/sunshine/current/.
  rm -f /usr/local/bin/sunshine
  cat >/usr/local/bin/sunshine <<'SUNSHINE_WRAPPER_EOF'
#!/usr/bin/env bash
exec /opt/sunshine/current/AppRun "$@"
SUNSHINE_WRAPPER_EOF
  chmod 0755 /usr/local/bin/sunshine
  cmsg "Sunshine installed (stable wrapper /usr/local/bin/sunshine)"
}

write_sunshine_config() {
  CURRENT_PHASE="Configuring Sunshine"
  local sdir="/home/deck/.config/sunshine"
  mkdir -p "$sdir"
  # sunshine.conf and apps.json are generated configuration; credentials and
  # pairing state live in sunshine_state.json and are never touched.
  cat >"${sdir}/sunshine.conf" <<SUNSHINE_CONF_EOF
# Generated by SteamOS Streaming LXC - regenerated on repair.
# Credentials/pairing live in sunshine_state.json and are preserved.
# capture is rewritten by gen-display-env to match the active display server
capture = x11
encoder = vaapi
adapter_name = ${GPU_RENDER_NODE}
# Sunshine redirects the default sink to its own routing sink during streams;
# capture THAT sink's monitor or Moonlight gets silence while the game plays
# into the sunshine sink. (Steam Remote Play does its own capture/routing.)
audio_sink = sink-sunshine-stereo
origin_web_ui_allowed = lan
upnp = off
# Extra forward error correction: survives sporadic Wi-Fi packet loss without
# visible macroblocking (Sunshine default is 20).
fec_percentage = 30
# Newer Sunshine builds default to requiring encrypted RTSP on LAN, which
# some Moonlight clients fail with "RTSP message tag" errors; keep the
# legacy behavior on the trusted LAN.
lan_encryption_mode = 0
# No system tray: Sunshine runs headless/trayless here, and builds >= 2026.7xx
# bundle only the X11 Qt platform - with the tray enabled and no reachable
# display they SIGABRT in a crash loop. Inert (warning only) on 2026.516.
system_tray = disabled
SUNSHINE_CONF_EOF
  # Cap the streaming UDP payload below a low path MTU (VPN/tunnel clients
  # that cannot set their own packet size, e.g. Moonlight on Apple TV/iOS).
  # Server-side support requires Sunshine >= 2026.7xx; the option is parsed
  # but ignored (warning) by the pinned 2026.516 stable.
  if [[ -n "${SUNSHINE_PACKETSIZE:-}" ]]; then
    printf 'packetsize = %s\n' "$SUNSHINE_PACKETSIZE" >>"${sdir}/sunshine.conf"
  fi
  # Sunshine's web UI CSRF protection only trusts known origins; without this
  # the browser is blocked when creating credentials via https://IP:47990.
  # Plain-string format required (a JSON array is not parsed by this build).
  # If the container IP changes (DHCP), rerun repair to refresh it.
  local ct_ip
  ct_ip="$(ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)"
  if [[ -n "$ct_ip" ]]; then
    echo "csrf_allowed_origins = https://${ct_ip}:47990" >>"${sdir}/sunshine.conf"
  fi
  # Tile 1 always routes through steamos-session-select (a no-op when already
  # gaming, returns from the desktop otherwise). Tile 2 switches to the KDE
  # Plasma desktop when installed; without it the tile stays a passthrough
  # view of the current session (classic Sunshine "Desktop" behavior).
  local desktop_tile_cmd=""
  if [[ "$INSTALL_DESKTOP" == "yes" ]]; then
    desktop_tile_cmd='"cmd": "/usr/local/bin/steamos-session-select desktop",
      "auto-detach": "true",'
  fi
  cat >"${sdir}/apps.json" <<SUNSHINE_APPS_EOF
{
  "env": {},
  "apps": [
    {
      "name": "1. Steam Gaming Mode",
      "image-path": "steam.png",
      "cmd": "/usr/local/bin/steamos-session-select gaming",
      "auto-detach": "true"
    },
    {
      ${desktop_tile_cmd}
      "name": "2. Desktop",
      "image-path": "desktop.png"
    },
    {
      "name": "3. Match display to this device",
      "cmd": "/usr/local/bin/match-display-mode"
    },
    {
      "name": "4. Restart Gaming Mode",
      "cmd": "sudo /usr/bin/systemctl restart steamos-session.service",
      "auto-detach": "true"
    },
    {
      "name": "5. Diagnostics",
      "cmd": "/usr/local/sbin/steamos-streaming-diagnose --verbose",
      "auto-detach": "true"
    }
  ]
}
SUNSHINE_APPS_EOF
  chown -R deck:deck "$sdir"
  # Keep the CSRF origin in sync with the current address on every Sunshine
  # start (self-heals after DHCP changes without a repair run).
  cat >"${LIB_DIR}/update-csrf-origin" <<'CSRF_HELPER_EOF'
#!/usr/bin/env bash
IP="$(ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
[[ -n "$IP" ]] || exit 0
CONF=/home/deck/.config/sunshine/sunshine.conf
grep -qx "csrf_allowed_origins = https://${IP}:47990" "$CONF" 2>/dev/null && exit 0
sed -i '/^csrf_allowed_origins/d' "$CONF"
echo "csrf_allowed_origins = https://${IP}:47990" >>"$CONF"
exit 0
CSRF_HELPER_EOF
  chmod 0755 "${LIB_DIR}/update-csrf-origin"
  cmsg "Sunshine configured (X11 capture, VA-API encoder, GameStream.monitor audio)"
}

configure_tmpfs_limits() {
  CURRENT_PHASE="Sizing tmpfs mounts to container RAM"
  # Default tmpfs sizing derives from the HOST's RAM (lxcfs only virtualizes
  # /proc/meminfo), so /dev/shm and /tmp would advertise half of the host
  # memory. Cap them at half the container's allocation, like a real machine.
  local mem_kb half_mb
  mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  half_mb=$((mem_kb / 2048))
  [[ "$half_mb" -lt 512 ]] && half_mb=512
  grep -q '^tmpfs /dev/shm' /etc/fstab 2>/dev/null ||
    echo "tmpfs /dev/shm tmpfs nosuid,nodev,size=${half_mb}M 0 0" >>/etc/fstab
  grep -q '^tmpfs /tmp' /etc/fstab 2>/dev/null ||
    echo "tmpfs /tmp tmpfs nosuid,nodev,size=${half_mb}M 0 0" >>/etc/fstab
  mount -o "remount,size=${half_mb}M" /dev/shm >>"$LOG_FILE" 2>&1 || true
  mount -o "remount,size=${half_mb}M" /tmp >>"$LOG_FILE" 2>&1 || true
  cmsg "tmpfs mounts capped at ${half_mb} MiB (/dev/shm, /tmp)"
}

write_steamos_shims() {
  CURRENT_PHASE="Installing SteamOS updater shims"
  # In -steamos3 mode, Steam runs SteamOS's mandatory OS-update and firmware
  # checks at the boot screen. Without these helpers the checks exit 127 and
  # Steam reports a bogus "network issue". OS updates come from pacman here,
  # so shim them the way SteamOS-like distros (ChimeraOS/Bazzite) do.
  cat >/usr/bin/steamos-update <<'STEAMOS_UPDATE_SHIM_EOF'
#!/usr/bin/env bash
# SteamOS update shim - OS updates are handled by pacman in this container.
# Exit 7 = "no update available" (Steam's expected up-to-date signal).
exit 7
STEAMOS_UPDATE_SHIM_EOF
  cat >/usr/bin/steamos-select-branch <<'SELECT_BRANCH_SHIM_EOF'
#!/usr/bin/env bash
case "${1:-}" in
-c | --current) echo "stable" ;;
-l | --list) echo "stable" ;;
esac
exit 0
SELECT_BRANCH_SHIM_EOF
  printf '#!/usr/bin/env bash\nexit 0\n' >/usr/bin/jupiter-biosupdate
  printf '#!/usr/bin/env bash\nexit 0\n' >/usr/bin/jupiter-initial-firmware-update
  chmod 0755 /usr/bin/steamos-update /usr/bin/steamos-select-branch \
    /usr/bin/jupiter-biosupdate /usr/bin/jupiter-initial-firmware-update
  mkdir -p /usr/bin/steamos-polkit-helpers
  ln -sfn /usr/bin/steamos-update /usr/bin/steamos-polkit-helpers/steamos-update
  ln -sfn /usr/bin/steamos-select-branch /usr/bin/steamos-polkit-helpers/steamos-select-branch
  ln -sfn /usr/bin/jupiter-biosupdate /usr/bin/steamos-polkit-helpers/jupiter-biosupdate
  ln -sfn /usr/bin/jupiter-biosupdate /usr/bin/steamos-polkit-helpers/jupiter-dock-updater
  cmsg "SteamOS updater shims installed (OS updates stay with pacman)"
}

configure_network_manager() {
  CURRENT_PHASE="Configuring NetworkManager"
  # Steam Gaming Mode (-steamos3) reads network state from NetworkManager over
  # D-Bus, exactly like a real Steam Deck. With systemd-networkd the UI
  # reports "No network" even though connectivity is fine.
  mkdir -p /etc/NetworkManager/conf.d
  cat <<EOF >/etc/NetworkManager/conf.d/dhcp-client-id.conf
[connection]
ipv4.dhcp-client-id=mac
EOF
  # NM does not read the systemd-networkd files Proxmox generates - and
  # Proxmox re-materializes them at EVERY container start. Regenerate the NM
  # profile from that file on each boot (Before=NetworkManager), so
  # `pct set -net0` changes apply after a container restart and both static
  # and DHCP intents are always respected.
  cat >"${LIB_DIR}/sync-network" <<'SYNC_NETWORK_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - regenerate the NetworkManager profile from the
# network config Proxmox materializes at container start.
set -euo pipefail
SRC=/etc/systemd/network/eth0.network
DST=/etc/NetworkManager/system-connections/eth0.nmconnection
addr="" gw="" dns=""
if [[ -r "$SRC" ]]; then
  addr="$(sed -n 's/^Address *= *//p' "$SRC" | head -n1)"
  gw="$(sed -n 's/^Gateway *= *//p' "$SRC" | head -n1)"
  dns="$(sed -n 's/^DNS *= *//p' "$SRC" | head -n1)"
fi
mkdir -p /etc/NetworkManager/system-connections
tmp="$(mktemp)"
{
  printf '[connection]\nid=eth0\ntype=ethernet\ninterface-name=eth0\nautoconnect=true\n\n'
  if [[ -n "$addr" ]]; then
    printf '[ipv4]\nmethod=manual\naddress1=%s' "$addr"
    [[ -n "$gw" ]] && printf ',%s' "$gw"
    printf '\n'
    [[ -n "$dns" ]] && printf 'dns=%s;\n' "$dns"
    printf '\n[ipv6]\nmethod=disabled\n'
  else
    printf '[ipv4]\nmethod=auto\n'
    printf '\n[ipv6]\nmethod=auto\n'
  fi
} >"$tmp"
if ! cmp -s "$tmp" "$DST" 2>/dev/null; then
  install -m 600 "$tmp" "$DST"
  echo "sync-network: NetworkManager profile updated from PVE network config"
fi
rm -f "$tmp"
SYNC_NETWORK_EOF
  chmod 0755 "${LIB_DIR}/sync-network"
  cat >/etc/systemd/system/steamos-network-sync.service <<'NETSYNC_UNIT_EOF'
[Unit]
Description=SteamOS Streaming NM profile sync (from PVE container network config)
After=local-fs.target
Before=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/steamos-streaming/sync-network

[Install]
WantedBy=multi-user.target
NETSYNC_UNIT_EOF
  run systemctl enable steamos-network-sync.service
  "${LIB_DIR}/sync-network" >>"$LOG_FILE" 2>&1 || true
  # Only enable/mask here - never stop the running stack mid-install; the
  # switchover happens on the container restart that follows installation.
  systemctl disable systemd-networkd.service systemd-networkd.socket \
    systemd-networkd-wait-online.service >>"$LOG_FILE" 2>&1 || true
  systemctl mask systemd-networkd.service systemd-networkd.socket \
    systemd-networkd-wait-online.service >>"$LOG_FILE" 2>&1 || true
  run systemctl enable NetworkManager.service NetworkManager-wait-online.service
  cmsg "NetworkManager enabled (Steam Gaming Mode network detection)"
}

write_udev_support() {
  CURRENT_PHASE="Enabling in-container udev"
  # Kernel uevents reach a privileged container, but the host udevd's
  # processed events and database do not. Without a local udevd, Xorg never
  # sees Sunshine's virtual keyboard/mouse and streamed input goes nowhere.
  # /sys is read-only in the container, so drop udevd's rw-/sys condition
  # (it only needs to read /sys to process events), and detach any stale
  # read-only /run/udev bind left by older container configurations.
  local u
  for u in systemd-udevd-control.socket systemd-udevd-kernel.socket; do
    mkdir -p "/etc/systemd/system/${u}.d"
    cat <<EOF >"/etc/systemd/system/${u}.d/steamos-container.conf"
[Unit]
ConditionPathIsReadWrite=
EOF
  done
  mkdir -p /etc/systemd/system/systemd-udevd.service.d
  cat >/etc/systemd/system/systemd-udevd.service.d/steamos-container.conf <<'UDEVD_OVERRIDE_EOF'
[Unit]
# /sys is read-only in this LXC; udevd only needs to read it.
ConditionPathIsReadWrite=

[Service]
# Detach an (empty, read-only) host /run/udev bind so udevd can write its db.
ExecStartPre=-/usr/bin/umount -l /run/udev
UDEVD_OVERRIDE_EOF
  cmsg "In-container udev enabled (input hotplug for Sunshine virtual devices)"
}

write_systemd_units() {
  CURRENT_PHASE="Installing systemd services"

  cat >/etc/systemd/system/steamos-xorg.service <<'XORG_UNIT_EOF'
[Unit]
Description=SteamOS Streaming virtual display (Xorg dummy)
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/steamos-streaming/display-server-wayland
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
# Resolve the set-gpu marker before the display server starts (the wayland
# unit runs this too; on the Xorg stack the session and Sunshine consume it).
ExecStartPre=/usr/local/lib/steamos-streaming/gen-gpu-env
ExecStartPre=/usr/local/lib/steamos-streaming/ensure-tty
ExecStart=/usr/bin/Xorg :0 vt7 -novtswitch -sharevts -noreset -ac -nolisten tcp -config /etc/X11/xorg.conf.d/20-steamos-virtual-display.conf -logfile /var/log/steamos-streaming/Xorg.0.log
ExecStartPost=/usr/local/lib/steamos-streaming/wait-display
Restart=on-failure
RestartSec=3

[Install]
WantedBy=steamos-streaming.target
XORG_UNIT_EOF

  cat >/etc/systemd/system/steamos-wayland.service <<'WAYLAND_UNIT_EOF'
[Unit]
Description=SteamOS Streaming virtual display (sway headless Wayland)
After=network-online.target user@1000.service
Wants=network-online.target user@1000.service
ConditionPathExists=/var/lib/steamos-streaming/display-server-wayland
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
User=deck
Group=deck
WorkingDirectory=/home/deck
Environment=HOME=/home/deck
Environment=USER=deck
Environment=LOGNAME=deck
Environment=XDG_RUNTIME_DIR=/run/user/1000
# noop: open devices with the user's own permissions (deck is in hostinput);
# seatd/logind session activation never completes inside an LXC (VT
# semantics), and root-level seat management is unnecessary here.
Environment=LIBSEAT_BACKEND=noop
# High-priority GPU context for the compositor that also serves the capture
# path - without it a game at 100% GPU starves the capture repaints.
AmbientCapabilities=CAP_SYS_NICE
Environment=WLR_BACKENDS=headless,libinput
Environment=WLR_LIBINPUT_NO_DEVICES=1
# GPU selection (set-gpu): gen-gpu-env resolves the marker to a render node
# and writes WLR_RENDER_DRM_DEVICE + Mesa device-select vars there. systemd
# reads the file just before each Exec* process spawns, so the ExecStartPre
# below regenerates it in time for sway.
EnvironmentFile=-/run/steamos-streaming/gpu.env
# Vulkan renderer: with amdgpu.mcbp=1 its submissions preempt long game
# command buffers, so GPU-saturating games cannot starve capture (gles2
# waited them out: 130-215ms/capture vs 64-97ms). Needs render_bit_depth 8
# in the sway config (10-bit vulkan buffers defeat Sunshine's dmabuf
# import) and the portal capture path (capture = portal).
#Environment=WLR_RENDERER=vulkan
# Insurance for the gles2 fallback: injects a high-priority EGL context
# (wlroots never requests one); a no-op under the vulkan renderer.
Environment=LD_PRELOAD=/usr/local/lib/steamos-streaming/egl-highprio.so
ExecStartPre=+/usr/local/lib/steamos-streaming/gen-gpu-env
ExecStartPre=+/usr/local/lib/steamos-streaming/gen-sway-config
ExecStart=/usr/bin/sway -c /var/lib/steamos-streaming/sway.conf
ExecStartPost=/usr/local/lib/steamos-streaming/wait-display
ExecStartPost=/usr/local/lib/steamos-streaming/setup-portals
Restart=on-failure
RestartSec=3

[Install]
WantedBy=steamos-streaming.target
WAYLAND_UNIT_EOF

  cat >/etc/systemd/system/steamos-audio.service <<'AUDIO_UNIT_EOF'
[Unit]
Description=SteamOS Streaming audio readiness (PipeWire GameStream sink)
After=steamos-xorg.service user@1000.service
Wants=user@1000.service
Requires=steamos-xorg.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=oneshot
RemainAfterExit=yes
User=deck
Group=deck
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/usr/local/lib/steamos-streaming/wait-audio

[Install]
WantedBy=steamos-streaming.target
AUDIO_UNIT_EOF

  cat >/etc/systemd/system/steamos-gamelib.service <<'GAMELIB_UNIT_EOF'
[Unit]
Description=SteamOS Streaming game library preparation (Proton dirs on native fs)
Before=steamos-session.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/lib/steamos-streaming/setup-game-library

[Install]
WantedBy=steamos-streaming.target
GAMELIB_UNIT_EOF

  cat >/etc/systemd/system/steamos-session.service <<'SESSION_UNIT_EOF'
[Unit]
Description=SteamOS Streaming Steam Gaming Mode (Gamescope session)
After=steamos-audio.service user@1000.service steamos-xorg.service steamos-wayland.service
Wants=steamos-audio.service user@1000.service steamos-xorg.service steamos-wayland.service
# Gamescope's window dies with the compositor; follow display-server restarts
# (an orphaned session renders black with dead input).
PartOf=steamos-xorg.service
PartOf=steamos-wayland.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
User=deck
Group=deck
WorkingDirectory=/home/deck
Environment=HOME=/home/deck
Environment=USER=deck
Environment=LOGNAME=deck
Environment=XDG_RUNTIME_DIR=/run/user/1000
# High-priority GPU queues for gamescope's compositing (Steam Deck parity):
# without this an uncapped game at 100% GPU starves the compositor and the
# zero-copy capture path. File caps (setcap) are blocked in the LXC.
AmbientCapabilities=CAP_SYS_NICE
# GPU selection (set-gpu): gamescope, Steam and games follow the chosen GPU
# via MESA_VK_DEVICE_SELECT / DRI_PRIME; unit env is inherited by every
# child, so the session wrapper needs no changes.
EnvironmentFile=-/run/steamos-streaming/gpu.env
ExecStartPre=/usr/local/lib/steamos-streaming/wait-display
ExecStartPre=/usr/local/lib/steamos-streaming/register-library
# The launcher picks Gaming Mode or Desktop Mode from the marker written by
# steamos-session-select; one unit hosting both makes the modes mutually
# exclusive by construction.
ExecStart=/usr/local/bin/steamos-session-launcher
# always: when Steam crashes, gamescope exits cleanly (code 0) and on-failure
# would leave the appliance without a session.
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=steamos-streaming.target
SESSION_UNIT_EOF

  cat >/etc/systemd/system/sunshine.service <<'SUNSHINE_UNIT_EOF'
[Unit]
Description=Sunshine game stream host (native AppImage)
# Ordered after the session but does NOT want it: a Sunshine restart must
# not drag Gaming Mode back up while Desktop Mode owns the display.
After=steamos-session.service steamos-audio.service user@1000.service
Wants=steamos-audio.service user@1000.service
# Sunshine holds a live connection to the display server; when that restarts
# Sunshine keeps running with a dead capture backend. Restart along with it.
PartOf=steamos-xorg.service
PartOf=steamos-wayland.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
User=deck
Group=deck
WorkingDirectory=/home/deck
Environment=HOME=/home/deck
Environment=USER=deck
Environment=LOGNAME=deck
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=PULSE_SERVER=unix:/run/user/1000/pulse/native
# The AppImage bundles an Ubuntu libva that searches /usr/lib/x86_64-linux-gnu;
# point it at Arch's VA-API driver location or encoding falls back to software.
Environment=LIBVA_DRIVERS_PATH=/usr/lib/dri
Environment=LIBVA_DRIVER_NAME=radeonsi
# High-priority EGL/encode context so capture is not starved by a game
# holding the GPU at 100% (sunshine logs a warning without it).
AmbientCapabilities=CAP_SYS_NICE
# gen-display-env writes DISPLAY=:0 (Xorg stack) or WAYLAND_DISPLAY=... (sway
# stack); Sunshine picks its capture backend from whichever is present.
EnvironmentFile=-/run/user/1000/steamos-display.env
ExecStartPre=/usr/local/lib/steamos-streaming/gen-display-env
ExecStartPre=/usr/local/lib/steamos-streaming/update-csrf-origin
ExecStart=/usr/local/bin/sunshine
Restart=on-failure
RestartSec=3

[Install]
WantedBy=steamos-streaming.target
SUNSHINE_UNIT_EOF

  cat >/etc/systemd/system/steamos-watchdog.service <<'WATCHDOG_UNIT_EOF'
[Unit]
Description=SteamOS Streaming black-screen watchdog

[Service]
Type=oneshot
ExecStart=/usr/local/lib/steamos-streaming/blackscreen-watchdog
WATCHDOG_UNIT_EOF

  cat >/etc/systemd/system/steamos-watchdog.timer <<'WATCHDOG_TIMER_EOF'
[Unit]
Description=SteamOS Streaming black-screen watchdog timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
WATCHDOG_TIMER_EOF

  cat >/etc/systemd/system/steamos-streaming.target <<'TARGET_UNIT_EOF'
[Unit]
Description=SteamOS Streaming stack (Xorg, PipeWire, Gaming Mode, Sunshine)
Wants=steamos-xorg.service steamos-audio.service steamos-session.service sunshine.service
After=steamos-xorg.service steamos-audio.service steamos-session.service sunshine.service

[Install]
WantedBy=multi-user.target
TARGET_UNIT_EOF

  run systemctl daemon-reload
  run systemctl enable steamos-xorg.service steamos-wayland.service \
    steamos-audio.service steamos-gamelib.service steamos-session.service \
    sunshine.service steamos-streaming.target steamos-watchdog.timer
  cmsg "systemd services installed and enabled"
}

write_maintenance_scripts() {
  CURRENT_PHASE="Installing maintenance commands"

  # Keep a copy of this installer for repair operations. Under the
  # community-scripts engine the script arrives via `bash -c` and $0 is not a
  # file - fetch the published copy instead so in-container repair still works.
  local _self
  if _self="$(readlink -f "$0" 2>/dev/null)" && [[ -f "$_self" ]]; then
    cp "$_self" "${LIB_DIR}/installer.sh"
  elif ! curl -fsSL "https://raw.githubusercontent.com/netwarex/sunshine-on-steamos/main/install/sunshine-on-steamos-install.sh" \
    -o "${LIB_DIR}/installer.sh" 2>/dev/null; then
    # Offline fallback: repair must be re-driven from the host-side script.
    cat >"${LIB_DIR}/installer.sh" <<'INSTALLER_STUB_EOF'
#!/usr/bin/env bash
echo "No local installer copy was archived (engine-delivered install)." >&2
echo "Re-run the repair from the Proxmox host instead (ct script update," >&2
echo "or the standalone installer's 'repair CTID' mode)." >&2
exit 1
INSTALLER_STUB_EOF
  fi
  chmod 0755 "${LIB_DIR}/installer.sh"

  cat >/usr/local/sbin/steamos-streaming-repair <<'REPAIR_EOF'
#!/usr/bin/env bash
# Regenerates all generated configuration while preserving user data.
exec bash /usr/local/lib/steamos-streaming/installer.sh repair
REPAIR_EOF
  chmod 0755 /usr/local/sbin/steamos-streaming-repair

  # ---------------------------------------------------------------- diagnose
  cat >/usr/local/sbin/steamos-streaming-diagnose <<'DIAG_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC health check. Exits nonzero when a required item fails.
set -uo pipefail
VERBOSE=0
JSON=0
for arg in "$@"; do
  case "$arg" in
  --verbose) VERBOSE=1 ;;
  --json) JSON=1 ;;
  *) echo "usage: steamos-streaming-diagnose [--verbose] [--json]" >&2; exit 2 ;;
  esac
done
# shellcheck disable=SC1090,SC1091
source /etc/steamos-streaming-release 2>/dev/null || true
GPU_RENDER_NODE="${GPU_RENDER_NODE:-/dev/dri/renderD128}"
# set-gpu override: the stack runs on the node resolved by gen-gpu-env, not
# necessarily the install-time default from the release file.
if [[ -r /run/steamos-streaming/gpu.env ]]; then
  # shellcheck disable=SC1090,SC1091
  source /run/steamos-streaming/gpu.env
  GPU_RENDER_NODE="${STEAMOS_RENDER_NODE:-$GPU_RENDER_NODE}"
fi
STREAM_WIDTH="${STREAM_WIDTH:-1920}"
STREAM_HEIGHT="${STREAM_HEIGHT:-1080}"
# A runtime mode set with set-display-mode overrides the installed default.
if [[ -r /var/lib/steamos-streaming/display-mode ]]; then
  _dm="$(head -n1 /var/lib/steamos-streaming/display-mode | tr -d '[:space:]')"
  if [[ "$_dm" =~ ^([0-9]+)x([0-9]+)(@([0-9]+))?$ ]]; then
    STREAM_WIDTH="${BASH_REMATCH[1]}"
    STREAM_HEIGHT="${BASH_REMATCH[2]}"
  fi
fi
XDG_RUNTIME_DIR_DECK=/run/user/1000

declare -a R_NAME R_STATUS R_DETAIL R_REQUIRED
add_result() { R_NAME+=("$1"); R_STATUS+=("$2"); R_DETAIL+=("$3"); R_REQUIRED+=("$4"); }

as_deck() { sudo -u deck env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR_DECK" "$@"; }

check_privileged() {
  if awk '{print $1, $2, $3}' /proc/self/uid_map 2>/dev/null | grep -qx "0 0 4294967295"; then
    add_result "Container is privileged" PASS "full uid map" 1
  else
    add_result "Container is privileged" FAIL "uid map is restricted (unprivileged container?)" 1
  fi
}
check_features() {
  if as_deck unshare -U true >/dev/null 2>&1; then
    add_result "Required LXC features present" PASS "user namespaces available (nesting=1)" 1
  else
    add_result "Required LXC features present" FAIL "cannot create user namespace; Steam pressure-vessel will fail (need features: nesting=1)" 1
  fi
}
check_render_node() {
  if [[ -e "$GPU_RENDER_NODE" ]]; then
    add_result "GPU render node exists" PASS "$GPU_RENDER_NODE" 1
  else
    add_result "GPU render node exists" FAIL "$GPU_RENDER_NODE missing (check LXC dev0 mapping)" 1
    return
  fi
  if as_deck test -r "$GPU_RENDER_NODE" && as_deck test -w "$GPU_RENDER_NODE"; then
    add_result "GPU render node writable by deck" PASS "$GPU_RENDER_NODE" 1
  else
    add_result "GPU render node writable by deck" FAIL "deck cannot access $GPU_RENDER_NODE" 1
  fi
}
check_uinput() {
  if [[ -e /dev/uinput ]] && as_deck test -r /dev/uinput && as_deck test -w /dev/uinput; then
    add_result "/dev/uinput available" PASS "readable and writable by deck" 1
  else
    add_result "/dev/uinput available" FAIL "missing or not accessible by deck (virtual input broken)" 1
  fi
  if [[ -e /dev/uhid ]] && as_deck test -r /dev/uhid && as_deck test -w /dev/uhid; then
    add_result "/dev/uhid available" PASS "readable and writable by deck" 1
  else
    add_result "/dev/uhid available" FAIL "missing or not accessible by deck" 1
  fi
}
check_vulkan() {
  local summary
  summary="$(as_deck vulkaninfo --summary 2>/dev/null)"
  if [[ -z "$summary" ]]; then
    add_result "Vulkan GPU detected" FAIL "vulkaninfo produced no output" 1
    add_result "No llvmpipe" FAIL "cannot verify" 1
    return
  fi
  if echo "$summary" | grep -qiE 'RADV|AMD'; then
    add_result "Vulkan GPU detected" PASS "$(echo "$summary" | grep -m1 -oE 'deviceName.*' | sed 's/deviceName *= *//')" 1
  else
    add_result "Vulkan GPU detected" FAIL "no AMD RADV device in vulkaninfo output" 1
  fi
  if echo "$summary" | grep -qi llvmpipe && ! echo "$summary" | grep -qiE 'RADV|AMD'; then
    add_result "No llvmpipe" FAIL "only llvmpipe software rendering available" 1
  else
    add_result "No llvmpipe" PASS "hardware Vulkan device present" 1
  fi
}
check_vaapi() {
  local out
  out="$(vainfo --display drm --device "$GPU_RENDER_NODE" 2>/dev/null)"
  if echo "$out" | grep -E 'VAProfileH264' | grep -qE 'VAEntrypointEncSlice'; then
    add_result "VA-API H.264 encoding available" PASS "H.264 hardware encoder present" 1
  else
    add_result "VA-API H.264 encoding available" FAIL "no H.264 encode entrypoint; refusing silent software encoding. vainfo: $(echo "$out" | tail -n 5 | tr '\n' ' ')" 1
  fi
  if echo "$out" | grep -E 'VAProfileHEVCMain([^1]|$)' | grep -qE 'EncSlice'; then
    add_result "HEVC Main encoding" PASS "available" 0
  else
    add_result "HEVC Main encoding" WARN "not reported" 0
  fi
  if echo "$out" | grep -E 'VAProfileHEVCMain10' | grep -qE 'EncSlice'; then
    add_result "HEVC Main 10 encoding" PASS "available" 0
  else
    add_result "HEVC Main 10 encoding" WARN "not reported" 0
  fi
  if echo "$out" | grep -E 'VAProfileAV1' | grep -qE 'EncSlice'; then
    add_result "AV1 encoding" PASS "available" 0
  else
    add_result "AV1 encoding" WARN "not reported" 0
  fi
}
check_udev() {
  if systemctl is-active --quiet systemd-udevd.service; then
    add_result "In-container udevd active" PASS "input hotplug available" 1
  else
    add_result "In-container udevd active" FAIL "systemd-udevd not running; Xorg cannot see Sunshine virtual input devices" 1
  fi
}
check_networkmanager() {
  if ! systemctl is-active --quiet NetworkManager.service; then
    add_result "NetworkManager active" FAIL "NetworkManager not running; Steam Gaming Mode will report no network" 1
    return
  fi
  add_result "NetworkManager active" PASS "Steam network detection available" 1
  local conn
  conn="$(nmcli -t -f CONNECTIVITY general status 2>/dev/null)"
  if [[ "$conn" == "full" ]]; then
    add_result "NetworkManager connectivity" PASS "full" 0
  else
    add_result "NetworkManager connectivity" WARN "reported: ${conn:-unknown}" 0
  fi
}
check_xorg() {
  if systemctl is-active --quiet steamos-xorg.service; then
    add_result "Xorg service active" PASS "steamos-xorg.service running" 1
  else
    add_result "Xorg service active" FAIL "steamos-xorg.service not active" 1
    add_result "Virtual resolution correct" FAIL "Xorg not running" 1
    return
  fi
  local dims
  dims="$(DISPLAY=:0 xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2}' | head -n1)"
  if [[ "$dims" == "${STREAM_WIDTH}x${STREAM_HEIGHT}" ]]; then
    add_result "Virtual resolution correct" PASS "$dims" 1
  else
    add_result "Virtual resolution correct" FAIL "expected ${STREAM_WIDTH}x${STREAM_HEIGHT}, got ${dims:-none}" 1
  fi
}
check_audio() {
  if as_deck wpctl status >/dev/null 2>&1 || as_deck pactl info >/dev/null 2>&1; then
    add_result "PipeWire active" PASS "deck user PipeWire responding (wpctl status)" 1
  else
    add_result "PipeWire active" FAIL "deck user PipeWire/pipewire-pulse not responding" 1
    add_result "GameStream sink exists" FAIL "PipeWire down" 1
    add_result "GameStream monitor exists" FAIL "PipeWire down" 1
    return
  fi
  if as_deck pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -qx GameStream; then
    add_result "GameStream sink exists" PASS "GameStream" 1
  else
    add_result "GameStream sink exists" FAIL "sink GameStream not found (wpctl status / pactl list short sinks)" 1
  fi
  if as_deck pactl list short sources 2>/dev/null | awk '{print $2}' | grep -qx GameStream.monitor; then
    add_result "GameStream monitor exists" PASS "GameStream.monitor" 1
  else
    add_result "GameStream monitor exists" FAIL "source GameStream.monitor not found" 1
  fi
}
check_session() {
  # gamescope renames its main process to "gamescope-wl"; match the prefix.
  if pgrep -u deck '^gamescope' >/dev/null 2>&1; then
    add_result "Gamescope active" PASS "gamescope process running" 1
  else
    add_result "Gamescope active" FAIL "no gamescope process for deck" 1
  fi
  if pgrep -u deck -f '[s]team' >/dev/null 2>&1; then
    add_result "Steam active" PASS "steam process running" 1
  else
    add_result "Steam active" FAIL "no steam process for deck" 1
  fi
  # A crash-looping session can look "active" at any single sampling instant
  # (observed: gamescope SEGV every ~4s on the Xorg path still passed the old
  # point-in-time checks). NRestarts counts automatic restarts since the last
  # manual start/restart, so a small number is normal after a watchdog kick
  # but a large one means the session is not actually holding up.
  local nrestarts
  nrestarts="$(systemctl show -p NRestarts --value steamos-session.service 2>/dev/null || echo 0)"
  if [[ "${nrestarts:-0}" -ge 5 ]]; then
    add_result "Session stable" FAIL "steamos-session auto-restarted ${nrestarts} times (crash loop)" 1
  else
    add_result "Session stable" PASS "auto-restarts since last manual start: ${nrestarts:-0}" 1
  fi
}
check_sunshine() {
  if systemctl is-active --quiet sunshine.service; then
    add_result "Sunshine active" PASS "sunshine.service running" 1
  else
    add_result "Sunshine active" FAIL "sunshine.service not active" 1
  fi
  if ss -tln 2>/dev/null | grep -q ':47990'; then
    add_result "Sunshine web port listening" PASS "https://:47990" 1
  else
    add_result "Sunshine web port listening" FAIL "port 47990 not listening" 1
  fi
  # Only inspect the current service invocation: earlier failed probes in the
  # same boot would otherwise report a stale software-encoding fallback.
  local slog iid
  iid="$(systemctl show -p InvocationID --value sunshine.service 2>/dev/null)"
  slog="$(journalctl _SYSTEMD_INVOCATION_ID="$iid" --no-pager 2>/dev/null | tail -n 400)"
  if echo "$slog" | grep -qiE 'software.*encod|encod.*software'; then
    add_result "Sunshine hardware encoder initialized" FAIL "Sunshine fell back to software encoding" 1
  elif echo "$slog" | grep -qiE '(found|creat|initializ).*(vaapi|va-api)|(vaapi|va-api).*encoder'; then
    add_result "Sunshine hardware encoder initialized" PASS "VA-API encoder reported in Sunshine log" 1
  else
    add_result "Sunshine hardware encoder initialized" WARN "no explicit VA-API probe line found yet (encoder is validated on first stream)" 0
  fi
}
check_ip() {
  local ip
  ip="$(ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  if [[ -n "$ip" ]]; then
    add_result "Container IP detected" PASS "$ip" 1
  else
    add_result "Container IP detected" FAIL "no IPv4 address on eth0" 1
  fi
}

check_games_mount() {
  # Only meaningful when the host delivers a raw games disk to the hidden
  # path (steamos-games-mount serves /games from it).
  mountpoint -q /var/lib/steamos-streaming/.games-raw 2>/dev/null || return 0
  if mountpoint -q /games 2>/dev/null; then
    add_result "Game library mount (/games)" PASS "$(findmnt -no FSTYPE /games 2>/dev/null)" 1
  else
    add_result "Game library mount (/games)" FAIL "raw games disk present but /games not mounted (steamos-games-mount.service)" 1
  fi
}
check_privileged
check_features
check_render_node
check_games_mount
check_uinput
check_vulkan
check_vaapi
check_udev
check_networkmanager
check_display() {
  if [[ -e /var/lib/steamos-streaming/display-server-wayland ]]; then
    if systemctl is-active --quiet steamos-wayland.service; then
      add_result "Display server active" PASS "steamos-wayland.service (sway headless) running" 1
    else
      add_result "Display server active" FAIL "steamos-wayland.service not active" 1
      add_result "Virtual resolution correct" FAIL "sway not running" 1
      return
    fi
    local sock dims
    sock="$(ls -t /run/user/1000/sway-ipc.* 2>/dev/null | head -n1)"
    dims="$(swaymsg -s "$sock" -t get_outputs 2>/dev/null | jq -r '.[0].current_mode | "\(.width)x\(.height)"' 2>/dev/null)"
    if [[ "$dims" == "${STREAM_WIDTH}x${STREAM_HEIGHT}" ]]; then
      add_result "Virtual resolution correct" PASS "$dims" 1
    else
      add_result "Virtual resolution correct" FAIL "expected ${STREAM_WIDTH}x${STREAM_HEIGHT}, got ${dims:-none}" 1
    fi
    return
  fi
  check_xorg
}
check_display
check_audio
check_session
check_sunshine
check_ip

FAILED=0
for i in "${!R_NAME[@]}"; do
  [[ "${R_STATUS[$i]}" == "FAIL" && "${R_REQUIRED[$i]}" == "1" ]] && FAILED=$((FAILED + 1))
done

if [[ "$JSON" -eq 1 ]]; then
  printf '{"failed_required":%d,"checks":[' "$FAILED"
  for i in "${!R_NAME[@]}"; do
    [[ "$i" -gt 0 ]] && printf ','
    printf '{"check":"%s","status":"%s","required":%s,"detail":"%s"}' \
      "${R_NAME[$i]}" "${R_STATUS[$i]}" "${R_REQUIRED[$i]}" \
      "$(echo "${R_DETAIL[$i]}" | tr -d '"\\' | tr '\n' ' ')"
  done
  printf ']}\n'
else
  GN=$'\033[1;92m'; RD=$'\033[01;31m'; YWB=$'\033[93m'; CL=$'\033[m'
  echo "SteamOS Streaming LXC health check"
  echo "----------------------------------"
  for i in "${!R_NAME[@]}"; do
    case "${R_STATUS[$i]}" in
    PASS) printf '  %s[PASS]%s %s\n' "$GN" "$CL" "${R_NAME[$i]}" ;;
    WARN) printf '  %s[WARN]%s %s\n' "$YWB" "$CL" "${R_NAME[$i]}" ;;
    FAIL) printf '  %s[FAIL]%s %s\n' "$RD" "$CL" "${R_NAME[$i]}" ;;
    esac
    if [[ "$VERBOSE" -eq 1 || "${R_STATUS[$i]}" != "PASS" ]]; then
      printf '         %s\n' "${R_DETAIL[$i]}"
    fi
  done
  echo "----------------------------------"
  if [[ "$FAILED" -gt 0 ]]; then
    echo "${RD}${FAILED} required check(s) failed${CL}"
  else
    echo "${GN}All required checks passed${CL}"
  fi
fi
[[ "$FAILED" -gt 0 ]] && exit 1
exit 0
DIAG_EOF
  chmod 0755 /usr/local/sbin/steamos-streaming-diagnose

  # ------------------------------------------------------------------ update
  cat >/usr/local/sbin/steamos-streaming-update <<'UPDATE_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC updater. Preserves Steam data, Sunshine credentials and
# paired clients. Rolls back the Sunshine symlink if the new version fails.
set -Eeuo pipefail
LOCK_FILE="/var/lock/steamos-streaming-update.lock"
LOG_FILE="/var/log/steamos-streaming/update.log"
RELEASE_FILE="/etc/steamos-streaming-release"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Another update is already running." >&2
  exit 1
fi
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"; }
# shellcheck disable=SC1090,SC1091
source "$RELEASE_FILE"
CHANNEL="${1:-${RELEASE_CHANNEL:-stable}}"
CHANNEL="${CHANNEL#--}"
case "$CHANNEL" in stable | latest) ;; *)
  echo "usage: steamos-streaming-update [stable|latest]" >&2
  exit 2
  ;;
esac

log "Starting update (channel: ${CHANNEL})"
avail_kb="$(df --output=avail / | tail -n1 | tr -d ' ')"
if [[ "$avail_kb" -lt 2097152 ]]; then
  log "ERROR: less than 2 GiB free on /; aborting update."
  exit 1
fi

backup_dir="/var/backups/steamos-streaming/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
{
  pacman -Q steam gamescope mesa vulkan-radeon 2>/dev/null || true
  readlink -f /opt/sunshine/current 2>/dev/null || true
} >"${backup_dir}/versions.txt"
tar czf "${backup_dir}/config.tar.gz" \
  /etc/steamos-streaming-release \
  /etc/X11/xorg.conf.d/20-steamos-virtual-display.conf \
  /etc/pipewire/pipewire.conf.d/10-steamos-gamestream.conf \
  /etc/systemd/system/steamos-*.service /etc/systemd/system/sunshine.service \
  /etc/systemd/system/steamos-streaming.target \
  /usr/local/bin/steamos-gaming-mode \
  /home/deck/.config/sunshine/sunshine.conf /home/deck/.config/sunshine/apps.json \
  2>/dev/null || true
log "Configuration backed up to ${backup_dir}"

log "Updating Arch packages (pacman -Syu)"
pacman -Syu --noconfirm >>"$LOG_FILE" 2>&1
log "Arch packages updated"

prev_sunshine="$(readlink -f /opt/sunshine/current 2>/dev/null || true)"
target_version="$SUNSHINE_VERSION"
target_url="$SUNSHINE_URL"
target_sha="$SUNSHINE_SHA256"
if [[ "$CHANNEL" == "latest" ]]; then
  log "WARNING: latest channel resolves the newest Sunshine release; reproducibility is reduced."
  tag="$(curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest | jq -r '.tag_name')"
  target_version="${tag#v}"
  target_url="https://github.com/LizardByte/Sunshine/releases/download/${tag}/sunshine.AppImage"
  target_sha=""
fi
if [[ ! -x "/opt/sunshine/${target_version}/AppRun" ]]; then
  log "Installing Sunshine ${target_version}"
  tmpd="$(mktemp -d)"
  curl -fsSL -o "${tmpd}/sunshine.AppImage" "$target_url" >>"$LOG_FILE" 2>&1
  if [[ -n "$target_sha" ]]; then
    got="$(sha256sum "${tmpd}/sunshine.AppImage" | awk '{print $1}')"
    if [[ "$got" != "$target_sha" ]]; then
      log "ERROR: Sunshine checksum mismatch; keeping current version."
      rm -rf "$tmpd"
      exit 1
    fi
  fi
  size="$(stat -c%s "${tmpd}/sunshine.AppImage")"
  if [[ "$size" -lt 10485760 ]]; then
    log "ERROR: downloaded Sunshine AppImage looks invalid (${size} bytes)."
    rm -rf "$tmpd"
    exit 1
  fi
  chmod +x "${tmpd}/sunshine.AppImage"
  (cd "$tmpd" && ./sunshine.AppImage --appimage-extract >>"$LOG_FILE" 2>&1)
  rm -rf "/opt/sunshine/${target_version}"
  mv "${tmpd}/squashfs-root" "/opt/sunshine/${target_version}"
  rm -rf "$tmpd"
  # Bundled libva cannot load Arch's newer VA-API driver; use the system libva.
  rm -f "/opt/sunshine/${target_version}"/usr/lib/libva.so* \
    "/opt/sunshine/${target_version}"/usr/lib/libva-drm.so* \
    "/opt/sunshine/${target_version}"/usr/lib/libva-x11.so*
fi
ln -sfn "/opt/sunshine/${target_version}" /opt/sunshine/current
sed -i "s/^SUNSHINE_VERSION=.*/SUNSHINE_VERSION=${target_version}/" "$RELEASE_FILE"

log "Restarting streaming services"
systemctl reset-failed >>"$LOG_FILE" 2>&1 || true
systemctl restart steamos-xorg.service steamos-audio.service \
  steamos-session.service sunshine.service >>"$LOG_FILE" 2>&1 || true
sleep 8
if ! systemctl is-active --quiet sunshine.service; then
  log "Sunshine failed after update; rolling back symlink"
  if [[ -n "$prev_sunshine" && -x "${prev_sunshine}/AppRun" ]]; then
    ln -sfn "$prev_sunshine" /opt/sunshine/current
    sed -i "s|^SUNSHINE_VERSION=.*|SUNSHINE_VERSION=$(basename "$prev_sunshine")|" "$RELEASE_FILE"
    systemctl restart sunshine.service || true
    log "Rolled back Sunshine to $(basename "$prev_sunshine")"
  fi
fi

# Refresh recorded component versions.
gs_ver="$(pacman -Q gamescope 2>/dev/null | awk '{print $2}')"
mesa_ver="$(pacman -Q mesa 2>/dev/null | awk '{print $2}')"
sed -i "s/^GAMESCOPE_VERSION=.*/GAMESCOPE_VERSION=${gs_ver:-unknown}/" "$RELEASE_FILE"
sed -i "s/^MESA_VERSION=.*/MESA_VERSION=${mesa_ver:-unknown}/" "$RELEASE_FILE"

log "Running diagnostics"
if /usr/local/sbin/steamos-streaming-diagnose; then
  log "Update finished successfully"
else
  log "Update finished with failed health checks; see diagnostics output above"
  exit 1
fi
UPDATE_EOF
  chmod 0755 /usr/local/sbin/steamos-streaming-update

  # ------------------------------------------------------------------ config
  cat >/usr/local/sbin/steamos-streaming-config <<'CONFIG_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC configuration menu.
set -uo pipefail
RELEASE_FILE="/etc/steamos-streaming-release"
# shellcheck disable=SC1090,SC1091
source "$RELEASE_FILE"

restart_stack() {
  systemctl reset-failed >/dev/null 2>&1 || true
  systemctl restart steamos-xorg.service steamos-audio.service \
    steamos-session.service sunshine.service
  echo "Streaming stack restarted."
}

show_url() {
  local ip
  ip="$(ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  echo "Sunshine web UI / pairing: https://${ip:-CONTAINER_IP}:47990"
}

while true; do
  # shellcheck disable=SC1091
  source "$RELEASE_FILE"
  echo ""
  echo "SteamOS Streaming configuration (${STREAM_WIDTH}x${STREAM_HEIGHT}@${STREAM_FPS}, encoder ${ENCODER:-vaapi})"
  echo " 1) Change virtual resolution"
  echo " 2) Change frame rate"
  echo " 3) Select hardware encoder"
  echo " 4) Restart Gaming Mode"
  echo " 5) Restart Sunshine"
  echo " 6) Reset Sunshine credentials"
  echo " 7) Show pairing URL"
  echo " 8) Enable/disable Steam autostart"
  echo " 9) Enable/disable SSH"
  echo "10) Run diagnostics"
  echo "11) Show logs"
  echo " 0) Exit"
  read -rp "Select: " choice
  case "$choice" in
  1)
    echo "Resolutions: 1) 1920x1080  2) 2560x1440  3) 3840x2160"
    read -rp "Select resolution: " r
    case "$r" in
    1) W=1920 H=1080 ;;
    2) W=2560 H=1440 ;;
    3) W=3840 H=2160 ;;
    *) echo "Invalid selection."; continue ;;
    esac
    /usr/local/lib/steamos-streaming/gen-xorg "$W" "$H" "${STREAM_FPS:-60}"
    restart_stack
    ;;
  2)
    read -rp "Frame rate (Hz, e.g. 60): " fps
    if [[ "$fps" =~ ^[0-9]+$ && "$fps" -ge 30 && "$fps" -le 120 ]]; then
      /usr/local/lib/steamos-streaming/gen-xorg "${STREAM_WIDTH}" "${STREAM_HEIGHT}" "$fps"
      restart_stack
    else
      echo "Invalid frame rate."
    fi
    ;;
  3)
    echo "Encoders: 1) vaapi (hardware, recommended)  2) software (x264, high CPU)"
    read -rp "Select encoder: " e
    case "$e" in
    1) enc=vaapi ;;
    2) enc=software; echo "WARNING: software encoding increases CPU load and latency." ;;
    *) echo "Invalid selection."; continue ;;
    esac
    sed -i "s/^encoder = .*/encoder = ${enc}/" /home/deck/.config/sunshine/sunshine.conf
    sed -i "s/^ENCODER=.*/ENCODER=${enc}/" "$RELEASE_FILE"
    systemctl restart sunshine.service
    echo "Sunshine encoder set to ${enc}."
    ;;
  4) systemctl restart steamos-session.service && echo "Gaming Mode restarted." ;;
  5) systemctl restart sunshine.service && echo "Sunshine restarted." ;;
  6)
    read -rp "New Sunshine username: " suser
    read -rsp "New Sunshine password: " spass
    echo ""
    if [[ -n "$suser" && -n "$spass" ]]; then
      sudo -u deck /usr/local/bin/sunshine --creds "$suser" "$spass" &&
        systemctl restart sunshine.service &&
        echo "Sunshine credentials updated (pairings preserved)."
    else
      echo "Username and password must not be empty."
    fi
    ;;
  7) show_url ;;
  8)
    if systemctl is-enabled --quiet steamos-session.service; then
      systemctl disable --now steamos-session.service
      echo "Steam autostart disabled."
    else
      systemctl enable --now steamos-session.service
      echo "Steam autostart enabled."
    fi
    ;;
  9)
    if systemctl is-enabled --quiet sshd.service 2>/dev/null; then
      systemctl disable --now sshd.service
      echo "SSH disabled."
    else
      pacman -S --noconfirm --needed openssh >/dev/null 2>&1 || true
      systemctl enable --now sshd.service
      echo "SSH enabled."
    fi
    ;;
  10) /usr/local/sbin/steamos-streaming-diagnose --verbose ;;
  11) /usr/local/sbin/steamos-streaming-logs --all ;;
  0) exit 0 ;;
  *) echo "Invalid selection." ;;
  esac
done
CONFIG_EOF
  chmod 0755 /usr/local/sbin/steamos-streaming-config

  # -------------------------------------------------------------------- logs
  cat >/usr/local/sbin/steamos-streaming-logs <<'LOGS_EOF'
#!/usr/bin/env bash
# Convenience wrapper around the systemd journal for the streaming stack.
set -uo pipefail
UNITS=()
FOLLOW=()
for arg in "$@"; do
  case "$arg" in
  --all) UNITS=(-u steamos-xorg.service -u steamos-audio.service -u steamos-session.service -u sunshine.service) ;;
  --xorg) UNITS+=(-u steamos-xorg.service) ;;
  --steam) UNITS+=(-u steamos-session.service) ;;
  --sunshine) UNITS+=(-u sunshine.service) ;;
  --audio) UNITS+=(-u steamos-audio.service) ;;
  --follow) FOLLOW=(-f) ;;
  *)
    echo "usage: steamos-streaming-logs [--all|--xorg|--steam|--sunshine|--audio] [--follow]" >&2
    exit 2
    ;;
  esac
done
if [[ "${#UNITS[@]}" -eq 0 ]]; then
  UNITS=(-u steamos-xorg.service -u steamos-audio.service -u steamos-session.service -u sunshine.service)
fi
exec journalctl --no-pager -n 200 "${UNITS[@]}" "${FOLLOW[@]}"
LOGS_EOF
  chmod 0755 /usr/local/sbin/steamos-streaming-logs

  # lxc-attach ("pct exec") searches a minimal PATH without /usr/local/*;
  # symlink the user-facing commands into /usr/bin so the documented
  # "pct exec CTID -- <command>" invocations resolve.
  local mcmd
  for mcmd in diagnose update repair config logs; do
    ln -sf "/usr/local/sbin/steamos-streaming-${mcmd}" "/usr/bin/steamos-streaming-${mcmd}"
  done

  cmsg "Maintenance commands installed (diagnose, update, repair, config, logs)"
}

configure_ssh() {
  CURRENT_PHASE="Configuring SSH"
  if [[ "$ENABLE_SSH" == "yes" ]]; then
    run pacman -S --noconfirm --needed openssh
    run systemctl enable sshd.service
    cmsg "SSH server enabled"
  else
    systemctl disable --now sshd.service >>"$LOG_FILE" 2>&1 || true
    cmsg "SSH server disabled (use 'pct enter CTID' on the host)"
  fi
}

record_versions() {
  CURRENT_PHASE="Recording component versions"
  local gs_ver mesa_ver
  gs_ver="$(pacman -Q gamescope 2>/dev/null | awk '{print $2}' || echo unknown)"
  mesa_ver="$(pacman -Q mesa 2>/dev/null | awk '{print $2}' || echo unknown)"
  sed -i "s/^GAMESCOPE_VERSION=.*/GAMESCOPE_VERSION=${gs_ver:-unknown}/" "$RELEASE_FILE"
  sed -i "s/^MESA_VERSION=.*/MESA_VERSION=${mesa_ver:-unknown}/" "$RELEASE_FILE"
  cmsg "Recorded versions (gamescope ${gs_ver:-unknown}, mesa ${mesa_ver:-unknown})"
}

validate_acceleration() {
  CURRENT_PHASE="Validating hardware acceleration"
  cmsg "Validating Vulkan and VA-API hardware acceleration"
  local vk
  vk="$(sudo -u deck vulkaninfo --summary 2>/dev/null || true)"
  if ! echo "$vk" | grep -qiE 'RADV|AMD'; then
    cerr "Software rendering detected: vulkaninfo does not report an AMD RADV device."
    echo "$vk" | tail -n 30 >>"$LOG_FILE" || true
    exit 1
  fi
  local va
  va="$(vainfo --display drm --device "$GPU_RENDER_NODE" 2>&1 || true)"
  echo "$va" >>"$LOG_FILE"
  if ! echo "$va" | grep -E 'VAProfileH264' | grep -qE 'VAEntrypointEncSlice'; then
    cerr "No VA-API H.264 hardware encoder found on ${GPU_RENDER_NODE}."
    cerr "Refusing to configure software encoding silently. vainfo output:"
    echo "$va" | tail -n 20 >&2
    exit 1
  fi
  cmsg "Hardware acceleration validated (RADV Vulkan + VA-API H.264 encode)"
}

apply_display_server_choice() {
  CURRENT_PHASE="Selecting display server"
  # The wayland/xorg toggle is the marker file set-display-server manages.
  # Only a fresh install applies the release-file choice; repair preserves
  # whatever the user last selected with set-display-server.
  local marker=/var/lib/steamos-streaming/display-server-wayland
  if [[ "$MODE" != "install" ]]; then
    cmsg "Display server left as configured ($([[ -e "$marker" ]] && echo wayland || echo xorg))"
    return 0
  fi
  mkdir -p /var/lib/steamos-streaming
  if [[ "$DISPLAY_SERVER" == "xorg" ]]; then
    rm -f "$marker"
    cmsg "Display server: Xorg dummy (legacy, per DISPLAY_SERVER=xorg)"
  else
    touch "$marker"
    cmsg "Display server: wayland (sway headless)"
  fi
}

# Decky Loader + NonSteamLaunchers plugin (INSTALL_DECKY=yes). Mirrors the
# official decky.xyz installer non-interactively: latest stable PluginLoader
# from GitHub, the service file as shipped by current Decky releases. NSL's
# Decky plugin is not in the Decky store; it installs from the repo's main
# branch (upstream ships no pinnable artifacts for either project).
install_decky() {
  [[ "$INSTALL_DECKY" == "yes" ]] || return 0
  CURRENT_PHASE="Installing Decky Loader and NonSteamLaunchers plugin"
  local home=/home/deck hb=/home/deck/homebrew
  sudo -u deck mkdir -p "$hb/services" "$hb/plugins" "$home/.local/share/Steam"
  # Decky drives the Steam UI through CEF remote debugging; Steam only
  # enables it when this marker exists in its data directory.
  sudo -u deck touch "$home/.local/share/Steam/.cef-enable-remote-debugging"
  if [[ ! -x "$hb/services/PluginLoader" || "$MODE" == "install" ]]; then
    fetch_and_deploy_gh_release "PluginLoader" "SteamDeckHomebrew/decky-loader" "singlefile" "latest" "$hb/services" "PluginLoader"
    cat ~/.PluginLoader >"$hb/services/.loader.version" 2>/dev/null || true
    chown -R deck:deck "$hb/services"
  fi
  cat >/etc/systemd/system/plugin_loader.service <<PLUGIN_LOADER_UNIT_EOF
[Unit]
Description=SteamDeck Plugin Loader
After=network.target
[Service]
Type=simple
User=root
Restart=always
KillMode=process
TimeoutStopSec=15
ExecStart=${hb}/services/PluginLoader
WorkingDirectory=${hb}/services
Environment=UNPRIVILEGED_PATH=${hb}
Environment=PRIVILEGED_PATH=${hb}
Environment=LOG_LEVEL=INFO
[Install]
WantedBy=multi-user.target
PLUGIN_LOADER_UNIT_EOF
  run systemctl daemon-reload
  run systemctl enable plugin_loader.service
  if [[ ! -d "$hb/plugins/NonSteamLaunchers" ]]; then
    cmsg "Installing NonSteamLaunchers Decky plugin"
    local tmp=/tmp/nsl-decky.tar.gz
    if curl -fsSL https://github.com/moraroy/NonSteamLaunchersDecky/archive/refs/heads/main.tar.gz -o "$tmp"; then
      mkdir -p "$hb/plugins/NonSteamLaunchers"
      tar -xzf "$tmp" -C "$hb/plugins/NonSteamLaunchers" --strip-components=1
      rm -f "$tmp"
      chown -R deck:deck "$hb/plugins/NonSteamLaunchers"
      cmsg "NonSteamLaunchers plugin installed"
    else
      cwarn "Could not download the NonSteamLaunchers plugin; install it later from Decky"
    fi
  fi
}

# Heroic Games Launcher (INSTALL_HEROIC=yes): latest release via
# fetch_and_deploy_gh_release, extracted AppImage-style (no FUSE needed).
# Native Linux Epic/GOG client - installs games as plain files with no EGL
# directory ACL checks, so exFAT/NTFS game disks work directly.
install_heroic() {
  [[ "$INSTALL_HEROIC" == "yes" ]] || return 0
  CURRENT_PHASE="Installing Heroic Games Launcher"
  local ver
  if [[ -x /opt/heroic/current/heroic && "$MODE" != "install" ]]; then
    cmsg "Heroic already installed"
  else
    fetch_and_deploy_gh_release "heroic" "Heroic-Games-Launcher/HeroicGamesLauncher" "singlefile" "latest" "/opt/heroic" "Heroic-*-linux-x86_64.AppImage"
    ver="$(cat ~/.heroic 2>/dev/null || echo unknown)"
    # Extraction must run from an exec-capable filesystem (/tmp may be a
    # noexec tmpfs in this container); --appimage-extract needs no FUSE.
    rm -rf /opt/heroic/squashfs-root "/opt/heroic/${ver}"
    (cd /opt/heroic && ./heroic --appimage-extract >/dev/null)
    mv /opt/heroic/squashfs-root "/opt/heroic/${ver}"
    ln -sfn "/opt/heroic/${ver}" /opt/heroic/current
    rm -f /opt/heroic/heroic
  fi
  cat >/usr/local/bin/heroic <<'HEROIC_WRAPPER_EOF'
#!/usr/bin/env bash
# Heroic (extracted AppImage): Epic/GOG installs as plain files - no EGL
# DirectoryPreparation ACL check, so exFAT/NTFS game disks work directly.
exec /opt/heroic/current/heroic --no-sandbox "$@"
HEROIC_WRAPPER_EOF
  chmod 0755 /usr/local/bin/heroic
  # Reachable under lxc-attach's minimal PATH ("pct exec CTID -- heroic").
  ln -sf /usr/local/bin/heroic /usr/bin/heroic
  cat >/usr/share/applications/heroic.desktop <<'HEROIC_DESKTOP_EOF'
[Desktop Entry]
Name=Heroic Games Launcher
Exec=/usr/local/bin/heroic
Icon=/opt/heroic/current/heroic.png
Type=Application
Categories=Game;
HEROIC_DESKTOP_EOF
  chown -R deck:deck /opt/heroic
  cmsg "Heroic Games Launcher installed"
}

# Game library mount: the host delivers the raw games disk to a hidden path
# and this unit serves /games from it - plain bind on POSIX filesystems,
# fuse_xattrs on exFAT/NTFS/vfat. Wine (GE-Proton) persists Windows ACLs as
# user.wine.sd xattrs; without them Epic-style directory checks fail
# (DP-07). fuse_xattrs stores xattrs in hidden .xattr sidecar files on the
# same disk and fakes chmod/chown success; it is built from a pinned
# upstream commit only when the games disk actually needs it.
FUSE_XATTRS_REPO="https://github.com/fbarriga/fuse_xattrs"
FUSE_XATTRS_COMMIT="d1e304659a2381e04c715afc6425c66b663f277d"

install_games_mount() {
  CURRENT_PHASE="Installing game library mount"
  cat >"${LIB_DIR}/mount-game-library" <<'MOUNT_GAMELIB_EOF'
#!/usr/bin/env bash
# SteamOS Streaming LXC - mount the game library at /games.
#
# The host delivers the raw games disk to a hidden path (RAW). On POSIX
# filesystems /games is a plain bind of it. On exFAT/NTFS/vfat the view is
# served by fuse_xattrs (patched: chmod/chown fake success): GE-Proton
# persists Windows ACLs as user.wine.sd xattrs, and Epic-style directory
# checks (DP-07) fail unless the xattr write-and-readback works - the shim
# stores xattrs in hidden .xattr sidecar files on the same disk.
#
# Runs from steamos-games-mount.service (Restart=always): a crashed FUSE
# daemon is remounted in place, no container restart needed.
set -euo pipefail
RAW=/var/lib/steamos-streaming/.games-raw
MNT=/games

case "${1:-run}" in
run)
  mountpoint -q "$RAW" || exit 0
  # Clear leftovers from a previous instance FIRST: a dead FUSE endpoint
  # makes even stat/mkdir on the path fail with ENOTCONN. Peel every
  # stacked layer (gamelib binds on top, then the mount itself).
  umount -l "$MNT/SteamLibrary/steamapps/compatdata" 2>/dev/null || true
  umount -l "$MNT/SteamLibrary/steamapps/shadercache" 2>/dev/null || true
  # mountpoint(1) stats the path, which itself fails ENOTCONN on a dead
  # FUSE endpoint - detect via the mount table (findmnt) instead.
  while findmnt -n "$MNT" >/dev/null 2>&1; do
    umount -l "$MNT" 2>/dev/null || break
  done
  mkdir -p "$MNT"
  fstype="$(findmnt -no FSTYPE "$RAW")"
  case "$fstype" in
  exfat | vfat | msdos | ntfs | ntfs3 | fuseblk)
    # Foreground: the service supervises the daemon and remounts on crash.
    exec /usr/local/sbin/fuse_xattrs -f -o allow_other "$RAW" "$MNT"
    ;;
  *)
    mount --bind "$RAW" "$MNT"
    # Keep the unit alive so ordering and restart semantics stay uniform.
    exec sleep infinity
    ;;
  esac
  ;;
wait)
  # ExecStartPost: block dependents until /games is actually mounted AND
  # answering (a dead endpoint is still listed in the mount table).
  mountpoint -q "$RAW" || exit 0
  for _ in $(seq 1 40); do
    mountpoint -q "$MNT" && exit 0
    sleep 0.5
  done
  echo "mount-game-library: /games did not come up" >&2
  exit 1
  ;;
*)
  echo "usage: mount-game-library [run|wait]" >&2
  exit 2
  ;;
esac
MOUNT_GAMELIB_EOF
  chmod 0755 "${LIB_DIR}/mount-game-library"

  cat >/etc/systemd/system/steamos-games-mount.service <<'GAMES_MOUNT_UNIT_EOF'
[Unit]
Description=SteamOS Streaming game library mount (/games, xattr shim on exFAT/NTFS)
# Only when the host delivers a raw games disk to the hidden path.
ConditionPathIsMountPoint=/var/lib/steamos-streaming/.games-raw
After=local-fs.target
# The library prep (binds) and the session stack build on /games.
Before=steamos-gamelib.service steamos-streaming.target

[Service]
Type=simple
ExecStart=/usr/local/lib/steamos-streaming/mount-game-library run
# Dependents must not start before the mount is actually up; also refresh
# the gamelib binds after a remount (no-op when it is not active yet).
ExecStartPost=/usr/local/lib/steamos-streaming/mount-game-library wait
ExecStartPost=-/usr/bin/systemctl --no-block try-restart steamos-gamelib.service
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
GAMES_MOUNT_UNIT_EOF
  run systemctl enable steamos-games-mount.service

  local raw=/var/lib/steamos-streaming/.games-raw fstype src
  if ! mountpoint -q "$raw"; then
    cmsg "No games disk delivered; /games mount unit stays idle"
    return 0
  fi
  fstype="$(findmnt -no FSTYPE "$raw" 2>/dev/null || true)"
  case "$fstype" in
  exfat | vfat | msdos | ntfs | ntfs3 | fuseblk) ;;
  *)
    cmsg "Games disk is ${fstype:-unknown}: plain bind, no FUSE shim needed"
    run systemctl restart steamos-games-mount.service
    return 0
    ;;
  esac
  if [[ -x /usr/local/sbin/fuse_xattrs ]]; then
    cmsg "fuse_xattrs already present"
  else
    CURRENT_PHASE="Building fuse_xattrs (xattr shim for ${fstype} game disk)"
    cmsg "Games disk is ${fstype}: building the fuse_xattrs xattr shim"
    run pacman -S --noconfirm --needed fuse2 gcc make cmake pkgconf
    # Build under /root: /tmp can be a noexec tmpfs and cmake's
    # try-compile executes test binaries.
    src=/root/fuse_xattrs-src
    rm -rf "$src"
    run git clone "$FUSE_XATTRS_REPO" "$src"
    run git -C "$src" checkout "$FUSE_XATTRS_COMMIT"
    sed -i 's|res = chmod(_path, mode);|res = 0; (void) mode; /* faked success: FAT-family source rejects chmod */|' "$src/passthrough.c"
    sed -i 's|res = lchown(_path, uid, gid);|res = 0; (void) uid; (void) gid; /* faked success */|' "$src/passthrough.c"
    if ! grep -q "faked success" "$src/passthrough.c"; then
      cerr "fuse_xattrs chmod patch did not apply (upstream changed?)"
      exit 1
    fi
    (cd "$src" && run cmake . && run make)
    install -m 0755 "$src/fuse_xattrs" /usr/local/sbin/fuse_xattrs
    rm -rf "$src"
    cmsg "fuse_xattrs built and installed"
  fi
  run systemctl restart steamos-games-mount.service
}

# NSL's "Move to SD Card" only recognizes real SD readers (mmcblk*); teach it
# to use the appliance game library. Runs whenever the plugin is present
# (also for manually installed NSL); plugin self-updates overwrite the patch,
# a repair reapplies it. Note: moving Wine prefixes to an exFAT/NTFS /games
# fails by design (no symlink support) - rsync aborts before deleting data.
patch_nsl_sd_path() {
  local nsl=/home/deck/homebrew/plugins/NonSteamLaunchers/NonSteamLaunchers.sh
  [[ -f "$nsl" ]] || return 0
  grep -q 'mountpoint -q /games' "$nsl" && return 0
  sed -i '/^    local sd_mount$/a\
\
    # SteamOS Streaming LXC: the appliance /games library stands in for\
    # the Deck SD card. (Reapplied by repair; plugin updates overwrite it.)\
    if mountpoint -q /games 2>/dev/null; then\
        echo /games\
        return\
    fi' "$nsl"
  cmsg "NonSteamLaunchers: /games taught to Move-to-SD detection"
}

start_stack() {
  CURRENT_PHASE="Starting streaming stack"
  # Clear any start-limit state from earlier crash loops (relevant on repair).
  systemctl reset-failed >>"$LOG_FILE" 2>&1 || true
  run systemctl start steamos-streaming.target
  cmsg "Streaming stack started (steamos-streaming.target)"
}

# ------------------------------------------------------------------------------
cmsg "Container installer starting (mode: ${MODE})"
if [[ "$MODE" == "install" ]]; then
  init_pacman
  system_update
  install_packages
else
  # init_pacman is idempotent; repair needs it too (sandbox off, multilib,
  # keyring) so it can complete a partially installed container.
  init_pacman
  verify_packages
fi
create_user
enable_linger
write_display_helpers
write_pipewire_sink
write_gaming_mode_wrapper
configure_tmpfs_limits
write_steamos_shims
install_sunshine
write_sunshine_config
configure_network_manager
write_udev_support
write_systemd_units
write_maintenance_scripts
install_games_mount
install_decky
install_heroic
patch_nsl_sd_path
configure_ssh
record_versions
validate_acceleration
apply_display_server_choice
motd_ssh
customize
cleanup_lxc
start_stack
touch "${LOG_DIR}/.install-ok"
cmsg "Container installation completed (mode: ${MODE})"

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: pabb85
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://ubuntu.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# This desktop needs a PRIVILEGED container: it relies on AppArmor unconfined +
# /sys rw so the container's own udevd can drive console input hotplug — an
# unprivileged container can't do that and you'd get a black screen at login.
# A privileged CT maps root 1:1 (uid_map "0 0 ..."); an unprivileged one maps
# root to a high host uid ("0 100000 ..."). Bail early with a clear message.
UID_MAP_HOST="$(awk 'NR==1{print $2}' /proc/self/uid_map 2>/dev/null)"
if [ -n "$UID_MAP_HOST" ] && [ "$UID_MAP_HOST" != "0" ]; then
  msg_error "This script requires a PRIVILEGED container (var_unprivileged=0)."
  msg_error "Re-create it with Advanced settings -> Container Type: Privileged."
  exit 1
fi

# Optional overrides (set via env at launch, e.g. CTUSER=alice CTLOCALE=en_GB.UTF-8)
DESK_USER="${CTUSER:-desktop}"
DESK_LOCALE="${CTLOCALE:-en_US.UTF-8}"
DESK_KEYMAP="${CTKEYMAP:-us}"

msg_info "Configuring locale (${DESK_LOCALE}) and keyboard (${DESK_KEYMAP})"
$STD apt-get install -y locales
grep -qE "^[# ]*${DESK_LOCALE} " /etc/locale.gen || echo "${DESK_LOCALE} UTF-8" >>/etc/locale.gen
sed -i -E "s|^# *(${DESK_LOCALE} )|\1|" /etc/locale.gen
$STD locale-gen
$STD update-locale LANG="$DESK_LOCALE"
cat >/etc/default/keyboard <<EOF
XKBLAYOUT="$DESK_KEYMAP"
XKBMODEL="pc105"
EOF
msg_ok "Configured locale and keyboard"

# Preseed LightDM (not GDM/SDDM): their greeter->session handover needs a logind
# VT switch that LXC can't do, so they freeze; LightDM does no VT handover.
echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections

msg_info "Installing KDE Plasma + LightDM (this can take a while)"
$STD apt-get install -y \
  kde-plasma-desktop \
  lightdm \
  xserver-xorg \
  x11-xserver-utils \
  mesa-utils \
  mesa-va-drivers \
  vainfo
# The Plasma X11 session package name varies by release (plasma-session-x11 on
# newer Ubuntu, plasma-workspace-x11 elsewhere); install whichever exists.
for p in plasma-session-x11 plasma-workspace-x11 kwin-x11; do
  $STD apt-get install -y "$p" || true
done
# Force LightDM as the DM (kde-plasma-desktop may pull sddm). DMs have no [Install]
# section — select via default-display-manager + the service symlink.
echo "/usr/sbin/lightdm" >/etc/X11/default-display-manager
systemctl disable --now sddm >/dev/null 2>&1 || true
ln -sf /usr/lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
msg_ok "Installed KDE Plasma + LightDM"

msg_info "Enabling in-container udevd (console input hotplug)"
# Xorg only reacts to processed UDEV events, and the host udevd's output doesn't
# cross the container netns — so input needs the container's own udevd. Pairs with
# 'lxc.mount.auto: sys:rw' added to the CT config by the ct script.
systemctl unmask systemd-udevd systemd-udevd-control.socket systemd-udevd-kernel.socket >/dev/null 2>&1 || true
$STD systemctl enable systemd-udevd
msg_ok "Enabled in-container udevd"

msg_info "Writing LightDM configuration"
SESSION=plasmax11
[ -f /usr/share/xsessions/plasmax11.desktop ] || SESSION=plasma
cat >/etc/lightdm/lightdm.conf <<EOF
[LightDM]
# MUST be under [LightDM] — ignored under [Seat:*] (greeter waits forever -> black).
logind-check-graphical=false

[Seat:*]
# -novtswitch: LightDM must not attempt a VT handover inside the container.
xserver-command=X vt7 -novtswitch
user-session=${SESSION}
EOF
msg_ok "Wrote LightDM configuration"

msg_info "Installing DRM-hotplug display handler"
# One root service for both phases: connecting a monitor AFTER a headless boot
# brings the greeter up, and re-applies the layout in-session (KVM-switch
# recovery). Generic: enables whatever outputs are connected, left-to-right.
cat >/usr/local/bin/display-fix <<'EOF'
#!/bin/sh
# Re-apply a display layout on DRM hotplug, at the LightDM greeter or in-session.
LOG=/var/log/display-fix.log
log() { echo "$(date '+%F %T') $*" >>"$LOG" 2>/dev/null; }

DISPLAY=""; XAUTHORITY=""; PHASE=""

# (a) If a user session is up, target it — pull its X env from plasmashell.
P=$(pgrep -x plasmashell | head -1)
if [ -n "$P" ]; then
  export $(tr '\0' '\n' < "/proc/$P/environ" 2>/dev/null | grep -E '^(DISPLAY|XAUTHORITY)=')
  PHASE=session
fi

# (b) Otherwise (greeter): target the greeter's Xorg via its -auth + display.
if [ -z "${XAUTHORITY:-}" ]; then
  for pid in $(pgrep -x Xorg 2>/dev/null) $(pgrep -x X 2>/dev/null); do
    cl=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null) || continue
    d=$(printf '%s\n' "$cl" | grep -m1 -E '^:[0-9]+$')
    a=$(printf '%s\n' "$cl" | awk '/^-auth$/{getline; print; exit}')
    if [ -n "$d" ] && [ -n "$a" ]; then DISPLAY="$d"; XAUTHORITY="$a"; PHASE=greeter; break; fi
  done
fi

[ -n "${DISPLAY:-}" ] || DISPLAY=:0
[ -n "${XAUTHORITY:-}" ] || { log "no X auth found; skip"; exit 0; }
export DISPLAY XAUTHORITY
command -v xrandr >/dev/null 2>&1 || exit 0

# Enable every connected output left-to-right at its preferred mode (first =
# primary); turn disconnected outputs off. No hardcoded names/modes/positions.
connected=$(xrandr 2>/dev/null | awk '/ connected/{print $1}')
[ -n "$connected" ] || { log "no outputs connected; skip"; exit 0; }
log "apply phase=$PHASE display=$DISPLAY outputs=[$connected]"
prev=""
for o in $connected; do
  if [ -z "$prev" ]; then xrandr --output "$o" --auto --pos 0x0 --primary
  else xrandr --output "$o" --auto --right-of "$prev"; fi
  prev="$o"
done
for o in $(xrandr 2>/dev/null | awk '/ disconnected/{print $1}'); do
  xrandr --output "$o" --off 2>/dev/null || true
done
EOF
chmod +x /usr/local/bin/display-fix

cat >/usr/local/bin/display-fix-daemon <<'EOF'
#!/bin/bash
# Watch DRM hotplug; coalesce bursts (2s quiet = settled); re-apply the layout.
udevadm monitor --udev --subsystem-match=drm 2>/dev/null | \
while read -r _; do
  while read -t 2 -r _; do :; done   # drain the hotplug burst
  /usr/local/bin/display-fix
  while read -t 2 -r _; do :; done   # absorb events from our own xrandr (no self-loop)
done
EOF
chmod +x /usr/local/bin/display-fix-daemon

cat >/etc/systemd/system/display-recover.service <<'EOF'
[Unit]
Description=Apply display layout on DRM hotplug (greeter + session: headless-connect recovery)
After=display-manager.service

[Service]
ExecStart=/usr/local/bin/display-fix-daemon
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl enable display-recover.service
msg_ok "Installed DRM-hotplug display handler"

msg_info "Creating desktop user '${DESK_USER}'"
if ! id "$DESK_USER" >/dev/null 2>&1; then
  $STD adduser --disabled-password --gecos "" "$DESK_USER"
  usermod -aG sudo "$DESK_USER"
fi
DESK_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)"
echo "${DESK_USER}:${DESK_PASS}" | chpasswd
{
  echo "Ubuntu-Desktop-GPU Credentials"
  echo "Console/SSH user: ${DESK_USER}"
  echo "Password: ${DESK_PASS}"
} >/root/ubuntu-desktop-gpu.creds
chmod 600 /root/ubuntu-desktop-gpu.creds
msg_ok "Created desktop user '${DESK_USER}' (password saved to /root/ubuntu-desktop-gpu.creds)"

motd_ssh
customize
cleanup_lxc

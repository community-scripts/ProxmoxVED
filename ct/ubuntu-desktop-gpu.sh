#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/pabb85/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: pabb85
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://ubuntu.com/

APP="Ubuntu-Desktop-GPU"
var_tags="${var_tags:-os;desktop}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-32}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-26.04}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-0}"
var_gpu="${var_gpu:-yes}"

# App-specific variables (not in build.func whitelist).
# Export so they survive lxc-attach into the install script. Filled by the
# whiptail prompt below, or supplied up front via env for unattended installs.
export var_desktop_user="${var_desktop_user:-}"
export var_desktop_pass="${var_desktop_pass:-}"
export var_desktop_pve_link="${var_desktop_pve_link:-}"
export var_pve_url="${var_pve_url:-}"

# Run the host-side helper steps under C.UTF-8 so build.func's `pct exec` calls
# don't emit "cannot change locale" warnings when the host's LC_ALL (e.g.
# en_US.UTF-8) isn't yet generated in the fresh container. The desktop's real
# locale is set later in the install script.
export LC_ALL=C.UTF-8

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/lightdm/lightdm.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt -y full-upgrade
  msg_ok "Updated ${APP} LXC"
  exit
}

# var_gpu only passes /dev/dri through. A desktop on the host's physical console
# also needs the framebuffer, the input devices, the X TTYs and sound, plus
# AppArmor unconfined + /sys rw so the container's own udevd can drive input
# hotplug. Append those once the CT exists, then reboot to load the new config.
function configure_console_passthrough() {
  local conf="/etc/pve/lxc/${CTID}.conf"
  grep -q "desktop-on-console passthrough" "$conf" 2>/dev/null && return 0
  msg_info "Adding console + desktop device passthrough"
  cat >>"$conf" <<EOF

# --- desktop-on-console passthrough (${APP}) ---
lxc.apparmor.profile: unconfined
lxc.mount.auto: sys:rw
# framebuffer
lxc.cgroup2.devices.allow: c 29:* rwm
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file
# input devices (keyboard/mouse; whole dir so hotplug / KVM re-plugs work)
lxc.cgroup2.devices.allow: c 13:* rwm
lxc.mount.entry: /dev/input dev/input none bind,optional,create=dir
# TTYs (X runs on vt7)
lxc.cgroup2.devices.allow: c 4:* rwm
lxc.mount.entry: /dev/tty0 dev/tty0 none bind,optional,create=file
lxc.mount.entry: /dev/tty7 dev/tty7 none bind,optional,create=file
# sound
lxc.cgroup2.devices.allow: c 116:* rwm
lxc.mount.entry: /dev/snd dev/snd none bind,optional,create=dir
EOF
  msg_ok "Added console + desktop device passthrough"
  msg_info "Rebooting ${APP} to apply passthrough"
  pct reboot "$CTID"
  msg_ok "Rebooted ${APP}"
}

# Ask (host-side, via whiptail) for the desktop login user and password before the
# container is built. Skipped for any value already supplied via env. A blank
# password is auto-generated here and shown in the final message (no creds file).
# The values are exported so they cross lxc-attach into the install script.
DESKTOP_PASS_GENERATED=0
function prompt_desktop_credentials() {
  if [[ -z "$var_desktop_user" ]]; then
    var_desktop_user="$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DESKTOP USER" \
      --inputbox "Username for the desktop login:" 10 60 "desktop" 3>&1 1>&2 2>&3)" || exit_script
    [[ -z "$var_desktop_user" ]] && var_desktop_user="desktop"
  fi

  if [[ -z "$var_desktop_pass" ]]; then
    local _msg="Password for '${var_desktop_user}'\n\n(leave blank to auto-generate a strong password):"
    while true; do
      local _p1 _p2
      _p1="$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DESKTOP PASSWORD" \
        --passwordbox "$_msg" 11 60 3>&1 1>&2 2>&3)" || exit_script
      if [[ -z "$_p1" ]]; then
        var_desktop_pass="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)"
        DESKTOP_PASS_GENERATED=1
        break
      fi
      _p2="$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CONFIRM PASSWORD" \
        --passwordbox "Re-enter the password for '${var_desktop_user}':" 10 60 3>&1 1>&2 2>&3)" || exit_script
      if [[ "$_p1" == "$_p2" ]]; then
        var_desktop_pass="$_p1"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "MISMATCH" \
        --msgbox "Passwords did not match — please try again." 8 50
    done
  fi

  export var_desktop_user var_desktop_pass
}

# Optionally drop a desktop shortcut to this node's Proxmox VE web UI. Asked
# host-side; the URL is auto-detected from the node's primary IP (override by
# pre-setting var_pve_url, e.g. to use a hostname). Honour env for unattended use.
function prompt_pve_link() {
  if [[ -z "$var_desktop_pve_link" ]]; then
    if whiptail --backtitle "Proxmox VE Helper Scripts" --title "PROXMOX VE SHORTCUT" \
      --yesno "Add a shortcut to the Proxmox VE web interface on the desktop?" 9 64; then
      var_desktop_pve_link="yes"
    else
      var_desktop_pve_link="no"
    fi
  fi
  if [[ "$var_desktop_pve_link" == "yes" && -z "$var_pve_url" ]]; then
    local _ip
    _ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
    [[ -z "$_ip" ]] && _ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    var_pve_url="${_ip:+https://${_ip}:8006}"
  fi
  export var_desktop_pve_link var_pve_url
}

start
prompt_desktop_credentials
prompt_pve_link
build_container
configure_console_passthrough
description

msg_ok "Completed successfully!\n"
msg_custom "🖥️" "${GN}" "${APP} setup has been successfully initialized!"
echo -e "${INFO}${YW} Connect a monitor and keyboard to this Proxmox host — the LightDM login${CL}"
echo -e "${INFO}${YW} appears on the physical console.${CL}"
echo -e "${INFO}${YW} Desktop login user: ${BGN}${var_desktop_user}${CL}"
if [[ "$DESKTOP_PASS_GENERATED" == "1" ]]; then
  echo -e "${INFO}${YW} Auto-generated password: ${BGN}${var_desktop_pass}${CL}"
fi

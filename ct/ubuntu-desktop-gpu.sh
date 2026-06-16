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
var_unprivileged="${var_unprivileged:-0}"
var_gpu="${var_gpu:-yes}"

# App-specific variables (not in build.func whitelist).
# Export so they survive lxc-attach into the install script. Filled by the
# whiptail prompt below, or supplied up front via env for unattended installs.
export var_desktop_user="${var_desktop_user:-}"
export var_desktop_pass="${var_desktop_pass:-}"

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
  $STD apt-get update
  $STD apt-get -y dist-upgrade
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
# password means the install auto-generates a strong one and saves it to the creds
# file. The values are exported so they cross lxc-attach into the install script.
function prompt_desktop_credentials() {
  if [[ -z "$var_desktop_user" ]]; then
    var_desktop_user="$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DESKTOP USER" \
      --inputbox "Username for the desktop login:" 10 60 "desktop" 3>&1 1>&2 2>&3)" || exit_script
    [[ -z "$var_desktop_user" ]] && var_desktop_user="desktop"
  fi

  if [[ -z "$var_desktop_pass" ]]; then
    while true; do
      local _p1 _p2
      _p1="$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DESKTOP PASSWORD" \
        --passwordbox "Password for '${var_desktop_user}'\n\n(leave blank to auto-generate a strong password):" 11 60 3>&1 1>&2 2>&3)" || exit_script
      if [[ -z "$_p1" ]]; then
        var_desktop_pass=""
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

start
prompt_desktop_credentials
build_container
configure_console_passthrough
description

msg_ok "Completed successfully!\n"
msg_custom "🖥️" "${GN}" "${APP} setup has been successfully initialized!"
echo -e "${INFO}${YW} Switch the host's monitor/keyboard (KVM) to this Proxmox node — the LightDM${CL}"
echo -e "${INFO}${YW} login appears on the physical console.${CL}"
echo -e "${INFO}${YW} Desktop login user: ${BGN}${var_desktop_user}${CL}"
echo -e "${INFO}${YW} If you left the password blank it was auto-generated and saved to${CL}"
echo -e "${INFO}${YW} /root/ubuntu-desktop-gpu.creds inside the container.${CL}"

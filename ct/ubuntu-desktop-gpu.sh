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

start
build_container
configure_console_passthrough
description

msg_ok "Completed successfully!\n"
msg_custom "🖥️" "${GN}" "${APP} setup has been successfully initialized!"
echo -e "${INFO}${YW} Switch the host's monitor/keyboard (KVM) to this Proxmox node — the LightDM${CL}"
echo -e "${INFO}${YW} login appears on the physical console. Desktop user + password are saved in${CL}"
echo -e "${INFO}${YW} /root/ubuntu-desktop-gpu.creds inside the container.${CL}"

#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://obsproject.com/

APP="OBS-Studio"
var_tags="${var_tags:-media;streaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
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

  if ! command -v obs &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Debian packages"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Debian packages"

  msg_info "Checking OBS Studio version"
  obs_version=$(dpkg-query -W -f='${Version}' obs-studio 2>/dev/null || echo "unknown")
  msg_ok "OBS Studio: ${obs_version}"

  msg_ok "OBS Studio is managed via Debian apt repository."
  msg_info "Updates are included in 'apt upgrade' above."
  exit
}

start
build_container
description

if [[ -e /dev/video0 ]]; then
  msg_info "Configuring capture device passthrough"
  LXC_CONF="/etc/pve/lxc/${CTID}.conf"
  cat <<EOF >>"$LXC_CONF"
lxc.cgroup2.devices.allow: c 81:* rwm
lxc.mount.entry: /dev/video0 dev/video0 none bind,optional,create=file 0 0
EOF
  msg_ok "Capture device /dev/video0 configured"
else
  msg_warn "/dev/video0 not found on host — no capture card detected"
fi

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Web Access:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://<IP>:5800/vnc.html${CL}"
echo -e "${INFO}${YW} VNC Access (macOS Screen Sharing / Remote Desktop):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}vnc://<IP>:5900${CL}"
echo -e "${INFO}${YW} Password: ${GN}obsstudio${CL} (change with: x11vnc -storepasswd)"
echo -e "${INFO}${YW} Capture Device: ${GN}/dev/video0${CL}"
echo -e "${INFO}${YW} GPU Device: ${GN}/dev/dri${CL}"
echo -e "${INFO}${YW} QuickSync: Run ${GN}vainfo${YW} inside container to verify${CL}"
echo -e "${INFO}${YW} If vainfo shows VAEntrypointEncSlice, select 'QuickSync H.264' in OBS${CL}"

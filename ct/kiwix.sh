#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tewalds
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

APP="Kiwix"
var_tags="${var_tags:-documentation;offline}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  CURRENT_VER=$(/usr/local/bin/kiwix-serve --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)

  fetch_and_deploy_archive "https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-x86_64.tar.gz" /usr/local/bin/

  NEW_VER=$(/usr/local/bin/kiwix-serve --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)

  if [[ "$CURRENT_VER" == "$NEW_VER" ]]; then
    msg_ok "Already on latest version: $CURRENT_VER"
    exit
  fi

  systemctl restart kiwix-serve
  msg_ok "Updated from $CURRENT_VER to $NEW_VER!"
  exit
}

start
build_container

msg_info "Validating ZIM directory."
if [[ -z "${ZIM_DIR:-}" ]]; then
  msg_error "ZIM_DIR cannot be empty. Please run with ZIM_DIR=/path/to/zims"
  exit 1
fi
if [[ ! -d "$ZIM_DIR" ]]; then
  msg_error "Directory '$ZIM_DIR' does not exist."
  exit 1
fi
if ! ls "${ZIM_DIR}"/*.zim >/dev/null 2>&1; then
  msg_error "No .zim files found in '$ZIM_DIR'"
  exit 1
fi
msg_ok "Using ZIM directory: ${ZIM_DIR}"

msg_info "Configuring Bind Mount"

if pct set $CTID -features mountidmap=1 2>/dev/null; then
  msg_info "Enabled ID-mapped mounts (ownership preserved)"
  pct set $CTID -mp0 "$ZIM_DIR,mp=/data,ro=1"
  msg_ok "Bind Mount Configured (read-only, ownership preserved)"
else
  msg_info "ID-mapped mounts not available, using standard mount"
  msg_info "Note: Files will appear as nobody:nogroup inside container"
  msg_info "Ensure ZIM files are world-readable: chmod -R a+rX ${ZIM_DIR}"
  pct set $CTID -mp0 "$ZIM_DIR,mp=/data"
  msg_ok "Bind Mount Configured (read-write mount, read-only service)"
fi

msg_info "Setting Container Options"
pct set $CTID --onboot 1
msg_ok "Container Options Set"

msg_ok "Completed Successfully!\n"
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo -e "${TAB}${GATEWAY}${BGN}Web Interface:${CL} ${BL}http://${IP}:8080${CL}"
echo -e "${TAB}${INFO}${BGN}ZIM Directory:${CL} ${ZIM_DIR} ${DGN}→${CL} ${BGN}/data${CL}"

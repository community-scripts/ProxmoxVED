#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Vadim Yuzi (yuzi-co)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/yuzi-co/fwupd-webui

APP="fwupd-webui"
var_tags="${var_tags:-hardware;monitoring;firmware}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"

# Privileged, deliberately, and the only setting here that is not a default.
#
# Enumerating firmware means issuing NVMe admin commands and SCSI generic ioctls
# against the host's disks. Measured on real hardware: a privileged container
# finds 8 devices, and 2 is the ceiling for everything short of it --
# --cap-add=ALL with seccomp and AppArmor unconfined still reaches only 2.
# Explicit device-cgroup rules make it worse, returning 0.
#
# build.func already emits the device access a privileged container needs, so no
# custom LXC configuration is added by this script.
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/fwupd-webui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop fwupd-webui
  msg_ok "Stopped Service"

  msg_info "Updating $APP"
  cd /opt/fwupd-webui/src-checkout || exit
  $STD git fetch origin main
  $STD git checkout FETCH_HEAD
  $STD /opt/fwupd-webui/venv/bin/pip install --upgrade /opt/fwupd-webui/src-checkout
  msg_ok "Updated $APP"

  msg_info "Starting Service"
  systemctl start fwupd-webui
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8099${CL}"
echo -e "${INFO}${YW}Firmware flashing is disabled by default. Enable it in${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/etc/fwupd-webui/env${CL}"

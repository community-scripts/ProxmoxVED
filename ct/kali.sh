#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Otto Zoeke (FairTradeOrange)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.kali.org/


APP="Kali"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-kali}"
var_version="${var_version:-current}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

# new generic Backend-Interface for download of LinuxContainers
# see: https://images.linuxcontainers.org/images/ || https://jenkins.linuxcontainers.org/
var_template_source="${var_template_source:-linuxcontainers}"
var_template_variant="${var_template_variant:-default}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Kali Linux LXC"
  $STD apt update
  $STD apt full-upgrade -y
  msg_ok "Updated Kali Linux LXC"
  exit
}

start
build_container
description

msg_ok "Completed successfully!"
msg_custom "🚀" "${GN}" "${APP} setup has been successfully initialized!" No newline at end of file
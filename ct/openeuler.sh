#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.openeuler.org/

# NOTE: openEuler has a PVE compatibility issue
# PVE detects openEuler templates as ostype 'centos', but the templates ship
# without /etc/redhat-release, so PVE's post_create_hook aborts pct create.
# build.func patches the cached template once (injects /etc/redhat-release)
# right before pct create, see template_patch step in build_container().

APP="openEuler"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-openeuler}"
var_version="${var_version:-25.03}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/1757}"

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
  msg_info "Updating OpenEuler LXC"
  $STD dnf -y upgrade
  msg_ok "Updated OpenEuler LXC"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
msg_custom "🚀" "${GN}" "${APP} setup has been successfully initialized!"

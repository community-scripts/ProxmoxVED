#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: nzbfast (nzbfast)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nzbfast/nzbfast

APP="nzbfast"
var_tags="${var_tags:-usenet;downloader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-yes}" # unset = ask the user; the release ships a
# linux-arm64 tarball and the script selects it, but nobody has run the result
# on arm64 yet, so this stays unset rather than claiming a verification.
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/nzbfast ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nzbfast" "nzbfast/nzbfast"; then
    msg_info "Stopping Service"
    systemctl stop nzbfast
    msg_ok "Stopped Service"

    # Settings, the API key, the queue and the index live in
    # /opt/nzbfast_data, so a clean replace of the program directory keeps
    # every one of them. Nothing below touches that directory.
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nzbfast" "nzbfast/nzbfast" "prebuild" "latest" "/opt/nzbfast" "nzbfast-*-linux-$(arch_resolve x64 arm64).tar.gz"

    # Same wrapper-directory flattening the install does - see the comment
    # there. CLEAN_INSTALL empties /opt/nzbfast first, so this runs on the
    # freshly unpacked tree every update.
    find /opt/nzbfast -name '._*' -delete
    if [[ ! -f /opt/nzbfast/nzbfast ]]; then
      nzbfast_wrapper="$(find /opt/nzbfast -mindepth 1 -maxdepth 1 -type d -name 'nzbfast-*' -print -quit)"
      if [[ -n "$nzbfast_wrapper" ]]; then
        mv "$nzbfast_wrapper"/* /opt/nzbfast/
        rmdir "$nzbfast_wrapper"
      fi
    fi
    chmod +x /opt/nzbfast/nzbfast

    msg_info "Starting Service"
    systemctl start nzbfast
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:6789${CL}"

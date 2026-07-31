#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://kanidm.com/

APP="Kanidm"
var_tags="${var_tags:-identity;authentication;sso}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/kanidm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "kanidm" "kanidm/kanidm"; then
    msg_info "Stopping Service"
    systemctl stop kanidm
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /etc/kanidm/server.toml /opt/kanidm-server.toml.bak
    [[ -f /var/lib/kanidm/kanidm.db ]] && cp /var/lib/kanidm/kanidm.db /opt/kanidm-kanidm.db.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "kanidm" "kanidm/kanidm" "tarball"

    setup_rust

    msg_info "Building Kanidm Server (Patience)"
    cd /opt/kanidm
    export KANIDM_BUILD_PROFILE=release_linux
    $STD cargo build --release --locked --bin kanidmd
    install -m 0755 target/release/kanidmd /usr/local/sbin/kanidmd
    mkdir -p /usr/share/kanidm/ui/hpkg
    cp -r server/core/static/. /usr/share/kanidm/ui/hpkg/
    msg_ok "Built Kanidm Server"

    msg_info "Restoring Data"
    cp /opt/kanidm-server.toml.bak /etc/kanidm/server.toml
    [[ -f /opt/kanidm-kanidm.db.bak ]] && cp /opt/kanidm-kanidm.db.bak /var/lib/kanidm/kanidm.db
    rm -f /opt/kanidm-server.toml.bak /opt/kanidm-kanidm.db.bak
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start kanidm
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
echo -e "${GATEWAY}${BGN}https://${IP}:8443${CL}"

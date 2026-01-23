#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/orhun/rustypaste

APP="Alpine-RustyPaste"
var_tags="${var_tags:-alpine;pastebin;storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/rustypaste/rustypaste ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rustypaste" "orhun/rustypaste"; then
    msg_info "Stopping Services"
    rc-service rustypaste stop
    msg_ok "Stopped Services"

    msg_info "Creating Backup"
    tar -czf "/opt/rustypaste_backup_$(date +%F).tar.gz" /opt/rustypaste/upload 2>/dev/null || true
    cp /opt/rustypaste/config.toml /tmp/rustypaste_config.toml.bak
    msg_ok "Backup Created"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rustypaste" "orhun/rustypaste" "prebuild" "latest" "/opt/rustypaste" "*x86_64-unknown-linux-musl.tar.gz"


    msg_info "Updating RustyPaste"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rustypaste" "orhun/rustypaste" "prebuild" "latest" "/opt/rustypaste" "*x86_64-unknown-linux-musl.tar.gz"
    mv /tmp/rustypaste_config.toml.bak /opt/rustypaste/config.toml
    msg_ok "Updated RustyPaste"

    msg_info "Starting Services"
    rc-service rustypaste start
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi

  if check_for_gh_release "rustypaste-cli" "orhun/rustypaste-cli"; then
    msg_info "Updating RustyPaste CLI"
    fetch_and_deploy_gh_release "rustypaste-cli" "orhun/rustypaste-cli" "prebuild" "latest" "/usr/local/bin" "*x86_64-unknown-linux-musl.tar.gz"
    msg_ok "Updated RustyPaste CLI"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"

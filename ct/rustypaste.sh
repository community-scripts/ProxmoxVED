#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: GoldenSpringness
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/orhun/rustypaste

APP="rustypaste"
var_tags="${var_tags:-pastebin;storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-20}"
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

    if [[ ! -f "/opt/rustypaste/target/release/rustypaste" ]]; then
        msg_error "No rustypaste Installation Found!"
        exit
    fi

    if check_for_gh_release "rustypaste" "orhun/rustypaste"; then
        msg_info "Stopping rustypaste"
        systemctl stop rustypaste
        msg_ok "Stopped rustypaste"

        msg_info "Creating Backup"
        tar -czf "/opt/rustypaste_backup_$(date +%F).tar.gz" "/opt/rustypaste/upload"
        msg_ok "Backup Created"

        CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rustypaste" "orhun/rustypaste" "tarball" "latest" "/opt/rustypaste"

        msg_info "Updating rustypaste"
        cd /opt/rustypaste
        sed -i 's|^address = ".*"|address = "0.0.0.0:8000"|' config.toml
        $STD cargo build --locked --release
        msg_ok "Updated rustypaste"
        
        msg_info "Starting rustypaste"
        systemctl start rustypaste
        msg_ok "Started rustypaste"
        msg_ok "Update Successful"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}rustypaste setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"

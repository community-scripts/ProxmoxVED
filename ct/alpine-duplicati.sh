#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Alpine-Duplicati"
var_tags="${var_tags:-alpine}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.21}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    msg_info "Updating Alpine Packages"
    $STD apk update
    $STD apk upgrade
    msg_ok "Updated Alpine Packages"

    msg_info "Updating Duplicati"
    $STD apk upgrade duplicati
    msg_ok "Updated Duplicati"

    msg_info "Restarting Duplicati"
    $STD rc-service duplicati restart || true
    msg_ok "Restarted Duplicati"

    exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access info will vary based on service config. CLI access likely available. ${CL}"

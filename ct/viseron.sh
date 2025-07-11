#!/usr/bin/env bash
source <(curl -s https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)

APP="Viseron"
var_tags="${var_tags:-nvr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"

variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -f /etc/systemd/system/viseron.service ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_error "To update Viseron, create a new container and transfer your configuration."
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8888${CL}"

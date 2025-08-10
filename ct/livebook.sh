#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: dkuku
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/community-scripts/ProxmoxVE

APP="Livebook"
var_tags="${var_tags:-development}"
var_disk="${var_disk:-4}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /home/livebook ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating ${APP} LXC"
    sudo -u livebook bash << 'EOF'
export HOME=/home/livebook
cd /home/livebook
source ~/.bashrc
mix local.hex --force >/dev/null 2>&1
mix local.rebar --force >/dev/null 2>&1
mix escript.install hex livebook --force >/dev/null 2>&1
EOF
    msg_ok "Updated Successfully"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} Authentication:${CL}"
echo -e "${TAB}${RD}• Token authentication enabled by default${CL}"
echo -e "${TAB}${RD}• Token will be shown in logs: journalctl -u livebook.service${CL}"
echo -e "${TAB}${RD}• Generated token: /data/token.txt${CL}"
echo -e "${TAB}${RD}• Configuration: /data/.env${CL}"

#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: edoardop13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/favonia/cloudflare-ddns

APP="Cloudflare-DDNS"
var_tags=""
var_cpu="1"
var_ram="512"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -f /etc/systemd/system/cloudflare-ddns.service ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_error "We don't provide an update function because the service ${APP} use every time the latest version."
    exit
}

start
build_container
description
msg_ok "Completed Successfully!\n"
echo -e "${APP} setup has been successfully initialized!\n"
echo -e "If you want to update the service go to the container and run the command:\n"
echo -e "sudo nano /etc/systemd/system/cloudflare-ddns.service\n"
echo -e "Update the token or the other environment variables and save the file.\n"
echo -e "Then run the command:\n"
echo -e "sudo systemctl daemon-reload\n"
echo -e "And finally restart the service with:\n"
echo -e "sudo systemctl restart cloudflare-ddns.service"
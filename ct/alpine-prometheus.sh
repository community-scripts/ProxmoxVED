#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://prometheus.io/

APP="Alpine-Prometheus"
var_tags="alpine;monitoring"
var_cpu="1"
var_ram="256"
var_disk="1"
var_os="alpine"
var_version="3.21"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    msg_info "Updating Alpine Packages"
    apk update && apk upgrade
    msg_ok "Updated Alpine Packages"

    msg_info "Updating Prometheus"
    apk upgrade prometheus
    msg_ok "Updated Prometheus"

    msg_info "Restarting Prometheus"
    rc-service prometheus restart
    msg_ok "Restarted Prometheus"
}

start
build_container
description

msg_ok "Completed Successfully!\n"

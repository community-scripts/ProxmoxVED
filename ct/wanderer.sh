#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: rrole
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://wanderer.to

APP="wanderer"
var_tags="traveling; sport"
var_cpu="2"
var_ram="4096"
var_disk="8"
var_os="debian"
var_version="13"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /opt/wanderer/start.sh ]]; then
        msg_error "No wanderer Installation Found!"
        exit
    fi

    if check_for_gh_release "wanderer" "Flomp/wanderer"; then
        msg_info "Stopping wanderer service"
        systemctl stop wanderer-web
        msg_ok "Stopped wanderer service"


        msg_info "Updating wanderer"
        $STD fetch_and_deploy_gh_release "wanderer" "Flomp/wanderer"  "tarball" "latest" "/opt/wanderer/source"
        cd /opt/wanderer/source/db
        $STD go mod tidy
       	$STD go build
        cd /opt/wanderer/source/web
        $STD npm ci --omit=dev
        $STD npm run build
        msg_ok "Updated wanderer"


        msg_info "Starting wanderer service"
        systemctl start wanderer-web
        msg_ok "Started wanderer service"

        msg_ok "Update Successful"
    fi
    if check_for_gh_release "meilisearch" "meilisearch/meilisearch"; then
        msg_info "Stopping wanderer service"
        systemctl stop wanderer-web
        msg_ok "Stopped wanderer service"

        msg_info "Updating Meilisearch"

        cd /opt/wanderer/source/search
        $STD fetch_and_deploy_gh_release "meilisearch" "meilisearch/meilisearch" "binary" "latest" "/opt/wanderer/source/search"
        msg_ok "Updated Meilisearch"

        msg_info "Starting wanderer service"
        systemctl start wanderer-web
        msg_ok "Started wanderer service"
        msg_ok "Update Successful"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"

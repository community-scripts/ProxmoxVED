#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
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

    if [[ ! -f /opt/${APP}/start.sh ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    INSTALL_DIR="/opt/$APP"
    SRC_DIR="${INSTALL_DIR}/source"
    DB_DIR="${SRC_DIR}/db"
    SEARCH_DIR="${SRC_DIR}/search"
    WEB_DIR="${SRC_DIR}/web"
    DATA_DIR="${INSTALL_DIR}/data"
    PB_DB_LOCATION="${DATA_DIR}/pb_data"
    MEILI_DB_LOCATION="${DATA_DIR}/meili_data"
    if check_for_gh_release "$APP" "Flomp/wanderer"; then

        msg_info "Stopping $APP"
        systemctl stop wanderer-web.service
        msg_ok "Stopped $APP"


        msg_info "Updating $APP"
        $STD fetch_and_deploy_gh_release "$APP" "Flomp/wanderer"  "tarball" "latest" "$SRC_DIR"
        cd $DB_DIR
        $STD go mod tidy && $STD go build
        cd $WEB_DIR
        $STD npm ci --omit=dev
        $STD npm run build
        msg_ok "Updated $APP"


        msg_info "Starting $APP"
        systemctl start "${APP}"-web.service
        msg_ok "Started $APP"

        msg_ok "Update Successful"
    fi
    if check_for_gh_release "meilisearch" "meilisearch/meilisearch"; then
        msg_info "Stopping $APP"
        systemctl stop wanderer-web.service
        msg_ok "Stopped $APP"

        msg_info "Updating Meilisearch"

        cd $SEARCH_DIR
        $STD fetch_and_deploy_gh_release "meilisearch" "meilisearch/meilisearch" "binary" "latest" "$SEARCH_DIR"
        msg_ok "Updated Meilisearch"

        msg_info "Starting $APP"
        systemctl start "${APP}"-web.service
        msg_ok "Started $APP"
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

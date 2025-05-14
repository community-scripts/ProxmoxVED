#!/usr/bin/env bash
source <(curl -s https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/karlomikus/bar-assistant
# Source: https://github.com/karlomikus/vue-salt-rim
# Source: https://www.meilisearch.com/

APP="Bar-Assistant"
var_tags="${var_tags:-inventory;drinks}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
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
    if [[ ! -d /opt/bar-assistant ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    RELEASE_MEILISEARCH=$(curl -s https://api.github.com/repos/meilisearch/meilisearch/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    RELEASE_BARASSISTANT=$(curl -s https://api.github.com/repos/karlomikus/bar-assistant/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
    RELEASE_SALTRIM=$(curl -s https://api.github.com/repos/karlomikus/vue-salt-rim/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE_BARASSISTANT}" != "$(cat /opt/${APP}_version.txt)" ]]; then
        msg_info "Stopping Service"
        systemctl stop nginx
        msg_ok "Stopped Service"

        msg_info "Updating ${APP} to v${RELEASE_BARASSISTANT}"
        cd /opt
        mv /opt/bar-assistant /opt/bar-assistant-backup
        curl -fsSL "https://github.com/karlomikus/bar-assistant/archive/refs/tags/v${RELEASE_BARASSISTANT}.zip" -o barassistant.zip
        unzip -q barassistant.zip
        mv /opt/bar-assistant-${RELEASE_BARASSISTANT}/ /opt/bar-assistant
        cp /opt/bar-assistant-backup/.env /opt/bar-assistant/.env
        cp /opt/bar-assistant-backup/storage/bar-assistant /opt/bar-assistant/storage/bar-assistant
        cd /opt/bar-assistant
        composer install
        php artisan migrate --force
        php artisan storage:link
        php artisan bar:setup-meilisearch
        php artisan scout:sync-index-settings
        php artisan config:cache
        php artisan route:cache
        php artisan event:cache
        echo "${RELEASE_BARASSISTANT}" >/opt/${APP}_version.txt
        msg_ok "Updated $APP to v${RELEASE_BARASSISTANT}"

        msg_info "Starting Service"
        systemctl start service nginx
        msg_ok "Started Service"

        msg_info "Cleaning up"
        rm -rf /opt/barassistant.zip
        rm -rf /opt/bar-assistant-backup
        msg_ok "Cleaned"
    else
        msg_ok "No update required. ${APP} is already at v${RELEASE_BARASSISTANT}"
    fi

    if [[ ! -f /opt/vue-salt-rim_version.txt ]] || [[ "${RELEASE_SALTRIM}" != "$(cat /opt/vue-salt-rim_version.txt)" ]]; then
        msg_info "Stopping Service"
        systemctl stop nginx
        msg_ok "Stopped Service"

        msg_info "Updating Salt Rim to v${RELEASE_SALTRIM}"
        cd /opt
        mv /opt/vue-salt-rim /opt/vue-salt-rim-backup
        curl -fsSL "https://github.com/karlomikus/vue-salt-rim/archive/refs/tags/v${RELEASE_SALTRIM}.zip" -o saltrim.zip
        unzip -q saltrim.zip
        mv /opt/vue-salt-rim-${RELEASE_SALTRIM}/ /opt/vue-salt-rim
        cp /opt/vue-salt-rim-backup/public/config.js /opt/vue-salt-rim/public/config.js
        cd /opt/vue-salt-rim
        npm run build
        echo "${RELEASE_SALTRIM}" >/opt/vue-salt-rim_version.txt
        msg_ok "Updated $APP to v${RELEASE_SALTRIM}"

        msg_info "Starting Service"
        systemctl start service nginx
        msg_ok "Started Service"

        msg_info "Cleaning up"
        rm -rf /opt/saltrim.zip
        rm -rf /opt/vue-salt-rim-backup
        msg_ok "Cleaned"
    else
        msg_ok "No update required. Salt Rim is already at v${RELEASE_SALTRIM}"
    fi

    if [[ ! -f /opt/meilisearch_version.txt ]] || [[ "${RELEASE_MEILISEARCH}" != "$(cat /opt/meilisearch_version.txt)" ]]; then
        msg_info "Stopping Service"
        systemctl stop meilisearch
        msg_ok "Stopped Service"

        msg_info "Updating Meilisearch to ${RELEASE_MEILISEARCH}"
        cd /opt
        RELEASE=$(curl -s https://api.github.com/repos/meilisearch/meilisearch/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
        curl -fsSL https://github.com/meilisearch/meilisearch/releases/latest/download/meilisearch.deb -o meilisearch.deb
        $STD dpkg -i meilisearch.deb
        echo "${RELEASE_MEILISEARCH}" >/opt/meilisearch_version.txt
        msg_ok "Updated Meilisearch to v${RELEASE_MEILISEARCH}"

        msg_info "Starting Service"
        systemctl start meilisearch
        msg_ok "Started Service"

        msg_info "Cleaning up"
        rm -rf "/opt/meilisearch.deb"
        msg_ok "Cleaned"
        msg_ok "Updated Meilisearch"
    else
        msg_ok "No update required. Meilisearch is already at ${RELEASE_MEILISEARCH}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"

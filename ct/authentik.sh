#!/usr/bin/env bash
source <(curl -fsSL "${BASE_URL-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: JamesonRGrieve
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/goauthentik/authentik

APP="Authentik"
var_tags="${var_tags:-identity;sso}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
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

    if [[ ! -d /opt/authentik ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    # Get latest version from HTML (avoids API rate limit)
    RELEASE=$(curl -fsSL https://github.com/goauthentik/authentik/releases/latest 2>&1 | grep -oP 'goauthentik/authentik/releases/tag/\Kversion/[0-9.]+' | head -1)
    if [[ -z "$RELEASE" ]]; then
        msg_error "Could not determine latest version"
        exit
    fi

    if [[ ! -f /opt/authentik_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/authentik_version.txt)" ]]; then
        msg_info "Stopping ${APP} services"
        systemctl stop authentik-server authentik-worker
        msg_ok "Stopped ${APP} services"

        msg_info "Creating backup"
        tar -czf "/opt/authentik_backup_$(date +%F).tar.gz" /opt/authentik/media /opt/authentik/.env 2>/dev/null || true
        msg_ok "Backup created"

        msg_info "Updating ${APP} to ${RELEASE}"
        cd /opt/authentik || exit 1

        # Update source
        sudo -u authentik git fetch --all --tags
        $STD sudo -u authentik git checkout "${RELEASE}"

        # Rebuild web components
        cd /opt/authentik/web || exit 1
        $STD sudo -u authentik npm install
        $STD sudo -u authentik npm run build

        # Update Python dependencies
        cd /opt/authentik || exit 1
        $STD sudo -u authentik bash -c 'source /opt/authentik/.venv/bin/activate && /usr/local/bin/uv sync --frozen --no-dev'

        # Rebuild Go binary
        cd /opt/authentik || exit 1
        $STD sudo -u authentik bash -c 'export PATH=/usr/local/go/bin:$PATH && CGO_ENABLED=1 go build -o /opt/authentik/bin/authentik ./cmd/server'

        # Run migrations
        cd /opt/authentik || exit 1
        $STD sudo -u authentik bash -c 'source /opt/authentik/.venv/bin/activate && set -a && source /opt/authentik/.env && set +a && python manage.py migrate'

        echo "${RELEASE}" >/opt/authentik_version.txt
        msg_ok "Updated ${APP} to ${RELEASE}"

        msg_info "Starting ${APP} services"
        systemctl start authentik-server authentik-worker
        msg_ok "Started ${APP} services"

        msg_info "Cleaning up"
        find /opt -name "authentik_backup_*.tar.gz" -mtime +7 -delete
        msg_ok "Cleanup complete"
    else
        msg_ok "No update required. ${APP} is already at ${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000/if/flow/initial-setup/${CL}"
echo -e "${INFO}${YW} Admin credentials are stored in:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}~/authentik.creds${CL}"

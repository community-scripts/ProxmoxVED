#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thieneret
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/goauthentik/authentik

APP="authentik"
var_tags="${var_tags:-auth}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
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

    AUTHENTIK_VERSION="version/2025.12.4"
    NODE_VERSION="24"

    if [[ ! -d /opt/authentik ]]; then
        msg_error "No authentik Installation Found!"
        exit
    fi

    if [[ "$AUTHENTIK_VERSION" == "$(cat /opt/authentik_version.txt)" ]]; then
        msg_ok "Authentik up-to-date"
        exit
    fi

    if check_for_gh_release "geoipupdate" "maxmind/geoipupdate"; then
        fetch_and_deploy_gh_release "geoipupdate" "maxmind/geoipupdate" "binary"
    fi

    msg_info "Stopping Services"
    systemctl stop authentik-server.service
    systemctl stop authentik-worker.service
    msg_ok "Stopped Services"

    if check_for_gh_release "xmlsec" "lsh123/xmlsec"; then
    
        CLEAN_INSTALL=1 fetch_and_deploy_gh_release "xmlsec" "lsh123/xmlsec" "tarball" "latest" "/opt/xmlsec"

        msg_info "Update xmlsec"
        cd /opt/xmlsec
        $STD ./autogen.sh
        $STD make -j $(nproc)
        $STD make check
        $STD make install
        ldconfig
        msg_ok "xmlsec updated"
    fi

    setup_nodejs
    setup_go

    if check_for_gh_tag "authentik" "goauthentik/authentik" "${AUTHENTIK_VERSION}"; then
        
        CLEAN_INSTALL=1 fetch_and_deploy_gh_release "authentik" "goauthentik/authentik" "tag" "${AUTHENTIK_VERSION}" "/opt/authentik"
        
        msg_info "Update web"
        cd /opt/authentik/web
        NODE_ENV="production"
        $STD npm install
        $STD npm run build
        $STD npm run build:sfe
        msg_ok "Web updated"

        msg_info "Update go proxy"
        cd /opt/authentik
        CGO_ENABLED="1"
        $STD go mod download
        $STD go build -o /opt/authentik/authentik-server ./cmd/server
        msg_ok "Go proxy updated"
    
        setup_uv

        setup_rust

        msg_info "Update python server"
        UV_NO_BINARY_PACKAGE="cryptography lxml python-kadmin-rs xmlsec"
        UV_COMPILE_BYTECODE="1"
        UV_LINK_MODE="copy"
        UV_NATIVE_TLS="1"
        RUSTUP_PERMIT_COPY_RENAME="true"
        cd /opt/authentik
        $STD uv sync --frozen --no-install-project --no-dev
        msg_ok "Python server updated"

        chown -R authentik:authentik /opt/authentik

        echo "${AUTHENTIK_VERSION}" > /opt/authentik_version.txt
    fi

    msg_info "Restarting services"
    systemctl restart authentik-server.service authentik-worker.service
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
    exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Initial setup URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000/if/flow/initial-setup/${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL}"

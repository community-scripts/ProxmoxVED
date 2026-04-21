#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
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

  AUTHENTIK_VERSION="version/2026.2.2"
  NODE_VERSION="24"
  XMLSEC_VERSION="1.3.9"

  if [[ ! -d /opt/authentik ]]; then
    msg_error "No authentik Installation Found!"
    exit
  fi

  if [[ "$AUTHENTIK_VERSION" == "$(cat $HOME/.authentik)" ]]; then
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

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "xmlsec" "lsh123/xmlsec" "tarball" "${XMLSEC_VERSION}" "/opt/xmlsec"

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

  if check_for_gh_release "authentik" "goauthentik/authentik" "${AUTHENTIK_VERSION}"; then

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "authentik" "goauthentik/authentik" "tarball" "${AUTHENTIK_VERSION}" "/opt/authentik"

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
    $STD uv python install 3.14.3 -i /usr/local/bin
    UV_NO_BINARY_PACKAGE="cryptography lxml python-kadmin-rs xmlsec"
    UV_COMPILE_BYTECODE="1"
    UV_LINK_MODE="copy"
    UV_NATIVE_TLS="1"
    RUSTUP_PERMIT_COPY_RENAME="true"
    cd /opt/authentik
    export UV_PYTHON_INSTALL_DIR="/usr/local/bin"
    $STD uv sync --frozen --no-install-project --no-dev
    msg_ok "Python server updated"

    chown -R authentik:authentik /opt/authentik

  fi

  msg_info "Restarting services"
  systemctl restart authentik-server.service authentik-worker.service
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container

export DISK_SIZE=1

if [[ -n "$CONTAINER_STORAGE" ]]; then
  msg_info "Validating storage space for data storage"
  if ! validate_storage_space "$CONTAINER_STORAGE" "$DISK_SIZE" "no"; then
    local free_space
    free_space=$(pvesm status 2>/dev/null | awk -v s="$CONTAINER_STORAGE" '$1 == s { print $6 }')
    local free_fmt
    free_fmt=$(numfmt --to=iec --from-unit=1024 --suffix=B --format %.1f "$free_space" 2>/dev/null || echo "${free_space}KB")
    msg_error "Not enough space on '$CONTAINER_STORAGE'. Required: ${DISK_SIZE}GB, Available: ${free_fmt}"
    exit 214
  fi
  msg_ok "Storage space validated for data storage"
fi

msg_info "Attaching data storage to container and creating directory structure"
pct set "$CTID" -mp0 "$CONTAINER_STORAGE":"$DISK_SIZE",mp=/opt/authentik-data,backup=1

lxc-attach -n "$CTID" -- bash -c "<<EOF
mkdir -p /opt/authentik-data/{certs,media,geoip,templates}
cp /opt/authentik/tests/GeoLite2-ASN-Test.mmdb /opt/authentik-data/geoip/GeoLite2-ASN.mmdb
cp /opt/authentik/tests/GeoLite2-City-Test.mmdb /opt/authentik-data/geoip/GeoLite2-City.mmdb
chown -R authentik:authentik /opt/authentik-data
EOF
"
msg_ok "Data store attached, directory structure created"

msg_info "Starting services"
lxc-attach -n "$CTID" -- systemctl enable -q --now authentik-server.service authentik-worker.service
msg_ok "Services started"

description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Initial setup URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000/if/flow/initial-setup/${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL}"

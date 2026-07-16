#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jay Brame (bramej)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Skylark-Software/Janua

APP="Janua"
var_tags="${var_tags:-remote;rdp;webserver}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
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

  if [[ ! -d /opt/janua ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "janua" "Skylark-Software/Janua"; then
    GUAC_VERSION="1.6.0"

    msg_info "Stopping Services"
    systemctl stop tomcat guacd
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "janua" "Skylark-Software/Janua" "tarball" "latest" "/opt/janua/src"

    msg_info "Rebuilding Janua Desktop Gateway (Patience)"
    rm -rf /opt/janua/server
    mkdir -p /opt/janua/server
    curl -fsSL "https://dlcdn.apache.org/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz" | tar -xz --strip-components=1 -C /opt/janua/server
    cd /opt/janua/server
    for p in /opt/janua/src/guacd/patches/*.patch; do
      $STD git apply --recount -p1 "$p"
    done
    export CPPFLAGS="-Wno-error=deprecated-declarations"
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    $STD autoreconf -fi
    $STD ./configure --with-init-dir=/etc/init.d --with-rdp --with-ssh --with-vnc
    $STD make -j"$(nproc)"
    $STD make install
    $STD ldconfig
    cp /opt/janua/src/guacamole-branding/janua-branding.jar /etc/guacamole/extensions/janua-branding.jar
    msg_ok "Rebuilt Janua Desktop Gateway"

    msg_info "Starting Services"
    systemctl start guacd tomcat
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080/janua${CL}"

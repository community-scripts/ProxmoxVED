#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/DioCrafts/OxiCloud

APP="OxiCloud"
var_tags="${var_tags:-files;documents}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-20}"
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

  if [[ ! -d /opt/oxicloud ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "OxiCloud" "DioCrafts/OxiCloud"; then
    msg_info "Stopping OxiCloud"
    $STD systemctl stop oxicloud
    msg_ok "Stopped OxiCloud"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "OxiCloud" "DioCrafts/OxiCloud" "tarball" "latest" "/opt/oxicloud"
    TOOLCHAIN="$(sed -n '2s/[^:]*://p' /opt/oxicloud/Dockerfile | awk -F- '{print $1}')"
    RUST_TOOLCHAIN=$TOOLCHAIN setup_rust

    msg_info "Updating OxiCloud"
    cd /opt/oxicloud
    export DATABASE_URL="postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost/${PG_DB_NAME}"
    $STD cargo build --release
    mv target/release/oxicloud /usr/bin/oxicloud && chmod +x /usr/bin/oxicloud
    msg_ok "Updated OxiCloud"

    msg_info "Starting OxiCloud"
    $STD systemctl start oxicloud
    msg_ok "Started OxiCloud"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8086${CL}"

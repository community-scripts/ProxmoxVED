#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Harrison (germondai)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/germondai/trawl

APP="TRAWL"
var_tags="${var_tags:-scraping;proxy;tools}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/trawl ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "trawl" "germondai/trawl"; then
    msg_info "Stopping Services"
    systemctl stop trawl
    msg_ok "Stopped Services"

    create_backup /etc/trawl.env /opt/trawl_data/proxy-ca

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "trawl" "germondai/trawl" "tarball"

    msg_info "Installing Bun Dependencies"
    cd /opt/trawl
    $STD bun install --frozen-lockfile --production --omit=dev --linker=hoisted
    msg_ok "Installed Bun Dependencies"

    CAMOUFOX_BUILD=$(arch_resolve "alpha.26" "alpha.25")
    CAMOUFOX_ARCH=$(arch_resolve "x86_64" "arm64")
    CLEAN_INSTALL=1 fetch_and_deploy_from_url \
      "https://github.com/daijro/camoufox/releases/download/v150.0.2-beta.25/camoufox-150.0.2-${CAMOUFOX_BUILD}-lin.${CAMOUFOX_ARCH}.zip" \
      "/opt/trawl_data/camoufox"
    curl_download \
      "/opt/trawl_data/camoufox/GeoLite2-City.mmdb" \
      "https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-City.mmdb"
    [[ "$(stat -c%s /opt/trawl_data/camoufox/GeoLite2-City.mmdb)" -gt 10000000 ]] || {
      msg_error "GeoLite2-City.mmdb download is incomplete"
      exit 1
    }
    cat <<EOF >/opt/trawl_data/camoufox/version.json
{"version":"150.0.2","release":"${CAMOUFOX_BUILD}"}
EOF
    chmod -R 755 /opt/trawl_data/camoufox

    restore_backup

    msg_info "Starting Services"
    systemctl start trawl
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
echo -e "${INFO}${YW}Access the FlareSolverr-compatible API at:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8191/v1${CL}"

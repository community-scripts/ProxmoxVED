#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://clickhouse.com

APP="ClickHouse"
var_tags="${var_tags:-database;analytics;observability}"
var_cpu="${var_cpu:-2}"
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

  if ! command -v clickhouse-server &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_clickhouse

  if [[ -f /opt/clickstack/.env ]]; then
    if check_for_gh_release "clickstack" "hyperdxio/hyperdx"; then
      msg_info "Stopping ClickStack Services"
      systemctl stop clickstack-app clickstack-api
      msg_ok "Stopped ClickStack Services"

      msg_info "Backing up Data"
      cp /opt/clickstack/.env /opt/clickstack.env.bak
      msg_ok "Backed up Data"

      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "clickstack" "hyperdxio/hyperdx" "tarball" "latest" "/opt/clickstack"

      cd /opt/clickstack
      $STD corepack enable
      YARN_SPEC=$(node -e "const p=require('./package.json');process.stdout.write(p.packageManager||'yarn@stable')" 2>/dev/null || echo "yarn@stable")
      $STD corepack prepare "${YARN_SPEC}" --activate

      msg_info "Building HyperDX"
      $STD yarn install
      $STD yarn workspace @hyperdx/common-utils run build
      rm -rf /opt/clickstack/packages/api/build
      yarn workspace @hyperdx/api exec tsc >>"$(get_active_logfile)" 2>&1 || true
      $STD yarn workspace @hyperdx/api exec tsc-alias
      cp -r /opt/clickstack/packages/api/src/opamp/proto /opt/clickstack/packages/api/build/opamp/ 2>/dev/null || true
      [[ -f /opt/clickstack/packages/api/build/index.js ]] || {
        msg_error "HyperDX API build failed: build/index.js not found"
        exit 1
      }
      $STD yarn workspace @hyperdx/app run build
      msg_ok "Built HyperDX"

      msg_info "Restoring Data"
      cp /opt/clickstack.env.bak /opt/clickstack/.env
      rm -f /opt/clickstack.env.bak
      msg_ok "Restored Data"

      msg_info "Starting ClickStack Services"
      systemctl start clickstack-api clickstack-app
      msg_ok "Started ClickStack Services"
      msg_ok "Updated successfully!"
    fi

    if check_for_gh_release "otelcol" "open-telemetry/opentelemetry-collector-releases"; then
      msg_info "Stopping OTel Collector"
      systemctl stop clickstack-otel
      msg_ok "Stopped OTel Collector"

      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "otelcol" "open-telemetry/opentelemetry-collector-releases" "prebuild" "latest" "/opt/otelcol" "otelcol-contrib_*_linux_amd64.tar.gz"

      msg_info "Starting OTel Collector"
      systemctl start clickstack-otel
      msg_ok "Started OTel Collector"
      msg_ok "Updated OTel Collector!"
    fi
  fi

  exit
}

export CLICKSTACK="no"
if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLICKSTACK" --yesno "Install ClickStack observability stack?\n\n(HyperDX UI + OTel Collector + MongoDB)\nRequires: 4 CPU, 8GB RAM, 30GB Disk" 12 58); then
  export CLICKSTACK="yes"
  var_cpu="4"
  var_ram="8192"
  var_disk="30"
fi

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
if [[ "${CLICKSTACK}" == "yes" ]]; then
  echo -e "${INFO}${YW} Access HyperDX UI using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
  echo -e "${INFO}${YW} ClickHouse Play UI / HTTP API:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8123${CL}"
  echo -e "${INFO}${YW} OTel Collector (gRPC: 4317, HTTP: 4318)${CL}"
else
  echo -e "${INFO}${YW} ClickHouse Play UI / HTTP API:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8123${CL}"
fi

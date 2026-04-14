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
    CURRENT_HDX_VERSION=$(cat ~/.clickstack 2>/dev/null || echo "none")
    LATEST_HDX_VERSION=$(curl -fsSL "https://api.github.com/repos/hyperdxio/hyperdx/tags?per_page=1" | grep -oP '"name": "hyperdx@\K[^"]+' | head -1)

    if [[ "$CURRENT_HDX_VERSION" != "$LATEST_HDX_VERSION" ]]; then
      msg_info "Stopping ClickStack Services"
      systemctl stop clickstack-app clickstack-api
      msg_ok "Stopped ClickStack Services"

      msg_info "Backing up Data"
      cp /opt/clickstack/.env /opt/clickstack.env.bak
      msg_ok "Backed up Data"

      cd /opt/clickstack
      $STD git fetch --all --tags
      $STD git checkout "hyperdx@${LATEST_HDX_VERSION}"

      msg_info "Building HyperDX"
      $STD yarn install --immutable
      $STD yarn workspace @hyperdx/common-utils run build
      $STD yarn workspace @hyperdx/api run build
      NEXT_OUTPUT_STANDALONE=true $STD yarn workspace @hyperdx/app run build
      msg_ok "Built HyperDX"

      msg_info "Restoring Data"
      cp /opt/clickstack.env.bak /opt/clickstack/.env
      rm -f /opt/clickstack.env.bak
      msg_ok "Restored Data"

      msg_info "Starting ClickStack Services"
      systemctl start clickstack-api clickstack-app
      msg_ok "Started ClickStack Services"

      echo "${LATEST_HDX_VERSION}" >~/.clickstack
      msg_ok "Updated HyperDX to v${LATEST_HDX_VERSION}"
    else
      msg_ok "HyperDX is already up to date (v${CURRENT_HDX_VERSION})"
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
  echo -e "${INFO}${YW} ClickHouse HTTP API:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8123${CL}"
  echo -e "${INFO}${YW} OTel Collector (gRPC: 4317, HTTP: 4318)${CL}"
else
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8123${CL}"
fi

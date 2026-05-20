#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: aliaksei135
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/arpanghosh8453/garmin-grafana

APP="garmin-grafana"
var_tags="${var_tags:-sports;visualization}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/garmin-grafana ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "garmin-grafana" "arpanghosh8453/garmin-grafana"; then
    msg_info "Stopping Services"
    systemctl stop garmin-grafana
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/garmin-grafana/.env /opt/garmin-grafana.env.bak
    cp -r /opt/garmin-grafana/.garminconnect /opt/garmin-grafana-tokens.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "garmin-grafana" "arpanghosh8453/garmin-grafana" "tarball"

    msg_info "Restoring Data"
    cp /opt/garmin-grafana.env.bak /opt/garmin-grafana/.env
    cp -r /opt/garmin-grafana-tokens.bak /opt/garmin-grafana/.garminconnect
    rm -f /opt/garmin-grafana.env.bak
    rm -rf /opt/garmin-grafana-tokens.bak
    msg_ok "Restored Data"

    msg_info "Updating Dependencies"
    source /opt/garmin-grafana/.env
    $STD uv sync --locked --project /opt/garmin-grafana/
    sed -i 's/\${DS_GARMIN_STATS}/garmin_influxdb/g' /opt/garmin-grafana/Grafana_Dashboard/Garmin-Grafana-Dashboard.json
    sed -i 's/influxdb:8086/localhost:8086/' /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
    sed -i "s/influxdb_user/${INFLUXDB_USERNAME}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
    sed -i "s/influxdb_secret_password/${INFLUXDB_PASSWORD}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
    sed -i "s/GarminStats/${INFLUXDB_DATABASE}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
    cp -r /opt/garmin-grafana/Grafana_Datasource/* /etc/grafana/provisioning/datasources
    cp -r /opt/garmin-grafana/Grafana_Dashboard/* /etc/grafana/provisioning/dashboards
    msg_ok "Updated Dependencies"

    msg_info "Starting Services"
    systemctl start garmin-grafana
    $STD systemctl restart grafana-server
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"

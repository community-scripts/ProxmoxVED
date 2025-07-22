#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/raw/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: aliaksei135
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/arpanghosh8453/garmin-grafana

APP="garmin-grafana"
var_tags="${var_tags:-sports;visualization}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

# this only updates garmin-grafana, not influxdb or grafana, which are upgraded with apt
function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/garmin-grafana/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/arpanghosh8453/garmin-grafana/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ ! -d /opt/garmin-grafana/ ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop garmin-grafana
    systemctl stop grafana-server
    systemctl stop influxdb
    msg_ok "Stopped $APP"

    if [[ ! -f /opt/garmin-grafana/.env ]]; then
      msg_error "No .env file found in /opt/garmin-grafana/.env"
      exit
    fi
    source /opt/garmin-grafana/.env
    if [[ -z "${INFLUXDB_USER}" || -z "${INFLUXDB_PASSWORD}" || -z "${INFLUXDB_NAME}" ]]; then
      msg_error "INFLUXDB_USER, INFLUXDB_PASSWORD, or INFLUXDB_NAME not set in .env file"
      exit
    fi

    msg_info "Creating Backup"
    tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /opt/garmin-grafana/.garminconnect /opt/garmin-grafana/.env
    mv /opt/garmin-grafana/ /opt/garmin-grafana-backup/
    msg_ok "Backup Created"

    msg_info "Updating $APP to v${RELEASE}"
    curl -fsSL -o "${RELEASE}.zip" "https://github.com/arpanghosh8453/garmin-grafana/archive/refs/tags/${RELEASE}.zip"
    unzip -q "${RELEASE}.zip"
    mv "garmin-grafana-${RELEASE}/" "/opt/garmin-grafana"
    rm -f "${RELEASE}.zip"
    $STD uv sync --locked --project /opt/garmin-grafana/
    # shellcheck disable=SC2016
    sed -i 's/\${DS_GARMIN_STATS}/garmin_influxdb/g' /opt/garmin-grafana/Grafana_Dashboard/Garmin-Grafana-Dashboard.json
    sed -i 's/influxdb:8086/localhost:8086/' /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
    sed -i "s/influxdb_user/${INFLUXDB_USER}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
    sed -i "s/influxdb_secret_password/${INFLUXDB_PASSWORD}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
    sed -i "s/GarminStats/${INFLUXDB_NAME}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
    # Copy across grafana data
    cp -r /opt/garmin-grafana/Grafana_Datasource/* /etc/grafana/provisioning/datasources
    cp -r /opt/garmin-grafana/Grafana_Dashboard/* /etc/grafana/provisioning/dashboards
    # Copy back the env and token files
    cp /opt/garmin-grafana-backup/.env /opt/garmin-grafana/.env
    cp -r /opt/garmin-grafana-backup/.garminconnect /opt/garmin-grafana/.garminconnect
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start garmin-grafana
    systemctl start grafana-server
    systemctl start influxdb
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -rf /opt/garmin-grafana-backup
    msg_ok "Cleanup Completed"

    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
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

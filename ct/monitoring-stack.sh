#!/usr/bin/env bash
source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Watashi (Watashi199) | Co-author: OpenAI Codex (GPT-5)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://grafana.com/

APP="Monitoring-Stack"
var_tags="${var_tags:-monitoring;analytics;logging}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
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

  if [[ ! -d /opt/monitoring-stack ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  create_backup /opt/monitoring-stack/.env \
                /etc/prometheus/prometheus.yml \
                /etc/prometheus/rules/monitoring-stack.yml \
                /etc/alertmanager/alertmanager.yml \
                /etc/loki/config.yml \
                /etc/alloy/config.alloy \
                /etc/grafana/provisioning/datasources/monitoring-stack.yml \
                /etc/grafana/provisioning/dashboards/monitoring-stack.yml

  msg_info "Stopping Services"
  systemctl stop alloy
  systemctl stop loki
  systemctl stop prometheus-node-exporter
  systemctl stop prometheus-alertmanager
  systemctl stop prometheus
  systemctl stop grafana-server
  msg_ok "Stopped Services"

  msg_info "Updating Packages"
  $STD apt update
  $STD apt install -y --only-upgrade \
    alloy \
    grafana \
    loki \
    prometheus \
    prometheus-alertmanager \
    prometheus-node-exporter
  msg_ok "Updated Packages"

  restore_backup

  msg_info "Starting Services"
  systemctl start prometheus
  systemctl start prometheus-alertmanager
  systemctl start prometheus-node-exporter
  systemctl start loki
  systemctl start alloy
  systemctl start grafana-server
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
echo -e "${TAB}${BGN}Grafana${CL} http://${IP}:3000"
echo -e "${TAB}${BGN}Prometheus${CL} http://${IP}:9090"
echo -e "${TAB}${BGN}Alertmanager${CL} http://${IP}:9093"
echo -e "${INFO}${YW} Loki, Node Exporter, and Alloy remain local-only inside the LXC.${CL}"

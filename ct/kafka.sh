#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tanansatpal
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://kafka.apache.org/
APP="Apache Kafka"
var_tags="${var_tags:-messaging;streaming;kraft}"
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

  if [[ ! -d /opt/kafka ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  RELEASE=$(curl -fsSL https://downloads.apache.org/kafka/ \
    | grep -oP '(?<=href=")[0-9]+\.[0-9]+\.[0-9]+(?=/")' \
    | sort -V | tail -1)
  if [[ -z "${RELEASE}" ]]; then
    msg_error "Failed to resolve latest Kafka version"
    exit 1
  fi
  CURRENT=$(cat /opt/kafka/.version 2>/dev/null || echo "0.0.0")

  if [[ "$RELEASE" == "$CURRENT" ]]; then
    msg_ok "Apache Kafka is already at v${CURRENT}."
    exit 0
  fi

  msg_info "Stopping Apache Kafka"
  systemctl stop kafka
  msg_ok "Stopped Apache Kafka"

  msg_info "Backing up configuration"
  cp -a /opt/kafka/config /opt/kafka-config.bak
  msg_ok "Backed up configuration"

  msg_info "Updating Apache Kafka to v${RELEASE}"
  cd /tmp
  curl -fsSLO "https://downloads.apache.org/kafka/${RELEASE}/kafka_2.13-${RELEASE}.tgz"
  rm -rf /opt/kafka.old
  mv /opt/kafka /opt/kafka.old
  tar -xzf "kafka_2.13-${RELEASE}.tgz" -C /opt
  mv "/opt/kafka_2.13-${RELEASE}" /opt/kafka
  cp -a /opt/kafka-config.bak/. /opt/kafka/config/
  echo "${RELEASE}" >/opt/kafka/.version
  chown -R kafka:kafka /opt/kafka
  rm -f "/tmp/kafka_2.13-${RELEASE}.tgz"
  rm -rf /opt/kafka-config.bak /opt/kafka.old
  msg_ok "Updated Apache Kafka to v${RELEASE}"

  msg_info "Starting Apache Kafka"
  systemctl start kafka
  msg_ok "Started Apache Kafka"

  msg_ok "Update Complete"
  exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Kafka broker is available at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}:9092${CL}"
echo -e "${INFO}${YW} Controller listener (internal):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}:9093${CL}"
echo -e "${INFO}${YW} Cluster info stored in:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/root/kafka.creds${CL}"
echo -e "${INFO}${YW} For a web UI, install the companion script 'Kafka-UI'.${CL}"

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jelcoo
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://calagopus.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y curl
msg_ok "Installed Dependencies"

setup_docker

if [[ "${CALAGOPUS_AIO:-yes}" == "yes" ]]; then
  if [[ "${CALAGOPUS_NIGHTLY:-no}" == "yes" && "${CALAGOPUS_HEAVY:-no}" == "yes" ]]; then
    IMAGE_TAG="nightly-heavy-aio"
  elif [[ "${CALAGOPUS_NIGHTLY:-no}" == "yes" ]]; then
    IMAGE_TAG="nightly-aio"
  elif [[ "${CALAGOPUS_HEAVY:-no}" == "yes" ]]; then
    IMAGE_TAG="heavy-aio"
  else
    IMAGE_TAG="aio"
  fi
else
  if [[ "${CALAGOPUS_NIGHTLY:-no}" == "yes" && "${CALAGOPUS_HEAVY:-no}" == "yes" ]]; then
    IMAGE_TAG="nightly-heavy"
  elif [[ "${CALAGOPUS_NIGHTLY:-no}" == "yes" ]]; then
    IMAGE_TAG="nightly"
  elif [[ "${CALAGOPUS_HEAVY:-no}" == "yes" ]]; then
    IMAGE_TAG="heavy"
  else
    IMAGE_TAG="latest"
  fi
fi

msg_info "Setting Up Calagopus"
mkdir -p /opt/calagopus
cd /opt/calagopus

if [[ "${CALAGOPUS_AIO:-yes}" == "yes" ]]; then
  $STD curl -fsSL "https://raw.githubusercontent.com/calagopus/panel/refs/heads/main/compose.aio.yml" -o compose.yml
elif [[ "${CALAGOPUS_HEAVY:-no}" == "yes" ]]; then
  $STD curl -fsSL "https://raw.githubusercontent.com/calagopus/panel/refs/heads/main/compose.heavy.yml" -o compose.yml
else
  $STD curl -fsSL "https://raw.githubusercontent.com/calagopus/panel/refs/heads/main/compose.yml" -o compose.yml
fi

if [[ "${CALAGOPUS_NIGHTLY:-no}" == "yes" ]]; then
  sed -i "s|:aio\b|:${IMAGE_TAG}|g; s|:latest\b|:${IMAGE_TAG}|g; s|:heavy\b|:${IMAGE_TAG}|g" compose.yml
fi

APP_ENCRYPTION_KEY=$(openssl rand -hex 16)
sed -i "s/CHANGEME/${APP_ENCRYPTION_KEY}/g" compose.yml

[[ "${CALAGOPUS_AIO:-yes}" == "yes" ]] && echo 'app_name: Calagopus' >/opt/calagopus/wings-config.yml
msg_ok "Set Up Calagopus"

msg_info "Starting Calagopus"
$STD docker compose up -d
msg_ok "Started Calagopus"

motd_ssh
customize
cleanup_lxc

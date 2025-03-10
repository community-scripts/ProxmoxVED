#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ZoeyVid/NPMplus

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add newt
$STD apk add curl
$STD apk add openssh
$STD apk add tzdata
$STD apk add nano
$STD apk add mc
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
$STD apk add docker
$STD rc-service docker start
$STD rc-update add docker default
msg_ok "Installed Docker"

get_latest_release() {
    curl -sL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")

msg_info "Installing Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -sSL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
msg_ok "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"

msg_info "Get NginxProxyManager Plus"
cd /opt
wget -q https://raw.githubusercontent.com/ZoeyVid/NPMplus/refs/heads/develop/compose.yaml
msg_ok "Get NginxProxyManager Plus"

read -r -p "Enter your TZ Timezone (https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List): " TZ_INPUT
read -r -p "Enter your ACME Email: " ACME_EMAIL_INPUT

sed -i "s|TZ=.*|TZ=\"$TZ_INPUT\"|g" /opt/compose.yaml
sed -i "s|ACME_EMAIL=.*|ACME_EMAIL=\"$ACME_EMAIL_INPUT\"|g" /opt/compose.yaml

msg_info "Starting NPM Plus"
docker compose up -d
msg_ok "Started NPM Plus"

motd_ssh
customize

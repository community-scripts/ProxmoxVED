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
$STD apk add \
    newt \
    curl \
    openssh \
    tzdata \
    nano \
    gawk \
    yq \
    mc

msg_ok "Installed Dependencies"

msg_info "Installing Docker & Compose"
$STD apk add docker
$STD rc-service docker start
$STD rc-update add docker default

get_latest_release() {
    curl -sL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -sSL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
msg_ok "Installed Docker & Compose"

msg_info "Get NPM Plus"
cd /opt
wget -q https://raw.githubusercontent.com/ZoeyVid/NPMplus/refs/heads/develop/compose.yaml
msg_ok "Get NPM Plus"

read -r -p "Enter your TZ Identifier for your Country (https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List): " TZ_INPUT
read -r -p "Enter your ACME Email: " ACME_EMAIL_INPUT

yq -i "
  .services.npmplus.environment |=
    (map(select(. != \"TZ=*\" and . != \"ACME_EMAIL=*\")) +
    [\"TZ=$TZ_INPUT\", \"ACME_EMAIL=$ACME_EMAIL_INPUT\"])
" /opt/compose.yaml

msg_info "Starting NPM Plus"
$STD docker compose up -d

CONTAINER_ID=$(docker ps --format "{{.ID}}" --filter "name=npmplus")

if [[ -z "$CONTAINER_ID" ]]; then
    msg_error "NPMplus container not found."
    break
fi

TIMEOUT=60
while [[ $TIMEOUT -gt 0 ]]; do
    STATUS=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_ID" 2>/dev/null)

    if [[ "$STATUS" == "healthy" ]]; then
        msg_ok "Started NPM Plus"
        break
    fi

    sleep 2
    ((TIMEOUT--))
done

if [[ "$STATUS" != "healthy" ]]; then
    msg_error "NPMplus container did not reach a healthy state."
    break
fi

msg_info "Get Default Login (Patience)"
TIMEOUT=60
while [[ $TIMEOUT -gt 0 ]]; do
    PASSWORD_LINE=$(docker logs "$CONTAINER_ID" 2>&1 | grep -m1 "Creating a new user: admin@example.org with password:")

    if [[ -n "$PASSWORD_LINE" ]]; then
        PASSWORD=$(echo "$PASSWORD_LINE" | gawk -F 'password: ' '{print $2}')
        echo -e "username: admin@example.org\npassword: $PASSWORD" >/opt/.npm_pwd
        msg_ok "Saved default login to /opt/.npm_pwd"
        break
    fi

    sleep 2
    ((TIMEOUT--))
done

if [[ $TIMEOUT -eq 0 ]]; then
    msg_error "Failed to retrieve default login credentials."
    break
fi
msg_ok "Get Default Login Successful"

motd_ssh
customize

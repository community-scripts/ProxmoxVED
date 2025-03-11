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

msg_info "Get NPMplus"
cd /opt
wget -q https://raw.githubusercontent.com/ZoeyVid/NPMplus/refs/heads/develop/compose.yaml
msg_ok "Get NPMplus"

attempts=0
while true; do
    read -r -p "Enter your TZ Identifier (e.g., Europe/Berlin): " TZ_INPUT
    if validate_tz "$TZ_INPUT"; then
        break
    fi
    msg_error "Invalid timezone! Please enter a valid TZ identifier."
    ((attempts++))
    if ((attempts >= 3)); then
        msg_error "Maximum attempts reached. Exiting."
        exit 1
    fi
done

read -r -p "Enter your ACME Email: " ACME_EMAIL_INPUT

yq -i "
  .services.npmplus.environment |=
    (map(select(. != \"TZ=*\" and . != \"ACME_EMAIL=*\")) +
    [\"TZ=$TZ_INPUT\", \"ACME_EMAIL=$ACME_EMAIL_INPUT\"])
" /opt/compose.yaml

msg_info "Starting NPMplus"
$STD docker compose up -d
CONTAINER_ID=$(docker ps --format "{{.ID}}" --filter "name=npmplus")

if [[ -z "$CONTAINER_ID" ]]; then
    msg_error "NPMplus container not found."
fi

TIMEOUT=60
while [[ $TIMEOUT -gt 0 ]]; do
    STATUS=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_ID" 2>/dev/null)
    sleep 2
    ((TIMEOUT--))
done

if [[ "$STATUS" != "healthy" ]]; then
    msg_error "NPMplus container did not reach a healthy state."
fi
msg_ok "Started NPMplus"

motd_ssh
customize

msg_info "Get Default Login (Patience)"
TIMEOUT=60
while [[ $TIMEOUT -gt 0 ]]; do
    PASSWORD_LINE=$(docker logs "$CONTAINER_ID" 2>&1 | awk '/Creating a new user:/ {print; exit}')
    if [[ -n "$PASSWORD_LINE" ]]; then
        PASSWORD=$(echo "$PASSWORD_LINE" | awk -F 'password: ' '{print $2}')
        echo -e "username: admin@example.org\npassword: $PASSWORD" >/opt/.npm_pwd
        msg_ok "Saved default login to /opt/.npm_pwd"
        break
    fi
    sleep 2
    ((TIMEOUT--))
done

if [[ $TIMEOUT -eq 0 ]]; then
    msg_error "Failed to retrieve default login credentials."
fi

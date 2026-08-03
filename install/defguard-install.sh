#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/DefGuard/defguard

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="17" setup_postgresql
PG_DB_NAME="defguard" PG_DB_USER="defguard" setup_postgresql_db

fetch_and_deploy_gh_release "defguard" "DefGuard/defguard" "binary" "latest" "/opt/defguard" "defguard-*-$(arch_resolve x86_64 aarch64)-unknown-linux-gnu.deb"

msg_info "Configuring Defguard"
DEFGUARD_ADMIN_PASSWORD=$(openssl rand -base64 18)
cat <<EOF >/etc/defguard/core.conf
DEFGUARD_DB_HOST=localhost
DEFGUARD_DB_PORT=5432
DEFGUARD_DB_NAME=defguard
DEFGUARD_DB_USER=defguard
DEFGUARD_DB_PASSWORD=${PG_DB_PASS}

DEFGUARD_URL=http://${LOCAL_IP}:8000
DEFGUARD_HTTP_PORT=8000
DEFGUARD_GRPC_PORT=50055

DEFGUARD_DEFAULT_ADMIN_PASSWORD=${DEFGUARD_ADMIN_PASSWORD}
DEFGUARD_COOKIE_INSECURE=true
DEFGUARD_LOG_LEVEL=info
EOF
chown root:defguard /etc/defguard/core.conf
chmod 640 /etc/defguard/core.conf
systemctl restart defguard
msg_ok "Configured Defguard"

motd_ssh
customize
cleanup_lxc

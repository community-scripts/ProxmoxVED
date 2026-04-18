#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Decrux (devdecrux)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/devdecrux/pocketr-app

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

JAVA_VERSION="25" setup_java
POCKETR_START_SERVICE="yes"

if [[ "${POCKETR_DB_MODE:-internal}" == "internal" ]]; then
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="pocketr_db" PG_DB_USER="pocketr_user" setup_postgresql_db
  POCKETR_DB_URL="jdbc:postgresql://127.0.0.1:5432/${PG_DB_NAME}"
  POCKETR_DB_USERNAME="${PG_DB_USER}"
  POCKETR_DB_PASSWORD="${PG_DB_PASS}"
else
  POCKETR_DB_URL="${POCKETR_DB_URL:-${DB_URL:-}}"
  POCKETR_DB_USERNAME="${POCKETR_DB_USERNAME:-${DB_USERNAME:-}}"
  POCKETR_DB_PASSWORD="${POCKETR_DB_PASSWORD:-${DB_PASSWORD:-}}"

  if [[ -z "${POCKETR_DB_URL}" || -z "${POCKETR_DB_USERNAME}" || -z "${POCKETR_DB_PASSWORD}" ]]; then
    msg_error "External PostgreSQL requires POCKETR_DB_URL, POCKETR_DB_USERNAME, and POCKETR_DB_PASSWORD"
    exit 1
  fi

  msg_info "Installing PostgreSQL Client"
  install_packages_with_retry postgresql-client
  msg_ok "Installed PostgreSQL Client"

  msg_info "Checking External Database"
  if [[ "${POCKETR_DB_URL}" != jdbc:postgresql://* ]]; then
    msg_error "POCKETR_DB_URL must use the jdbc:postgresql:// format"
    exit 1
  fi
  if ! PGPASSWORD="${POCKETR_DB_PASSWORD}" $STD psql "${POCKETR_DB_URL#jdbc:}" -U "${POCKETR_DB_USERNAME}" -v ON_ERROR_STOP=1 -c "SELECT 1"; then
    POCKETR_START_SERVICE="no"
    mkdir -p /opt/pocketr
    cat <<EOF >/opt/pocketr/.service-not-started
External PostgreSQL is not reachable, database is missing, or credentials are invalid.
Edit /opt/pocketr/.env, then run: systemctl start pocketr
EOF
    msg_warn "External PostgreSQL is not reachable, database is missing, or credentials are invalid"
    msg_warn "Pocketr will be installed and enabled, but not started. Update /opt/pocketr/.env, then run: systemctl start pocketr"
  else
    msg_ok "Checked External Database"
  fi
fi

fetch_and_deploy_gh_release "pocketr" "devdecrux/pocketr-app" "singlefile" "latest" "/opt/pocketr" "pocketr-*.jar"

msg_info "Setting up Pocketr"
mkdir -p /opt/pocketr/data/avatars
cat <<EOF >/opt/pocketr/.env
SPRING_PROFILES_ACTIVE=prod
DB_URL=${POCKETR_DB_URL}
DB_USERNAME=${POCKETR_DB_USERNAME}
DB_PASSWORD=${POCKETR_DB_PASSWORD}
SERVER_PORT=8081
AVATAR_STORAGE_DIR=/opt/pocketr/data/avatars
APP_SECURITY_CSRF_COOKIE_PATH=/
EOF
msg_ok "Set up Pocketr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/pocketr.service
[Unit]
Description=Pocketr Budgeting App
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pocketr
EnvironmentFile=/opt/pocketr/.env
ExecStart=/usr/bin/java -jar /opt/pocketr/pocketr
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
if [[ "${POCKETR_START_SERVICE}" == "yes" ]]; then
  systemctl enable -q --now pocketr
  rm -f /opt/pocketr/.service-not-started
else
  systemctl enable -q pocketr
fi
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

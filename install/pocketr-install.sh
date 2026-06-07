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

case "${POCKETR_DB_MODE:-internal}" in
internal)
  POCKETR_PG_VERSION="${POCKETR_PG_VERSION:-${PG_VERSION:-}}"
  if [[ -n "${POCKETR_PG_VERSION}" && ! "${POCKETR_PG_VERSION}" =~ ^[0-9]+$ ]]; then
    msg_error "POCKETR_PG_VERSION must be a PostgreSQL major version number"
    exit 1
  fi
  if [[ -n "${POCKETR_PG_VERSION}" ]]; then
    PG_VERSION="${POCKETR_PG_VERSION}" setup_postgresql
  else
    setup_postgresql
  fi
  PG_DB_NAME="pocketr_db" PG_DB_USER="pocketr_user" PG_DB_SCHEMA_PERMS="true" setup_postgresql_db
  POCKETR_DB_URL="jdbc:postgresql://127.0.0.1:5432/${PG_DB_NAME}"
  POCKETR_DB_USERNAME="${PG_DB_USER}"
  POCKETR_DB_PASSWORD="${PG_DB_PASS}"
  ;;
external)
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
    msg_error "External PostgreSQL is not reachable, database is missing, or credentials are invalid"
    exit 1
  fi
  if ! PGPASSWORD="${POCKETR_DB_PASSWORD}" $STD psql "${POCKETR_DB_URL#jdbc:}" -U "${POCKETR_DB_USERNAME}" -v ON_ERROR_STOP=1 -c "CREATE TABLE public.pocketr_install_check (id integer); DROP TABLE public.pocketr_install_check;"; then
    msg_error "External PostgreSQL user must be able to create tables in the public schema"
    exit 1
  fi
  msg_ok "Checked External Database"
  ;;
*)
  msg_error "POCKETR_DB_MODE must be 'internal' or 'external'"
  exit 1
  ;;
esac

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
systemctl enable -q --now pocketr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

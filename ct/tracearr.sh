#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: durzo
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/connorgallopo/Tracearr

APP="Tracearr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
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
  if [[ ! -f /lib/systemd/system/tracearr.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "tracearr" "connorgallopo/Tracearr"; then
    msg_info "Stopping Services"
    systemctl stop tracearr postgresql redis
    msg_ok "Stopped Services"

    NODE_VERSION="22" NODE_MODULE="pnpm@10.24.0" setup_nodejs

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "tracearr" "connorgallopo/Tracearr" "tarball" "latest" "/opt/tracearr.build"

    msg_info "Building Tracearr"
    export TZ=$(cat /etc/timezone)
    cd /opt/tracearr.build
    $STD pnpm install --frozen-lockfile --force
    $STD pnpm turbo telemetry disable
    $STD pnpm turbo run build --no-daemon --filter=@tracearr/shared --filter=@tracearr/server --filter=@tracearr/web
    rm -rf /opt/tracearr
    mkdir -p /opt/tracearr/{packages/shared,apps/server,apps/web,apps/server/src/db}
    cp -rf package.json /opt/tracearr/
    cp -rf pnpm-workspace.yaml /opt/tracearr/
    cp -rf pnpm-lock.yaml /opt/tracearr/
    cp -rf apps/server/package.json /opt/tracearr/apps/server/
    cp -rf apps/server/dist /opt/tracearr/apps/server/dist
    cp -rf apps/web/dist /opt/tracearr/apps/web/dist
    cp -rf packages/shared/package.json /opt/tracearr/packages/shared/
    cp -rf packages/shared/dist /opt/tracearr/packages/shared/dist
    cp -rf apps/server/src/db/migrations /opt/tracearr/apps/server/src/db/migrations
    cp -rf data /opt/tracearr/data
    rm -rf /opt/tracearr.build
    cd /opt/tracearr
    $STD pnpm install --prod --frozen-lockfile
    $STD chown -R tracearr:tracearr /opt/tracearr
    msg_ok "Built Tracearr"

    msg_info "Configuring Tracearr"
    if [ ! -d /data/tracearr ]; then
      install -d -m 750 -o tracearr -g tracearr /data/tracearr
    fi

    if [ -f /data/tracearr/.jwt_secret ]; then
      export JWT_SECRET=$(cat /data/tracearr/.jwt_secret)
    else
      export JWT_SECRET=$(openssl rand -hex 32)
      echo "$JWT_SECRET" > /data/tracearr/.jwt_secret
      chmod 600 /data/tracearr/.jwt_secret
    fi
    if [ -f /data/tracearr/.cookie_secret ]; then
      export COOKIE_SECRET=$(cat /data/tracearr/.cookie_secret)
    else
      export COOKIE_SECRET=$(openssl rand -hex 32)
      echo "$COOKIE_SECRET" > /data/tracearr/.cookie_secret
      chmod 600 /data/tracearr/.cookie_secret
    fi
    if [ ! -f /root/tracearr.creds ]; then
      if [ -f /data/tracearr/.env ]; then
        PG_DB_NAME=$(grep 'DATABASE_URL=' /data/tracearr/.env | cut -d'/' -f4)
        PG_DB_USER=$(grep 'DATABASE_URL=' /data/tracearr/.env | cut -d'/' -f3 | cut -d':' -f1)
        PG_DB_PASS=$(grep 'DATABASE_URL=' /data/tracearr/.env | cut -d':' -f3 | cut -d'@' -f1)
        { echo "PostgreSQL Credentials"
          echo "Database: $PG_DB_NAME"
          echo "User: $PG_DB_USER"
          echo "Password: $PG_DB_PASS"
        } >/root/tracearr.creds
        msg_ok "Recreated tracearr.creds file from existing .env"
      else
        msg_error "No existing tracearr.creds or .env file found. Cannot configure database connection!"
        exit 1
      fi
    else
      PG_DB_NAME=$(grep 'Database:' /root/tracearr.creds | awk '{print $2}')
      PG_DB_USER=$(grep 'User:' /root/tracearr.creds | awk '{print $2}')
      PG_DB_PASS=$(grep 'Password:' /root/tracearr.creds | awk '{print $2}')
    fi
    cat <<EOF >/data/tracearr/.env
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
PORT=3000
HOST=0.0.0.0
NODE_ENV=production
TZ=${TZ}
LOG_LEVEL=info
JWT_SECRET=$JWT_SECRET
COOKIE_SECRET=$COOKIE_SECRET
APP_VERSION=$(cat /root/.tracearr)
#CORS_ORIGIN=http://localhost:5173
#MOBILE_BETA_MODE=true
EOF
    chmod 600 /data/tracearr/.env
    chown -R tracearr:tracearr /data/tracearr
    msg_ok "Configured Tracearr"

    msg_info "Starting Services"
    systemctl start postgresql redis tracearr
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
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

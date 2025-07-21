#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/ekke85/ProxmoxVED/refs/heads/dispatcharr/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: ekke85
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Dispatcharr/Dispatcharr

APP="Dispatcharr"
APP_NAME=${APP,,}
var_tags="${var_tags:-media;arr}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d "/opt/dispatcharr" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/Dispatcharr/Dispatcharr/releases/latest | jq -r '.tag_name' | sed 's/^v//')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_ok "Starting update"
    APP_DIR="/opt/dispatcharr"
    APP_USER="dispatcharr"
    APP_GROUP="dispatcharr"



    msg_info "Stopping $APP"
      systemctl stop dispatcharr-celery
      systemctl stop dispatcharr-celerybeat
      systemctl stop dispatcharr-daphne
      systemctl stop dispatcharr
    msg_ok "Stopped $APP"

    msg_info "Creating Backup"
    BACKUP_FILE="/opt/dispatcharr_$(date +%F).tar.gz"
    msg_info "Source and Database backup"
    set -o allexport
    source /etc/$APP_NAME/$APP_NAME.env
    set +o allexport
    PGPASSWORD=$POSTGRES_PASSWORD pg_dump -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB > /opt/$POSTGRES_DB-`date +%F`.sql
    $STD tar -czf "$BACKUP_FILE" /opt/dispatcharr /opt/Dispatcharr_version.txt /opt/$POSTGRES_DB-`date +%F`.sql &>/dev/null
    msg_ok "Backup Created"

    msg_info "Updating $APP to v${RELEASE}"
    rm -rf /opt/dispatcharr
    fetch_and_deploy_gh_release "dispatcharr" "Dispatcharr/Dispatcharr"
    chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
    sed -i 's/program\[\x27channel_id\x27\]/program["channel_id"]/g' "${APP_DIR}/apps/output/views.py"

    msg_ok "Dispatcharr Updated to $RELEASE"

    msg_info "Creating Python Virtual Environment"
    cd $APP_DIR
    python3 -m venv env
    source env/bin/activate
    $STD pip install --upgrade pip
    $STD pip install -r requirements.txt
    $STD pip install gunicorn
    ln -sf /usr/bin/ffmpeg $APP_DIR/env/bin/ffmpeg
    msg_ok "Python Environment Setup"

    msg_info "Building Frontend"
    cd $APP_DIR/frontend
    $STD npm install --legacy-peer-deps
    $STD npm run build
    msg_ok "Built Frontend"

    msg_info "Running Django Migrations"
    cd $APP_DIR
    source env/bin/activate
    set -o allexport
    source /etc/$APP_NAME/$APP_NAME.env
    set +o allexport
    $STD python manage.py migrate --noinput
    $STD python manage.py collectstatic --noinput
    msg_ok "Migrations Complete"

    msg_info "Starting $APP"
      systemctl start dispatcharr-celery
      systemctl start dispatcharr-celerybeat
      systemctl start dispatcharr-daphne
      systemctl start dispatcharr
    msg_ok "Started $APP"
    echo "${RELEASE}" > "/opt/${APP}_version.txt"

    msg_info "Cleaning Up"
    rm -rf /opt/$POSTGRES_DB-`date +%F`.sql
    msg_ok "Cleanup Completed"

    msg_ok "Update Successful, Backup saved to $BACKUP_FILE"

  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9191${CL}"

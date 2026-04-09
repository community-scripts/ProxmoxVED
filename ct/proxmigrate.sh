#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: csd440
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/backupassure/proxmigrate

APP="ProxMigrate"
var_tags="${var_tags:-proxmox;migration;vm;management;backup}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
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

  if [[ ! -d /opt/proxmigrate ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "proxmigrate" "backupassure/proxmigrate"; then
    msg_info "Stopping Services"
    systemctl stop proxmigrate-gunicorn proxmigrate-celery proxmigrate-daphne
    msg_ok "Stopped Services"

    msg_info "Updating ${APP}"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "proxmigrate" "backupassure/proxmigrate" "tarball"
    cd /opt/proxmigrate
    chown -R proxmigrate:proxmigrate /opt/proxmigrate
    sudo -u proxmigrate /opt/proxmigrate/venv/bin/pip install --quiet -r /opt/proxmigrate/requirements.txt
    sudo -u proxmigrate \
      DJANGO_SETTINGS_MODULE=proxmigrate.settings.production \
      /opt/proxmigrate/venv/bin/python /opt/proxmigrate/manage.py migrate --noinput \
      --settings=proxmigrate.settings.production
    sudo -u proxmigrate \
      DJANGO_SETTINGS_MODULE=proxmigrate.settings.production \
      /opt/proxmigrate/venv/bin/python /opt/proxmigrate/manage.py collectstatic --noinput \
      --settings=proxmigrate.settings.production
    msg_ok "Updated ${APP}"

    msg_info "Starting Services"
    systemctl start proxmigrate-gunicorn proxmigrate-celery proxmigrate-daphne
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:8443${CL}"
echo -e "${INFO}${YW} Default credentials: admin / Password! (forced change on first login)${CL}"

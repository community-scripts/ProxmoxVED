#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.paperless-ngx.com/

APP="Paperless-ngx"
var_tags="${var_tags:-document;management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
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
  if [[ ! -d /opt/paperless ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/paperless-ngx/paperless-ngx/releases/latest | jq -r .tag_name | sed 's/^v//')
  if [[ "${RELEASE}" != "$(cat ~/.paperless 2>/dev/null)" ]] || [[ ! -f ~/.paperless ]]; then
    PYTHON_VERSION="3.13" setup_uv
    fetch_and_deploy_gh_release "paperless" "paperless-ngx/paperless-ngx" "tarball" "latest" "/opt/paperless"
    fetch_and_deploy_gh_release "jbig2enc" "ie13/jbig2enc" "tarball" "latest" "/opt/jbig2enc"
    #setup_gs

    msg_info "Stopping all Paperless-ngx Services"
    systemctl stop paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue.service
    msg_ok "Stopped all Paperless-ngx Services"

    if grep -q "uv run" /etc/systemd/system/paperless-webserver.service; then
      msg_info "Updating to ${RELEASE}"
      cd /opt/paperless
      $STD uv sync --all-extras
      cd /opt/paperless/src
      $STD uv run -- python manage.py migrate
      msg_ok "Updated to ${RELEASE}"
    else
      msg_info "Migrating old Paperless-ngx installation to uv"
      rm -rf /opt/paperless/venv
      find /opt/paperless -name "__pycache__" -type d -exec rm -rf {} +
      declare -A PATCHES=(
        ["paperless-consumer.service"]="ExecStart=.*manage.py document_consumer|ExecStart=uv run -- python manage.py document_consumer"
        ["paperless-scheduler.service"]="ExecStart=celery|ExecStart=uv run -- celery"
        ["paperless-task-queue.service"]="ExecStart=celery|ExecStart=uv run -- celery"
        ["paperless-webserver.service"]="ExecStart=.*|ExecStart=uv run -- granian --interface asginl --ws \"paperless.asgi:application\""
      )
      for svc in "${!PATCHES[@]}"; do
        path=$(systemctl show -p FragmentPath "$svc" | cut -d= -f2)
        if [[ -n "$path" && -f "$path" ]]; then
          sed -i "s|${PATCHES[$svc]%|*}|${PATCHES[$svc]#*|}|" "$path"
          msg_ok "Patched $svc"
        else
          msg_error "Service file for $svc not found!"
        fi
      done
      $STD systemctl daemon-reexec
      $STD systemctl daemon-reload
      cd /opt/paperless
      $STD uv sync --all-extras
      cd /opt/paperless/src
      $STD uv run -- python manage.py migrate
      msg_ok "Paperless-ngx migration and update to ${RELEASE} completed"
    fi

    msg_info "Cleaning up"
    cd ~
    msg_ok "Cleaned"

    msg_info "Starting all Paperless-ngx Services"
    systemctl start paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue.service
    sleep 1
    msg_ok "Started all Paperless-ngx Services"
    msg_ok "Updated Successfully!\n"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"

#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
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
  RELEASE=$(curl -fsSL https://api.github.com/repos/paperless-ngx/paperless-ngx/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping Paperless services"
    systemctl stop paperless-{webserver,scheduler,task-queue,consumer}
    msg_ok "Stopped Paperless services"

    BACKUP_DIR="/opt/paperless-backup-$(date +%F_%T | tr ':' '-')"

    MIGRATION_NEEDED=0
    if ! command -v uv &>/dev/null || [[ ! -d /opt/paperless/.venv ]]; then
      MIGRATION_NEEDED=1
      msg_info "uv not found or missing venv, migrating..."
      setup_uv
      $STD uv venv /opt/paperless/.venv
      source /opt/paperless/.venv/bin/activate
      $STD uv sync --all-extras
    fi

    BACKUP_DIR="/opt/paperless-backup-$(date +%F_%T | tr ':' '-')"

    setup_gs
    setup_uv

    msg_info "Backing up Paperless folders"
    mkdir -p "$BACKUP_DIR"
    for d in consume data media; do
      [[ -d "/opt/paperless/$d" ]] && mv "/opt/paperless/$d" "$BACKUP_DIR/"
    done
    [[ -f "/opt/paperless/paperless.conf" ]] && cp "/opt/paperless/paperless.conf" "$BACKUP_DIR/"
    msg_ok "Backup completed to $BACKUP_DIR"

    msg_info "Updating PaperlessNGX"
    RELEASE=$(curl -fsSL "https://api.github.com/repos/paperless-ngx/paperless-ngx/releases/latest" | grep 'tag_name' | cut -d '"' -f4)
    cd /tmp
    curl -fsSL "https://github.com/paperless-ngx/paperless-ngx/releases/download/$RELEASE/paperless-ngx-$RELEASE.tar.xz" -o paperless.tar.xz
    tar -xf paperless.tar.xz
    cp -r paperless-ngx/* /opt/paperless/
    rm -rf paperless.tar.xz paperless-ngx
    echo "$RELEASE" >/opt/paperless/Paperless-ngx_version.txt
    msg_ok "Updated Paperless-ngx to $RELEASE"

    for d in consume data media; do
      [[ -d "$BACKUP_DIR/$d" ]] && mv "$BACKUP_DIR/$d" "/opt/paperless/"
    done
    [[ ! -f "/opt/paperless/paperless.conf" && -f "$BACKUP_DIR/paperless.conf" ]] && cp "$BACKUP_DIR/paperless.conf" "/opt/paperless/paperless.conf"
    $STD uv venv /opt/paperless/.venv
    source /opt/paperless/.venv/bin/activate
    echo -e "source done"
    $STD uv sync --all-extras
    echo -e "uv sync done"
    source /opt/paperless/paperless.conf
    $STD /opt/paperless/.venv/bin/python3 /opt/paperless/src/manage.py migrate

    if [[ "$MIGRATION_NEEDED" == 1 ]]; then
      cat <<EOF >/etc/default/paperless
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
PNGX_CONTAINERIZED=0
UV_LINK_MODE=copy
EOF

      for svc in /etc/systemd/system/paperless-*.service; do
        sed -i \
          -e "s|^ExecStart=.*manage.py|ExecStart=/opt/paperless/.venv/bin/python3 manage.py|" \
          -e "s|^ExecStart=.*celery|ExecStart=/opt/paperless/.venv/bin/celery|" \
          -e "s|^ExecStart=.*granian|ExecStart=/opt/paperless/.venv/bin/granian|" \
          -e "/^WorkingDirectory=/a EnvironmentFile=/etc/default/paperless" "$svc"
      done
    fi

    systemctl daemon-reexec
    systemctl daemon-reload

    msg_info "Starting Paperless services"
    systemctl start paperless-{webserver,scheduler,task-queue,consumer}.service
    sleep 1
    msg_ok "All services restarted"
    msg_ok "Updated Successfully!\n"
    read -r -p "Remove backup directory at $BACKUP_DIR? [y/N]: " CLEANUP
    if [[ "$CLEANUP" =~ ^[Yy]$ ]]; then
      rm -rf "$BACKUP_DIR"
      msg_ok "Backup directory removed"
    else
      msg_info "Backup directory retained at $BACKUP_DIR"
    fi
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
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

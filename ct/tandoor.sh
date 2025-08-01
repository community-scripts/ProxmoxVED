#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://tandoor.dev/

APP="Tandoor"
var_tags="${var_tags:-recipes}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
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
  if [[ ! -d /opt/tandoor ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ ! -f ~/.tandoor ]]; then
    msg_error "v1 Installation found, please create an new LXC!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/TandoorRecipes/recipes/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat ~/.tandoor 2>/dev/null)" ]] || [[ ! -f ~/.tandoor ]]; then
    msg_info "Stopping $APP"
    systemctl stop tandoor
    msg_ok "Stopped $APP"

    msg_info "Creating Backup"
    BACKUP_FILE="/opt/tandoor_backup_$(date +%F).tar.gz"
    $STD tar -czf "$BACKUP_FILE" /opt/tandoor/{.env,start.sh} /opt/tandoor/database/ &>/dev/null
    mv /opt/tandoor/.env /opt/.env
    msg_ok "Backup Created"

    NODE_VERSION="20" NODE_MODULE="yarn@latest" setup_nodejs
    fetch_and_deploy_gh_release "tandoor" "TandoorRecipes/recipes" "tarball" "latest" "/opt/tandoor"
    PYTHON_VERSION="3.13" setup_uv

    msg_info "Updating $APP to ${RELEASE}"
    mkdir -p /opt/tandoor/{config,api,mediafiles,staticfiles}
    mv /opt/.env /opt/tandoor/.env
    cd /opt/tandoor
    $STD uv venv .venv --python=python3
    $STD uv pip install -r requirements.txt --python .venv/bin/python
    cd /opt/tandoor/vue3
    $STD yarn install
    $STD yarn build
    TANDOOR_VERSION="$(curl -s https://api.github.com/repos/TandoorRecipes/recipes/releases/latest | jq -r .tag_name)"
    cat <<EOF >/opt/tandoor/cookbook/version_info.py
TANDOOR_VERSION = "$TANDOOR_VERSION"
TANDOOR_REF = "bare-metal"
VERSION_INFO = []
EOF
    cd /opt/tandoor
    $STD /opt/tandoor/.venv/bin/python manage.py migrate
    $STD /opt/tandoor/.venv/bin/python manage.py collectstatic --no-input
    msg_ok "Updated $APP to ${RELEASE}"

    msg_info "Starting $APP"
    systemctl start tandoor
    systemctl reload nginx
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -rf "$BACKUP_FILE"
    msg_ok "Cleanup Completed"
    msg_ok "Update Successful"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8002${CL}"

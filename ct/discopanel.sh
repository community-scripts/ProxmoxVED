#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: DragoQC
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://discopanel.app/

APP="DiscoPanel"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8096}"
var_disk="${var_disk:-20}"
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

	if [[ ! -d "/opt/discopanel" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

	LATEST=$(curl -fsSL https://api.github.com/repos/nickheyer/discopanel/releases/latest \
		grep '"tag_name":' | cut -d'"' -f4)

	CURRENT=$(cat /opt/${APP}_version.txt 2>/dev/null || echo "none")

	if [[ "$LATEST" == "$CURRENT" ]]; then
    msg_ok "${APP} is already at ${LATEST}"
    exit
  fi

	msg_info "Updating ${APP} from ${CURRENT} → ${LATEST}"

	systemctl stop "${APP}"

	msg_info "Creating Backup"
  tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" "/opt/${APP}"
  msg_ok "Backup Created"

	rm -rf /opt/${APP}

	msg_info "Downloading ${APP} ${LATEST}"
  git clone --branch "$LATEST" --depth 1 \
      https://github.com/nickheyer/discopanel.git \
      /opt/${APP}
  msg_ok "Downloaded ${APP} ${LATEST}"


	msg_info "Building frontend"
  cd /opt/${APP}/web/discopanel || exit
  npm install
  npm run build
  msg_ok "Frontend Built"

	msg_info "Building backend"
  cd /opt/${APP} || exit
  go build -o discopanel cmd/discopanel/main.go
  msg_ok "Backend Built"

	echo "$LATEST" >/opt/${APP}_version.txt

	systemctl start "${APP}"
  msg_ok "Update Successful → now at ${LATEST}"
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"

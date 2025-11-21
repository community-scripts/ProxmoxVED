#!/usr/bin/env bash
source <(curl -fsSL "${BASE_URL-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: gpt-5-codex
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/openbao/openbao

APP="OpenBao"
var_tags="${var_tags:-secrets;vault}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
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

  if [[ ! -f /usr/local/bin/openbao ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT_VERSION="$(cat /opt/openbao_version.txt 2>/dev/null || echo '')"
  LATEST_VERSION="$(cat "$HOME/.bao" 2>/dev/null || echo '')"

  # If we don't have latest version cached, fetch it
  if [[ -z "$LATEST_VERSION" ]]; then
    LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/openbao/openbao/releases/latest 2>/dev/null | jq -r '.tag_name' | sed 's/^v//')
  fi

  if [[ -z "${LATEST_VERSION}" ]]; then
    msg_error "Unable to determine the latest release version."
    exit 1
  fi

  if [[ ! -f /opt/openbao_version.txt ]] || [[ "${LATEST_VERSION}" != "${CURRENT_VERSION}" ]]; then
    msg_info "Updating ${APP} to v${LATEST_VERSION}"

    msg_info "Stopping ${APP}"
    systemctl stop openbao
    msg_ok "Stopped ${APP}"

    msg_info "Creating Backup"
    tar -czf "/opt/openbao_backup_$(date +%F).tar.gz" \
      /etc/openbao /var/lib/openbao /var/log/openbao
    msg_ok "Backup Created"

    msg_info "Downloading and installing new version"

    fetch_and_deploy_gh_release "bao" "openbao/openbao" "binary" "latest" "" "bao_*_linux_amd64.deb"

    # Ensure symlink exists
    if [[ -f /usr/bin/bao ]]; then
      ln -sf /usr/bin/bao /usr/local/bin/openbao
    else
      msg_error "OpenBao binary not found after installation"
      systemctl start openbao
      exit 1
    fi
    msg_ok "Installed new version"

    msg_info "Starting ${APP}"
    systemctl start openbao
    msg_ok "Started ${APP}"

    RELEASE=$(bao version | grep -oP 'Bao v\K[0-9.]+' || echo "${LATEST_VERSION}")
    echo "${RELEASE}" >/opt/openbao_version.txt
    msg_ok "Updated to v${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at v${CURRENT_VERSION}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8200${CL}"

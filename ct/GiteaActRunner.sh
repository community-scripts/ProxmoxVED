#!/usr/bin/env bash
# shellcheck source=/dev/null
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://gitea.com/gitea/act_runner

APP="GiteaActRunner"
var_tags="${var_tags:-ci-cd;gitea;runner}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/act_runner ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  RELEASE=$(curl -fsSL https://gitea.com/api/v1/repos/gitea/act_runner/releases | jq -r '.[0].tag_name')
  if [[ -z "${RELEASE}" || "${RELEASE}" == "null" ]]; then
    msg_error "Unable to fetch latest release tag"
    exit 1
  fi

  if [[ -f /opt/${APP}_version.txt && "${RELEASE}" == "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
    exit
  fi

  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l)  ARCH="armv7" ;;
    *) msg_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

  VERSION="${RELEASE#v}"

  msg_info "Stopping ${APP}"
  rc-service gitea-runner stop || true
  msg_ok "Stopped ${APP}"

  msg_info "Backing up current binary"
  cp /usr/local/bin/act_runner /usr/local/bin/act_runner.bak
  msg_ok "Backup created at /usr/local/bin/act_runner.bak"

  msg_info "Updating ${APP} to ${RELEASE}"
  curl -fsSL "https://gitea.com/gitea/act_runner/releases/download/${RELEASE}/act_runner-${VERSION}-linux-${ARCH}" -o /usr/local/bin/act_runner
  chmod +x /usr/local/bin/act_runner
  echo "${RELEASE}" >/opt/${APP}_version.txt
  msg_ok "Updated ${APP} to ${RELEASE}"

  msg_info "Starting ${APP}"
  rc-service gitea-runner start
  msg_ok "Started ${APP}"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Run 'act_runner register' inside the LXC to register the runner with your Gitea instance.${CL}"

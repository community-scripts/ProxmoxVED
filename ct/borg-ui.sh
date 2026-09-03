#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/karanhudia/borg-ui

APP="Borg-UI"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2133}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/borg-ui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "borg-ui" "karanhudia/borg-ui"; then
    msg_info "Stopping Service"
    systemctl stop borg-ui
    msg_ok "Stopped Service"

    create_backup /opt/borg-ui/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "borg-ui" "karanhudia/borg-ui" "tarball"

    restore_backup

    BORG_UI_VERSION=$(cat "$HOME/.borg-ui" 2>/dev/null)
    if [[ -n "$BORG_UI_VERSION" ]]; then
      if grep -q '^APP_VERSION=' /opt/borg-ui/.env; then
        sed -i "s|^APP_VERSION=.*|APP_VERSION=${BORG_UI_VERSION}|" /opt/borg-ui/.env
      else
        echo "APP_VERSION=${BORG_UI_VERSION}" >>/opt/borg-ui/.env
      fi
    fi

    RUNTIME_ENV="/opt/borg-ui/docker/runtime-base.env"
    BORG1_VERSION=$(sed -n 's/^BORG1_VERSION=//p' "$RUNTIME_ENV" 2>/dev/null | tr -d ' \r')
    BORG2_VERSION=$(sed -n 's/^BORG2_VERSION=//p' "$RUNTIME_ENV" 2>/dev/null | tr -d ' \r')
    BORGSTORE_VERSION=$(sed -n 's/^BORGSTORE_VERSION=//p' "$RUNTIME_ENV" 2>/dev/null | tr -d ' \r')
    RCLONE_VERSION=$(sed -n 's/^RCLONE_VERSION=//p' "$RUNTIME_ENV" 2>/dev/null | tr -d ' \r')
    BORG_PYTHON=$(sed -n 's/^PYTHON_VERSION=//p' "$RUNTIME_ENV" 2>/dev/null | tr -d ' \r')
    if [[ -z "$BORG1_VERSION" || -z "$BORG2_VERSION" || -z "$BORGSTORE_VERSION" || -z "$RCLONE_VERSION" || -z "$BORG_PYTHON" ]]; then
      msg_error "Could not read the pinned versions from ${RUNTIME_ENV}"
      exit 1
    fi

    if [[ "$(cat /opt/borg1-venv/.pinned_version 2>/dev/null)" != "$BORG1_VERSION" ]]; then
      msg_info "Installing Borg ${BORG1_VERSION} (Patience)"
      $STD uv venv --python "$BORG_PYTHON" /opt/borg1-venv
      $STD uv pip install --python /opt/borg1-venv pyfuse3 "borgbackup==${BORG1_VERSION}"
      echo "$BORG1_VERSION" >/opt/borg1-venv/.pinned_version
      ln -sf /opt/borg1-venv/bin/borg /usr/local/bin/borg
      msg_ok "Installed Borg ${BORG1_VERSION}"
    fi

    if [[ "$(cat /opt/borg2-venv/.pinned_version 2>/dev/null)" != "${BORG2_VERSION}-${BORGSTORE_VERSION}" ]]; then
      msg_info "Installing Borg ${BORG2_VERSION} (Patience)"
      $STD uv venv --python "$BORG_PYTHON" /opt/borg2-venv
      $STD uv pip install --python /opt/borg2-venv pyfuse3 "borgbackup==${BORG2_VERSION}" "borgstore[rclone,sftp,rest,s3,blake3]==${BORGSTORE_VERSION}"
      echo "${BORG2_VERSION}-${BORGSTORE_VERSION}" >/opt/borg2-venv/.pinned_version
      ln -sf /opt/borg2-venv/bin/borg /usr/local/bin/borg2
      msg_ok "Installed Borg ${BORG2_VERSION}"
    fi

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rclone" "rclone/rclone" "prebuild" "v${RCLONE_VERSION}" "/opt/rclone" "rclone-v${RCLONE_VERSION}-linux-$(arch_resolve amd64 arm64).zip"
    ln -sf /opt/rclone/rclone /usr/local/bin/rclone

    msg_info "Building Frontend"
    cd /opt/borg-ui/frontend
    $STD npm ci
    $STD npm run build
    rm -rf /opt/borg-ui/app/static
    mkdir -p /opt/borg-ui/app/static
    cp -r /opt/borg-ui/frontend/build/* /opt/borg-ui/app/static/
    msg_ok "Built Frontend"

    msg_info "Updating Python Environment"
    cd /opt/borg-ui
    $STD uv venv --python "$BORG_PYTHON" /opt/borg-ui/.venv
    $STD uv pip install --python /opt/borg-ui/.venv -r requirements.txt
    msg_ok "Updated Python Environment"

    msg_info "Starting Service"
    systemctl start borg-ui
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8081${CL}"

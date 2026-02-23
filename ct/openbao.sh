#!/usr/bin/env bash
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Yamon
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.openbao.org/

APP="openbao"
var_tags="${var_tags:-security;secrets;vault}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -x /usr/local/bin/bao || ! -f /etc/systemd/system/openbao.service || ! -f /etc/openbao.d/openbao.hcl ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Debian LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Debian LXC"

  local ARCH RELEASE TMP_DIR TS BACKUP_BIN BACKUP_VER LISTENER_PORT HEALTH_URL OPENBAO_ASSET
  ARCH="$(dpkg --print-architecture)"
  case "${ARCH}" in
  amd64)
    ARCH="x86_64"
    OPENBAO_ASSET="bao_*_Linux_x86_64.tar.gz"
    ;;
  arm64)
    ARCH="arm64"
    OPENBAO_ASSET="bao_*_Linux_arm64.tar.gz"
    ;;
  *)
    msg_error "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
  esac

  if check_for_gh_release "openbao" "openbao/openbao"; then
    TMP_DIR="$(mktemp -d)"
    TS="$(date +%Y%m%d-%H%M%S)"
    BACKUP_BIN="/opt/openbao/backups/bao-${TS}"
    BACKUP_VER="$(cat /opt/openbao/VERSION 2>/dev/null || echo "unknown")"
    mkdir -p /opt/openbao/backups
    cp -a /usr/local/bin/bao "${BACKUP_BIN}"

    msg_info "Stopping Service"
    systemctl stop openbao
    msg_ok "Stopped Service"

    msg_info "Updating OpenBao"
    if ! CLEAN_INSTALL=1 fetch_and_deploy_gh_release "openbao" "openbao/openbao" "prebuild" "latest" "${TMP_DIR}" "${OPENBAO_ASSET}"; then
      msg_error "Failed downloading/deploying OpenBao"
      rm -rf "${TMP_DIR}"
      if ! systemctl start openbao; then
        msg_error "Failed to restart previous OpenBao service state"
      fi
      exit 1
    fi
    RELEASE="$(cat ~/.openbao 2>/dev/null || echo "unknown")"
    install -m 755 "${TMP_DIR}/bao" /usr/local/bin/bao
    echo "${RELEASE}" >/opt/openbao/VERSION
    rm -rf "${TMP_DIR}"
    msg_ok "Updated OpenBao"

    msg_info "Starting Service"
    systemctl start openbao

    msg_info "Running Health Check"
    LISTENER_PORT="$(awk -F'"' '/^[[:space:]]*address[[:space:]]*=/{print $2; exit}' /etc/openbao.d/openbao.hcl | awk -F: '{print $NF}')"
    HEALTH_URL="http://127.0.0.1:${LISTENER_PORT:-8200}/v1/sys/health"
    HEALTH_CODE=""
    for _ in {1..30}; do
      if ! HEALTH_CODE="$(curl -sS -o /dev/null -w "%{http_code}" "${HEALTH_URL}")"; then
        HEALTH_CODE="000"
      fi
      case "${HEALTH_CODE}" in
      200 | 429 | 472 | 473 | 501) break ;;
      esac
      sleep 2
    done
    case "${HEALTH_CODE}" in
    200 | 429 | 472 | 473 | 501)
      msg_ok "Started Service (HTTP ${HEALTH_CODE})"
      ;;
    *)
      msg_error "Update health check failed (HTTP ${HEALTH_CODE:-000}), rolling back to ${BACKUP_VER}"
      install -m 755 "${BACKUP_BIN}" /usr/local/bin/bao
      [[ "${BACKUP_VER}" != "unknown" ]] && echo "${BACKUP_VER}" >/opt/openbao/VERSION
      if ! systemctl restart openbao; then
        msg_error "Rollback restart failed. Manual recovery required."
      fi
      exit 1
      ;;
    esac
  else
    msg_ok "OpenBao is already up to date"
  fi

  LISTENER_PORT="$(awk -F'"' '/^[[:space:]]*address[[:space:]]*=/{print $2; exit}' /etc/openbao.d/openbao.hcl | awk -F: '{print $NF}')"
  msg_warn "OpenBao may require unseal after restart. Verify with: BAO_ADDR=http://127.0.0.1:${LISTENER_PORT:-8200} bao status"
  msg_warn "This helper installs OpenBao quickly, but production hardening (TLS, policy, audit, backup) is still required."
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8200${CL}"
echo -e "${INFO}${YW} Post-install setup instructions:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}export BAO_ADDR=http://127.0.0.1:8200${CL}"
echo -e "${TAB}${GATEWAY}${BGN}bao operator init${CL}"
echo -e "${TAB}${GATEWAY}${BGN}bao operator unseal${CL}"
echo -e "${INFO}${YW} Security warning:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}HTTP is enabled by default (tls_disable=true). Configure TLS before production use.${CL}"

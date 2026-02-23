#!/usr/bin/env bash
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Yamon
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.langflow.org/

APP="Langflow"
var_tags="${var_tags:-ai;interface}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-12288}"
var_disk="${var_disk:-16}"
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

  if [[ ! -d /opt/langflow || ! -f /etc/systemd/system/langflow.service || ! -x /opt/langflow/.venv/bin/python ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local TS BACKUP_DIR OLD_VERSION TARGET_VERSION
  TS="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="/opt/langflow/backups/${TS}"
  TARGET_VERSION="${LANGFLOW_TARGET_VERSION:-latest}"
  OLD_VERSION="$([ -x /opt/langflow/.venv/bin/python ] && /opt/langflow/.venv/bin/python -m pip show langflow 2>/dev/null | awk '/^Version:/ {print $2}')"
  msg_info "Installed Version: ${OLD_VERSION:-unknown}"
  if [[ "${TARGET_VERSION}" == "latest" ]] && ! check_for_gh_release "langflow" "langflow-ai/langflow"; then
    msg_ok "Langflow is already up to date"
    exit
  fi

  msg_info "Preparing Backup"
  mkdir -p "${BACKUP_DIR}"
  if [[ -f /opt/langflow/.env ]]; then
    cp -a /opt/langflow/.env "${BACKUP_DIR}/.env"
  fi
  if compgen -G "/opt/langflow/data/langflow.db*" >/dev/null; then
    cp -a /opt/langflow/data/langflow.db* "${BACKUP_DIR}/"
  fi
  msg_ok "Backup saved to ${BACKUP_DIR}"

  msg_info "Stopping Service"
  systemctl stop langflow
  msg_ok "Stopped Service"

  UV_PYTHON="3.12" setup_uv
  UV_CONCURRENT_DOWNLOADS="${UV_CONCURRENT_DOWNLOADS:-2}"
  UV_CONCURRENT_BUILDS="${UV_CONCURRENT_BUILDS:-1}"
  UV_CONCURRENT_INSTALLS="${UV_CONCURRENT_INSTALLS:-1}"
  LANGFLOW_NO_CACHE="${LANGFLOW_NO_CACHE:-false}"
  UV_CACHE_ARGS=()
  if [[ "${LANGFLOW_NO_CACHE,,}" == "true" || "${LANGFLOW_NO_CACHE}" == "1" ]]; then
    UV_CACHE_ARGS+=(--no-cache)
  fi

  msg_info "Pinning CPU Torch"
  if ! $STD env \
    UV_CONCURRENT_DOWNLOADS="${UV_CONCURRENT_DOWNLOADS}" \
    UV_CONCURRENT_BUILDS="${UV_CONCURRENT_BUILDS}" \
    UV_CONCURRENT_INSTALLS="${UV_CONCURRENT_INSTALLS}" \
    uv pip install --python /opt/langflow/.venv/bin/python "${UV_CACHE_ARGS[@]}" \
    --index-strategy unsafe-best-match \
    --index-url https://download.pytorch.org/whl/cpu \
    --extra-index-url https://pypi.org/simple \
    "torch==2.8.0+cpu"; then
    msg_error "Failed to install CPU torch"
    exit 1
  fi
  msg_ok "Pinned CPU Torch"

  msg_info "Updating Langflow (${TARGET_VERSION})"
  if [[ "${TARGET_VERSION}" == "latest" ]]; then
    if ! $STD env \
      UV_CONCURRENT_DOWNLOADS="${UV_CONCURRENT_DOWNLOADS}" \
      UV_CONCURRENT_BUILDS="${UV_CONCURRENT_BUILDS}" \
      UV_CONCURRENT_INSTALLS="${UV_CONCURRENT_INSTALLS}" \
      uv pip install --python /opt/langflow/.venv/bin/python "${UV_CACHE_ARGS[@]}" --upgrade langflow; then
      msg_error "Langflow update failed"
      if [[ -n "${OLD_VERSION}" ]]; then
        msg_info "Rolling back to ${OLD_VERSION}"
        $STD env \
          UV_CONCURRENT_DOWNLOADS="${UV_CONCURRENT_DOWNLOADS}" \
          UV_CONCURRENT_BUILDS="${UV_CONCURRENT_BUILDS}" \
          UV_CONCURRENT_INSTALLS="${UV_CONCURRENT_INSTALLS}" \
          uv pip install --python /opt/langflow/.venv/bin/python "${UV_CACHE_ARGS[@]}" "langflow==${OLD_VERSION}"
      fi
      if [[ -f "${BACKUP_DIR}/.env" ]]; then
        cp -a "${BACKUP_DIR}/.env" /opt/langflow/.env
      fi
      if compgen -G "${BACKUP_DIR}/langflow.db*" >/dev/null; then
        cp -a "${BACKUP_DIR}/langflow.db"* /opt/langflow/data/
      fi
      if ! systemctl start langflow; then
        msg_error "Failed to start service after rollback"
      fi
      exit 1
    fi
  else
    if ! $STD env \
      UV_CONCURRENT_DOWNLOADS="${UV_CONCURRENT_DOWNLOADS}" \
      UV_CONCURRENT_BUILDS="${UV_CONCURRENT_BUILDS}" \
      UV_CONCURRENT_INSTALLS="${UV_CONCURRENT_INSTALLS}" \
      uv pip install --python /opt/langflow/.venv/bin/python "${UV_CACHE_ARGS[@]}" "langflow==${TARGET_VERSION}"; then
      msg_error "Langflow update to ${TARGET_VERSION} failed"
      if [[ -n "${OLD_VERSION}" ]]; then
        msg_info "Rolling back to ${OLD_VERSION}"
        $STD env \
          UV_CONCURRENT_DOWNLOADS="${UV_CONCURRENT_DOWNLOADS}" \
          UV_CONCURRENT_BUILDS="${UV_CONCURRENT_BUILDS}" \
          UV_CONCURRENT_INSTALLS="${UV_CONCURRENT_INSTALLS}" \
          uv pip install --python /opt/langflow/.venv/bin/python "${UV_CACHE_ARGS[@]}" "langflow==${OLD_VERSION}"
      fi
      if [[ -f "${BACKUP_DIR}/.env" ]]; then
        cp -a "${BACKUP_DIR}/.env" /opt/langflow/.env
      fi
      if compgen -G "${BACKUP_DIR}/langflow.db*" >/dev/null; then
        cp -a "${BACKUP_DIR}/langflow.db"* /opt/langflow/data/
      fi
      if ! systemctl start langflow; then
        msg_error "Failed to start service after rollback"
      fi
      exit 1
    fi
  fi
  msg_ok "Updated Langflow"

  msg_info "Starting Service"
  systemctl start langflow

  if [[ "$(systemctl is-active langflow)" != "active" ]]; then
    msg_error "Service failed to start"
    if [[ -n "${OLD_VERSION}" ]]; then
      msg_info "Rolling back to ${OLD_VERSION}"
      $STD env \
        UV_CONCURRENT_DOWNLOADS="${UV_CONCURRENT_DOWNLOADS}" \
        UV_CONCURRENT_BUILDS="${UV_CONCURRENT_BUILDS}" \
        UV_CONCURRENT_INSTALLS="${UV_CONCURRENT_INSTALLS}" \
        uv pip install --python /opt/langflow/.venv/bin/python "${UV_CACHE_ARGS[@]}" "langflow==${OLD_VERSION}"
      if [[ -f "${BACKUP_DIR}/.env" ]]; then
        cp -a "${BACKUP_DIR}/.env" /opt/langflow/.env
      fi
      if compgen -G "${BACKUP_DIR}/langflow.db*" >/dev/null; then
        cp -a "${BACKUP_DIR}/langflow.db"* /opt/langflow/data/
      fi
      if ! systemctl restart langflow; then
        msg_error "Failed to restart service after rollback"
      fi
    fi
    exit 1
  fi

  msg_info "Running Health Check"
  ensure_dependencies curl
  if command -v curl >/dev/null 2>&1; then
    for _ in {1..30}; do
      if curl -fsS http://127.0.0.1:7860/ >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
    if ! curl -fsS http://127.0.0.1:7860/ >/dev/null 2>&1; then
      msg_error "Health check failed. Check logs: journalctl -u langflow -n 100"
      exit 1
    fi
  else
    msg_info "curl not available, skipping HTTP health check"
  fi
  msg_ok "Health check passed"
  msg_info "If migration errors occur, review Langflow docs before using 'langflow migration --fix'"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7860${CL}"
echo -e "${INFO}${YW} Post-install credential location:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/opt/langflow/.env${CL}"

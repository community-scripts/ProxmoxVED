#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: andrewtryder
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/andrewtryder/unifi-netwatcher

APP="NetWatcher"
var_tags="${var_tags:-network;unifi;monitoring;security}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/netwatcher/netwatcher.env ]] || [[ ! -f /etc/systemd/system/netwatcher.service ]] || [[ ! -L /opt/netwatcher/current ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if ! check_for_gh_release "netwatcher" "andrewtryder/unifi-netwatcher"; then
    exit
  fi

  local new_ver old_target old_ver release_dir stamp backup_dir
  new_ver="$(get_latest_github_release "andrewtryder/unifi-netwatcher")"
  [[ -n "$new_ver" ]] || {
    msg_error "Could not resolve latest NetWatcher release"
    exit 1
  }
  old_target="$(readlink -f /opt/netwatcher/current)"
  old_ver="$(basename "$old_target")"

  if [[ "$old_ver" == "$new_ver" ]]; then
    msg_ok "Already up to date ($new_ver)"
    exit
  fi

  release_dir="/opt/netwatcher/releases/${new_ver}"
  if [[ -d "$release_dir" ]]; then
    msg_info "Removing incomplete release directory ${release_dir}"
    rm -rf "$release_dir"
  fi

  # Use "latest" so GitHub resolves the real tag name (e.g. v0.3.0).
  fetch_and_deploy_gh_release "netwatcher" "andrewtryder/unifi-netwatcher" "tarball" "latest" "$release_dir"

  if [[ ! -f "${release_dir}/app/web/static/app.css" ]] || [[ ! -f "${release_dir}/app/web/static/js/htmx.min.js" ]]; then
    msg_error "Release ${new_ver} is missing built static assets (app.css / htmx.min.js)"
    rm -rf "$release_dir"
    exit 1
  fi

  msg_info "Installing Python dependencies (${new_ver})"
  cd "$release_dir" || exit 1
  $STD uv sync --frozen --no-dev
  chown -R root:root "$release_dir"
  find "$release_dir" -type d -exec chmod 755 {} +
  find "$release_dir" -type f -exec chmod 644 {} +
  chmod -R a+x "${release_dir}/.venv/bin"
  $STD "${release_dir}/.venv/bin/python" -c "import uvicorn, alembic, app.main"
  msg_ok "Installed Python dependencies"

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_dir="/var/lib/netwatcher/backups/${stamp}"
  msg_info "Creating pre-update backup"
  install -d -m 0700 -o netwatcher -g netwatcher /var/lib/netwatcher/backups
  install -d -m 0700 -o root -g root "$backup_dir"
  cp -a /etc/netwatcher/netwatcher.env "$backup_dir/netwatcher.env"
  if [[ -f /var/lib/netwatcher/netwatcher.db ]]; then
    cp -a /var/lib/netwatcher/netwatcher.db "$backup_dir/netwatcher.db"
    shopt -s nullglob
    for wal in /var/lib/netwatcher/netwatcher.db-*; do
      cp -a "$wal" "$backup_dir/"
    done
    shopt -u nullglob
  fi
  if [[ -f /var/lib/netwatcher/app-secret.key ]]; then
    install -m 0600 -o root -g root /var/lib/netwatcher/app-secret.key "$backup_dir/app-secret.key"
  fi
  printf '%s\n' "$old_target" >"$backup_dir/previous-release"
  chmod -R go-rwx "$backup_dir"
  msg_ok "Created backup at ${backup_dir}"

  msg_info "Stopping Service"
  systemctl stop netwatcher
  msg_ok "Stopped Service"

  rollback_update() {
    msg_error "Update failed — rolling back to ${old_ver}"
    systemctl stop netwatcher >/dev/null 2>&1 || true
    if [[ -f "$backup_dir/netwatcher.db" ]]; then
      cp -a "$backup_dir/netwatcher.db" /var/lib/netwatcher/netwatcher.db
      chown netwatcher:netwatcher /var/lib/netwatcher/netwatcher.db
      chmod 0600 /var/lib/netwatcher/netwatcher.db
      shopt -s nullglob
      for wal in /var/lib/netwatcher/netwatcher.db-*; do
        rm -f "$wal"
      done
      for wal in "$backup_dir"/netwatcher.db-*; do
        cp -a "$wal" /var/lib/netwatcher/
        chown netwatcher:netwatcher "/var/lib/netwatcher/$(basename "$wal")"
        chmod 0600 "/var/lib/netwatcher/$(basename "$wal")"
      done
      shopt -u nullglob
    fi
    if [[ -f "$backup_dir/app-secret.key" ]]; then
      install -m 0600 -o netwatcher -g netwatcher "$backup_dir/app-secret.key" /var/lib/netwatcher/app-secret.key
    fi
    if [[ -f "$backup_dir/netwatcher.env" ]]; then
      install -m 0640 -o root -g netwatcher "$backup_dir/netwatcher.env" /etc/netwatcher/netwatcher.env
    fi
    ln -sfn "$old_target" /opt/netwatcher/current
    systemctl start netwatcher
    for _ in $(seq 1 60); do
      if curl -fsS http://127.0.0.1:8080/readyz >/dev/null 2>&1; then
        msg_ok "Rolled back to ${old_ver} and /readyz is healthy"
        return 0
      fi
      sleep 1
    done
    msg_error "Rollback started ${old_ver} but /readyz did not become healthy"
    return 1
  }

  msg_info "Running database migrations"
  set -a
  # shellcheck source=/dev/null
  source /etc/netwatcher/netwatcher.env
  set +a
  if ! (
    cd "$release_dir" || exit 1
    runuser -u netwatcher --preserve-environment -- \
      "${release_dir}/.venv/bin/alembic" upgrade head
  ); then
    rollback_update
    exit 1
  fi
  msg_ok "Ran database migrations"

  msg_info "Activating release ${new_ver}"
  ln -sfn "$release_dir" /opt/netwatcher/current
  msg_ok "Activated ${new_ver}"

  msg_info "Starting Service"
  systemctl start netwatcher
  local ready=0
  for _ in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:8080/readyz >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "$ready" -ne 1 ]]; then
    rollback_update
    exit 1
  fi
  msg_ok "Started Service (/readyz OK)"

  # Retain previous release for rollback; prune older ones (keep newest 2 dirs + current).
  msg_info "Pruning obsolete releases and backups"
  local keep_dirs=("$release_dir" "$old_target")
  shopt -s nullglob
  for d in /opt/netwatcher/releases/*; do
    local keep=0
    for k in "${keep_dirs[@]}"; do
      [[ "$(readlink -f "$d")" == "$(readlink -f "$k")" ]] && keep=1 && break
    done
    if [[ "$keep" -eq 0 ]]; then
      rm -rf "$d"
    fi
  done
  mapfile -t backup_list < <(ls -1dt /var/lib/netwatcher/backups/* 2>/dev/null || true)
  if ((${#backup_list[@]} > 3)); then
    for ((i = 3; i < ${#backup_list[@]}; i++)); do
      rm -rf "${backup_list[$i]}"
    done
  fi
  shopt -u nullglob
  msg_ok "Pruned obsolete releases/backups"

  msg_ok "Updated successfully to ${new_ver}!"
  echo -e "${INFO}${YW}Previous release retained at:${CL} ${old_target}"
  echo -e "${INFO}${YW}Backup retained at:${CL} ${backup_dir}"
  echo -e "${INFO}${YW}Database and app-secret.key must be restored together.${CL}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}NetWatcher URL:${CL} ${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW}Bootstrap login:${CL} ${BGN}admin / admin${CL}"
echo -e "${INFO}${YW}Change the bootstrap password immediately via Security.${CL}"
echo -e "${INFO}${YW}Configuration:${CL} ${BGN}/etc/netwatcher/netwatcher.env${CL}"
echo -e "${INFO}${YW}Data:${CL} ${BGN}/var/lib/netwatcher${CL}"
echo -e "${INFO}${YW}Service:${CL} ${BGN}systemctl status netwatcher${CL}"
echo -e "${INFO}${YW}Logs:${CL} ${BGN}journalctl -u netwatcher -f${CL}"
echo -e "${INFO}${YW}NetWatcher starts in UniFi mock mode. Configure UniFi settings, set UNIFI_MOCK_MODE=false, then:${CL}"
echo -e "${GATEWAY}${BGN}systemctl restart netwatcher${CL}"
echo -e "${INFO}${YW}Trusted hosts: private/loopback IP literals work initially. Add DNS names under Security → Trusted Hosts.${CL}"
echo -e "${INFO}${YW}Intended for LAN use. Prefer an HTTPS reverse proxy for higher-security environments.${CL}"

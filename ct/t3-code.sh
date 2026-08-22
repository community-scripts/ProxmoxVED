#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: lukdz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://t3.codes/ | Github: https://github.com/pingdotgg/t3code

APP="T3-Code"
var_tags="${var_tags:-ai;coding}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
export var_t3_providers="${var_t3_providers:-}"
export var_t3_version_control="${var_t3_version_control:-git}"
export var_t3_source_control="${var_t3_source_control:-}"

t3_user="t3"
t3_home="/home/${t3_user}"
t3_data="/opt/t3-code_data"

header_info "$APP"
variables
color
catch_errors

t3_exec() {
  $STD runuser --user "$t3_user" -- env \
    HOME="$t3_home" \
    USER="$t3_user" \
    LOGNAME="$t3_user" \
    SHELL=/bin/bash \
    PATH="$t3_home/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    T3CODE_HOME="$t3_data" \
    XDG_RUNTIME_DIR="/run/user/${t3_uid}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${t3_uid}/bus" \
    NPM_CONFIG_PREFIX="$t3_home/.local" \
    NPM_CONFIG_CACHE="$t3_home/.cache/npm" \
    "$@"
}

migrate_t3_data() {
  t3_data_migrated=0
  if [[ -d "$t3_home/.t3" && ! -e "$t3_data" ]]; then
    msg_info "Migrating T3 Code Data"
    t3_exec /usr/bin/systemctl --user stop t3code.service 2>/dev/null || true
    mv "$t3_home/.t3" "$t3_data"
    chown -R "$t3_user:$t3_user" "$t3_data"
    t3_data_migrated=1
    msg_ok "Migrated T3 Code Data"
  elif [[ -d "$t3_home/.t3" && -d "$t3_data" ]]; then
    if [[ -z "$(find "$t3_data" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
      msg_info "Migrating T3 Code Data"
      t3_exec /usr/bin/systemctl --user stop t3code.service 2>/dev/null || true
      rmdir "$t3_data"
      mv "$t3_home/.t3" "$t3_data"
      chown -R "$t3_user:$t3_user" "$t3_data"
      t3_data_migrated=1
      msg_ok "Migrated T3 Code Data"
    else
      msg_error "Both legacy and current T3 Code data directories exist; migration was not performed."
      return 1
    fi
  fi
}

configure_t3_service_environment() {
  mkdir -p "$t3_home/.config/systemd/user/t3code.service.d"
  cat <<EOF >"$t3_home/.config/systemd/user/t3code.service.d/10-network.conf"
[Service]
Environment=HOME=${t3_home}
Environment=PATH=${t3_home}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=NPM_CONFIG_PREFIX=${t3_home}/.local
Environment=T3CODE_HOME=${t3_data}
Environment=T3CODE_HOST=0.0.0.0
Environment=T3CODE_PORT=3773
EOF
  chown "$t3_user:$t3_user" \
    "$t3_home/.config/systemd/user/t3code.service.d" \
    "$t3_home/.config/systemd/user/t3code.service.d/10-network.conf"
}

fix_resource_monitor_permissions() {
  local monitor
  t3_resource_monitor_repaired=0
  for monitor in "$t3_data"/runtime/versions/*/node_modules/t3/dist/resource-monitor/linux-*/t3-resource-monitor; do
    [[ -f "$monitor" ]] || continue
    if [[ ! -x "$monitor" ]]; then
      chmod 755 "$monitor"
      t3_resource_monitor_repaired=1
    fi
  done
}

finish_t3_service_setup() {
  local expected_version="${1:-}"
  local installed_version

  $STD loginctl enable-linger "$t3_user"
  if [[ ! -f "$t3_home/.config/systemd/user/t3code.service" ||
    ! -f "$t3_data/runtime/service-launcher.mjs" ||
    ! -f "$t3_data/runtime/service-state.json" ]]; then
    return 1
  fi

  installed_version=$(jq -r '.activeVersion // empty' "$t3_data/runtime/service-state.json" 2>/dev/null || true)
  [[ "$installed_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ -z "$expected_version" || "$installed_version" == "$expected_version" ]] || return 1
  [[ -f "$t3_data/runtime/versions/${installed_version}/node_modules/t3/dist/bin.mjs" ]] || return 1
  [[ -f "$t3_data/runtime/versions/${installed_version}/.install-complete" ]] || return 1

  t3_exec /usr/bin/systemctl --user daemon-reload
  t3_exec /usr/bin/systemctl --user enable t3code.service
}

sync_t3_version() {
  local version
  version=$(jq -r '.activeVersion // empty' "$t3_data/runtime/service-state.json" 2>/dev/null || true)
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    msg_error "Unable to determine the installed T3 Code version."
    exit 1
  fi
  cat <<EOF >/root/.t3-code
${version}
EOF
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! id "$t3_user" >/dev/null 2>&1 || [[ ! -f "$t3_home/.config/systemd/user/t3code.service" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  t3_uid="$(id -u "$t3_user")"
  if ! migrate_t3_data; then
    exit 1
  fi
  configure_t3_service_environment
  t3_exec /usr/bin/systemctl --user daemon-reload
  if [[ "$t3_data_migrated" -eq 1 ]]; then
    t3_exec /usr/bin/systemctl --user restart t3code.service
    if ! t3_exec /usr/bin/systemctl --user is-active --quiet t3code.service; then
      msg_error "${APP} service failed to start after data migration"
      exit 1
    fi
  fi
  fix_resource_monitor_permissions

  if check_for_gh_release "t3-code" "pingdotgg/t3code"; then
    NODE_VERSION="24" setup_nodejs

    msg_info "Updating ${APP}"
    if ! t3_exec /usr/bin/npx --yes "t3@${CHECK_UPDATE_RELEASE#v}" service update --base-dir "$t3_data"; then
      msg_warn "T3 could not enable lingering from the unprivileged user; completing service setup as root."
      if ! finish_t3_service_setup "${CHECK_UPDATE_RELEASE#v}"; then
        msg_error "T3 Code service update failed"
        exit 1
      fi
    fi
    fix_resource_monitor_permissions
    t3_exec /usr/bin/systemctl --user restart t3code.service
    sync_t3_version
    msg_ok "Updated ${APP}"

    if ! t3_exec /usr/bin/systemctl --user is-active --quiet t3code.service; then
      msg_error "${APP} service failed to start"
      exit 1
    fi
    msg_ok "Updated successfully!"
  elif [[ "$t3_resource_monitor_repaired" -eq 1 ]]; then
    msg_info "Restarting ${APP} after resource monitor repair"
    t3_exec /usr/bin/systemctl --user restart t3code.service
    msg_ok "Restarted ${APP}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3773${CL}"
echo -e "${INFO}${YW}A one-time pairing URL with a one-hour lifetime is printed during installation.${CL}"
echo -e "${INFO}${YW}To generate another one inside the container as the t3 user:${CL}"
echo -e "${TAB}${BGN}npx --yes t3@latest pair --base-dir /opt/t3-code_data --ttl 1h${CL}"

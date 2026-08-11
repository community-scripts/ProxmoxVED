#!/usr/bin/env bash

# community-scripts ORG | nebula-sync Addon Installer
# Author: MickLesk (CanbiZ)
# License: MIT
# Source: https://github.com/lovelaze/nebula-sync

if command -v curl >/dev/null 2>&1; then
  source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func)
  load_functions
elif command -v wget >/dev/null 2>&1; then
  source <(wget -qO- ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func)
  load_functions
fi
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/lib/tools.func)

color
catch_errors

APP="nebula-sync"
APP_TYPE="tools"
SERVICE="nebula-sync"
CONFIG="/etc/nebula-sync.env"
REPO="lovelaze/nebula-sync"

header_info "$APP"

if [[ ! -f /etc/pihole/pihole.toml ]]; then
  msg_error "Pi-hole v6 not found. Run this addon inside your primary Pi-hole LXC."
  exit 1
fi

if ! grep -q -Ei 'debian|ubuntu' /etc/os-release; then
  msg_error "Unsupported OS. This addon supports only Debian or Ubuntu."
  exit 1
fi

IP=$(hostname -I | awk '{print $1}')

function is_installed() {
  [[ -f /usr/local/bin/nebula-sync ]]
}

function deploy_binary() {
  fetch_and_deploy_gh_release "nebula-sync" "$REPO" "prebuild" "latest" "/usr/local/bin" "nebula-sync_*_linux_$(arch_resolve).tar.gz"
  chmod +x /usr/local/bin/nebula-sync
  rm -f /usr/local/bin/LICENSE /usr/local/bin/README.md
}

function install_sync() {
  echo -n "${TAB}Password of THIS Pi-hole (the primary): "
  read -rs PRIMARY_PASS
  echo ""

  local replicas=""
  while true; do
    echo -n "${TAB}Replica address (e.g. http://192.168.1.5, empty to finish): "
    read -r r_host
    [[ -z "$r_host" ]] && break
    echo -n "${TAB}Password for ${r_host}: "
    read -rs r_pass
    echo ""
    replicas="${replicas:+$replicas,}${r_host}|${r_pass}"
  done

  if [[ -z "$replicas" ]]; then
    msg_error "No replicas given - nothing to sync."
    exit 1
  fi

  echo -n "${TAB}Sync schedule as cron [0 * * * *]: "
  read -r cron
  cron="${cron:-0 * * * *}"

  deploy_binary

  msg_info "Configuring ${APP}"
  cat <<EOF >"$CONFIG"
PRIMARY=http://${IP}|${PRIMARY_PASS}
REPLICAS=${replicas}
FULL_SYNC=true
RUN_GRAVITY=true
CRON=${cron}
TZ=$(cat /etc/timezone 2>/dev/null || echo UTC)
EOF
  chmod 600 "$CONFIG"

  cat <<EOF >/etc/systemd/system/${SERVICE}.service
[Unit]
Description=Pi-hole nebula-sync
Wants=network-online.target
After=network-online.target pihole-FTL.service

[Service]
Type=simple
User=root
EnvironmentFile=${CONFIG}
ExecStart=/usr/local/bin/nebula-sync run
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "$SERVICE"
  msg_ok "Configured ${APP}"

  echo ""
  msg_ok "${APP} syncs this Pi-hole to its replicas on schedule: ${BL}${cron}${CL}"
  msg_ok "Follow it with: ${BL}journalctl -u ${SERVICE} -f${CL}"
}

function uninstall_sync() {
  msg_info "Removing ${APP}"
  systemctl disable -q --now "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service" /usr/local/bin/nebula-sync "$CONFIG" ~/.nebula-sync
  systemctl daemon-reexec
  msg_ok "${APP} uninstalled - Pi-hole itself is untouched"
}

function update_sync() {
  if check_for_gh_release "nebula-sync" "$REPO"; then
    msg_info "Stopping ${APP}"
    systemctl stop "$SERVICE"
    msg_ok "Stopped ${APP}"

    CLEAN_INSTALL=1 deploy_binary

    systemctl start "$SERVICE"
    msg_ok "${APP} updated"
  else
    msg_ok "${APP} is already up-to-date"
  fi
}

if is_installed; then
  read -r -p "Update (1), Uninstall (2), Cancel (3)? [1/2/3]: " action
  action="${action//[[:space:]]/}"
  case "$action" in
  1) update_sync ;;
  2) uninstall_sync ;;
  3) msg_info "Cancelled" ;;
  *) msg_error "Invalid input" ;;
  esac
else
  read -r -p "Install ${APP} on this Pi-hole? (y/n): " answer
  answer="${answer//[[:space:]]/}"
  [[ "${answer,,}" =~ ^(y|yes)$ ]] && install_sync || msg_info "Installation skipped"
fi

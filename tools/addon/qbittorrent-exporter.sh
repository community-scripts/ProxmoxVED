#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/martabal/qbittorrent-exporter

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

VERBOSE=${var_verbose:-no}
APP="qbittorrent-exporter"
APP_TYPE="tools"
INSTALL_PATH="/opt/qbittorrent-exporter/src/qbittorrent-exporter"
CONFIG_PATH="/opt/qbittorrent-exporter.env"
header_info
ensure_usr_local_bin_persist
get_current_ip &>/dev/null

# OS Detection
if [[ -f "/etc/alpine-release" ]]; then
  OS="Alpine"
  SERVICE_PATH="/etc/init.d/qbittorrent-exporter"
elif grep -qE 'ID=debian|ID=ubuntu' /etc/os-release; then
  OS="Debian"
  SERVICE_PATH="/etc/systemd/system/qbittorrent-exporter.service"
else
  echo -e "${CROSS} Unsupported OS detected. Exiting."
  exit 1
fi

# Existing installation
if [[ -f "$INSTALL_PATH" ]]; then
  echo -e "${YW}⚠️ qbittorrent-exporter is already installed.${CL}"
  echo -n "Uninstall ${APP}? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Uninstalling qbittorrent-exporter"
    if [[ "$OS" == "Debian" ]]; then
      systemctl disable --now qbittorrent-exporter.service &>/dev/null
      rm -f "$SERVICE_PATH"
    else
      rc-service qbittorrent-exporter stop &>/dev/null
      rc-update del qbittorrent-exporter &>/dev/null
      rm -f "$SERVICE_PATH"
    fi
    rm -f "$INSTALL_PATH" "$CONFIG_PATH" ~/.qbittorrent-exporter
    msg_ok "${APP} has been uninstalled."
    exit 0
  fi

  echo -n "Update qbittorrent-exporter? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    if check_for_gh_release "qbittorrent-exporter" "martabal/qbittorrent-exporter"; then
      fetch_and_deploy_gh_release "qbittorrent-exporter" "martabal/qbittorrent-exporter"
      setup_go
      msg_info "Updating qbittorrent-exporter"
      cd /opt/qbittorrent-exporter/src
      /usr/local/bin/go build -o ./qbittorrent-exporter
      msg_ok "Updated Successfully!"
    fi
    exit 0
  else
    echo -e "${YW}⚠️ Update skipped. Exiting.${CL}"
    exit 0
  fi
fi

echo -e "${YW}⚠️ qbittorrent-exporter is not installed.${CL}"
echo -n "Enter URL of qbittorrent, example: (http://127.0.0.1:8080): "
read -er QBITTORRENT_BASE_URL

echo -n "Enter qbittorrent username: "
read -er QBITTORRENT_USERNAME

echo -n "Enter qbittorrent password: "
read -rs QBITTORRENT_PASSWORD
echo

echo -n "Install qbittorrent-exporter? (y/n): "
read -r install_prompt
if ! [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  echo -e "${YW}⚠️ Installation skipped. Exiting.${CL}"
  exit 0
fi

fetch_and_deploy_gh_release "qbittorrent-exporter" "martabal/qbittorrent-exporter" "tarball" "latest"
setup_go
msg_info "Installing qbittorrent-exporter on ${OS}"
cd /opt/qbittorrent-exporter/src
/usr/local/bin/go build -o ./qbittorrent-exporter
msg_ok "Installed qbittorrent-exporter"

msg_info "Creating configuration"
cat <<EOF >"$CONFIG_PATH"
# https://github.com/martabal/qbittorrent-exporter?tab=readme-ov-file#parameters
QBITTORRENT_BASE_URL="${QBITTORRENT_BASE_URL}"
QBITTORRENT_USERNAME="${QBITTORRENT_USERNAME}"
QBITTORRENT_PASSWORD="${QBITTORRENT_PASSWORD}"
EOF
msg_ok "Created configuration"

msg_info "Creating service"
if [[ "$OS" == "Debian" ]]; then
  cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=qbittorrent-exporter
After=network.target

[Service]
User=root
WorkingDirectory=/opt/qbittorrent-exporter/src
EnvironmentFile=$CONFIG_PATH
ExecStart=/opt/qbittorrent-exporter/src/qbittorrent-exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now qbittorrent-exporter
else
  cat <<EOF >"$SERVICE_PATH"
#!/sbin/openrc-run

command="$INSTALL_PATH"
command_args=""
command_background=true
directory="/opt/qbittorrent-exporter/src"
pidfile="/opt/qbittorrent-exporter/src/pidfile"

depend() {
    need net
}

start_pre() {
    if [ -f "$CONFIG_PATH" ]; then
        export \$(grep -v '^#' $CONFIG_PATH | xargs)
    fi
}
EOF
  chmod +x "$SERVICE_PATH"
  rc-update add qbittorrent-exporter default &>/dev/null
  rc-service qbittorrent-exporter start &>/dev/null
fi
msg_ok "Service created successfully"

echo -e "${CM} ${GN}${APP} is reachable at: ${BL}http://$CURRENT_IP:8090/metrics${CL}"

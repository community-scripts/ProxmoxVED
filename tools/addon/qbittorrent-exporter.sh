#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)

var_verbose=${var_verbose:-0}
APP="qbittorrent-exporter"
APP_TYPE="tools"
INSTALL_PATH="/opt/qbittorrent-exporter/src/qbittorrent-exporter"
CONFIG_PATH="/opt/qbittorrent-exporter.env"
SRC_DIR="/"
TMP_BIN="/tmp/qbittorrent-exporter.$$"
header_info
ensure_usr_local_bin_persist

# Get primary IP
IFACE=$(ip -4 route | awk '/default/ {print $5; exit}')
IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)
[[ -z "$IP" ]] && IP=$(hostname -I | awk '{print $1}')
[[ -z "$IP" ]] && IP="127.0.0.1"

# OS Detection
if [[ -f "/etc/alpine-release" ]]; then
  OS="Alpine"
  SERVICE_PATH="/etc/init.d/qbittorrent-exporter"
elif [[ -f "/etc/debian_version" ]]; then
  OS="Debian"
  SERVICE_PATH="/etc/systemd/system/qbittorrent-exporter.service"
else
  echo -e "${CROSS} Unsupported OS detected. Exiting."
  exit 1
fi

# Existing installation
if [[ -f "$INSTALL_PATH" ]]; then
  echo -e "${YW}⚠️ ${APP} is already installed.${CL}"
  echo -n "Uninstall ${APP}? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Uninstalling ${APP}"
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

  echo -n "Update ${APP}? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then

    fetch_and_deploy_gh_release "qbittorrent-exporter" "martabal/qbittorrent-exporter" 
    setup_go
    msg_info "Updating ${APP}"
    cd /opt/qbittorrent-exporter
    /usr/local/bin/go get -d=true -v &>/dev/null
    cd src
    /usr/local/bin/go build -o ./qbittorrent-exporter
    msg_ok "Updated ${APP}"
    exit 0
  else
    echo -e "${YW}⚠️ Update skipped. Exiting.${CL}"
    exit 0
  fi
fi

echo -e "${YW}⚠️ ${APP} is not installed.${CL}"
echo -n "Enter URL of qbittorrent example: (http://192.168.1.10:8080): "
read -er QBITTORRENT_BASE_URL

echo -n "Enter qbittorrent username: "
read -er QBITTORRENT_USERNAME

echo -n "Enter qbittorrent password: "
read -rs QBITTORRENT_PASSWORD
echo ""

echo -n "Install ${APP}? (y/n): "
read -r install_prompt
if ! [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  echo -e "${YW}⚠️ Installation skipped. Exiting.${CL}"
  exit 0
fi

fetch_and_deploy_gh_release "qbittorrent-exporter" "martabal/qbittorrent-exporter" "1.12.0"
setup_go
msg_info "Installing ${APP} on ${OS}"
cd /opt/qbittorrent-exporter
/usr/local/bin/go get -d -v &>/dev/null
cd src
/usr/local/bin/go build -o ./qbittorrent-exporter
msg_ok "Installed ${APP}"

msg_info "Creating configuration"
cat <<EOF >"$CONFIG_PATH"
QBITTORRENT_BASE_URL=${QBITTORRENT_BASE_URL}
QBITTORRENT_USERNAME=${QBITTORRENT_USERNAME}
QBITTORRENT_PASSWORD=${QBITTORRENT_PASSWORD}
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
  systemctl enable --now qbittorrent-exporter &>/dev/null
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
echo -e "${CM} ${GN}${APP} is reachable at: ${BL}http://$IP:8090/metrics${CL}"

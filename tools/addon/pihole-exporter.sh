#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/eko/pihole-exporter/

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

VERBOSE=${var_verbose:-no}
APP="pihole-exporter"
APP_TYPE="tools"
INSTALL_PATH="/opt/pihole-exporter/pihole-exporter"
CONFIG_PATH="/opt/pihole.env"
header_info
ensure_usr_local_bin_persist
get_current_ip &>/dev/null

# OS Detection
if [[ -f "/etc/alpine-release" ]]; then
  OS="Alpine"
  SERVICE_PATH="/etc/init.d/pihole-exporter"
elif grep -qE 'ID=debian|ID=ubuntu' /etc/os-release; then
  OS="Debian"
  SERVICE_PATH="/etc/systemd/system/pihole-exporter.service"
else
  echo -e "${CROSS} Unsupported OS detected. Exiting."
  exit 1
fi

# Existing installation
if [[ -f "$INSTALL_PATH" ]]; then
  echo -e "${YW}⚠️ pihole-exporter is already installed.${CL}"
  echo -n "Uninstall ${APP}? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Uninstalling pihole-exporter"
    if [[ "$OS" == "Debian" ]]; then
      systemctl disable --now pihole-exporter.service &>/dev/null
      rm -f "$SERVICE_PATH"
    else
      rc-service pihole-exporter stop &>/dev/null
      rc-update del pihole-exporter &>/dev/null
      rm -f "$SERVICE_PATH"
    fi
    rm -f "$INSTALL_PATH" "$CONFIG_PATH" ~/.pihole-exporter
    msg_ok "${APP} has been uninstalled."
    exit 0
  fi

  echo -n "Update pihole-exporter? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    if check_for_gh_release "pihole-exporter" "eko/pihole-exporter"; then
      fetch_and_deploy_gh_release "pihole-exporter" "eko/pihole-exporter"
      setup_go
      msg_info "Updating pihole-exporter"
      cd /opt/pihole-exporter/
      /usr/local/bin/go build -o ./pihole-exporter
      msg_ok "Updated Successfully!"
    fi
    exit 0
  else
    echo -e "${YW}⚠️ Update skipped. Exiting.${CL}"
    exit 0
  fi
fi

echo -e "${YW}⚠️ pihole-exporter is not installed.${CL}"
echo -n "Enter the hostname of pihole, example: (127.0.0.1): "
read -er pihole_HOSTNAME

echo -n "Enter pihole password: "
read -rs pihole_PASSWORD
echo

echo -n "Do you want to skip TLS-Verification (if using a self-signed Certificate on Pi-Hole) [y/N]: "
read -er pihole_SKIP_TLS
if ! [[ "${pihole_SKIP_TLS,,}" =~ ^(y|yes)$ ]]; then
  pihole_SKIP_TLS="true"
fi

echo -n "Install qbittorrent-exporter? (y/n): "
read -r install_prompt
if ! [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  echo -e "${YW}⚠️ Installation skipped. Exiting.${CL}"
  exit 0
fi

fetch_and_deploy_gh_release "pihole-exporter" "eko/pihole-exporter" "tarball" "latest"
setup_go
msg_info "Installing pihole-exporter on ${OS}"
cd /opt/pihole-exporter/
/usr/local/bin/go build -o ./pihole-exporter
msg_ok "Installed pihole-exporter"

msg_info "Creating configuration"
cat <<EOF >"$CONFIG_PATH"
# https://github.com/eko/pihole-exporter/?tab=readme-ov-file#available-cli-options
PIHOLE_PASSWORD="${pihole_PASSWORD}"
PIHOLE_hostname="${pihole_HOSTNAME}"
SKIP_TLS_VERIFICATION="${pihole_SKIP_TLS}"
EOF
msg_ok "Created configuration"

msg_info "Creating service"
if [[ "$OS" == "Debian" ]]; then
  cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=pihole-exporter
After=network.target

[Service]
User=root
WorkingDirectory=/opt/pihole-exporter
EnvironmentFile=$CONFIG_PATH
ExecStart=/opt/pihole-exporter/pihole-exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now pihole-exporter
else
  cat <<EOF >"$SERVICE_PATH"
#!/sbin/openrc-run

command="$INSTALL_PATH"
command_args=""
command_background=true
directory="/opt/pihole-exporter"
pidfile="/opt/pihole-exporter/pidfile"

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
  rc-update add pihole-exporter default &>/dev/null
  rc-service pihole-exporter start &>/dev/null
fi
msg_ok "Service created successfully"

echo -e "${CM} ${GN}${APP} is reachable at: ${BL}http://$CURRENT_IP:9617/metrics${CL}"

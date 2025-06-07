#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: KellanStevens
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Stremio/stremio-service

color() {
  YW=$(echo "\033[33m")
  GN=$(echo "\033[32m")
  RD=$(echo "\033[01;31m")
  CL=$(echo "\033[m")
  BGN=$(echo "\033[1;92m")
  CREATING="${GN} [\xE2\x9C\x94]${CL}"
  INFO="${YW} [i]${CL}"
  TAB="    "
}

msg_info() {
  echo -e "${INFO} $1"
}

msg_ok() {
  echo -e "${CREATING} $1"
}

msg_info "Updating OS"
apt-get update
apt-get upgrade -y
msg_ok "OS Updated"

msg_info "Installing dependencies"
apt-get install -y curl tar
msg_ok "Dependencies Installed"

msg_info "Installing Node.js (LTS)"
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
msg_ok "Node.js Installed"

msg_info "Downloading latest Stremio release"
LATEST_URL=$(curl -s https://api.github.com/repos/Stremio/stremio-service/releases/latest | grep "browser_download_url.*linux_amd64.tar.gz" | cut -d '"' -f 4)
mkdir -p /opt/stremio
curl -L "$LATEST_URL" | tar xz -C /opt/stremio
chmod +x /opt/stremio/stremio
msg_ok "Stremio Downloaded"

msg_info "Creating systemd service"
cat <<EOL >/etc/systemd/system/stremio.service
[Unit]
Description=Stremio (Official Backend)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/stremio
ExecStart=/opt/stremio/stremio
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable --now stremio
msg_ok "Service Created and Started"

msg_info "Cleaning up"
apt-get -y autoremove
apt-get -y autoclean
msg_ok "Cleaned"

IP=$(hostname -I | awk '{print $1}')
echo -e "\n${CREATING}${GN}Stremio setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${BGN}http://${IP}:11470${CL}"

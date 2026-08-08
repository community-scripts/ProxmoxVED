#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: VRB95
# Source: https://github.com/VRB95/WatchYourLAN-MobileUI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

REPO_URL="https://github.com/VRB95/WatchYourLAN-MobileUI.git"
APP_DIR="/opt/mynetwork"
DATA_DIR="/data/myNetwork"
GO_VERSION="1.25.1"

msg_info "Installing Dependencies"
$STD apt install -y git curl ca-certificates build-essential arp-scan tzdata rsync
msg_ok "Installed Dependencies"

msg_info "Installing Node.js"
curl -fsSL "https://deb.nodesource.com/setup_22.x" | bash -
$STD apt install -y nodejs
msg_ok "Installed Node.js"

msg_info "Installing Go ${GO_VERSION}"
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o "/tmp/go${GO_VERSION}.linux-amd64.tar.gz"
rm -rf /usr/local/go
tar -C /usr/local -xzf "/tmp/go${GO_VERSION}.linux-amd64.tar.gz"
rm -f "/tmp/go${GO_VERSION}.linux-amd64.tar.gz"
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
msg_ok "Installed Go ${GO_VERSION}"

msg_info "Cloning myNetwork"
git clone "$REPO_URL" "$APP_DIR"
msg_ok "Cloned myNetwork"

msg_info "Building Frontend"
cd "$APP_DIR/frontend"
if [[ -f package-lock.json ]]; then
  $STD npm ci
else
  $STD npm install
fi
$STD npm run build
mkdir -p "$APP_DIR/backend/internal/web/public/assets"
rsync -a --delete "$APP_DIR/frontend/dist/assets/" "$APP_DIR/backend/internal/web/public/assets/"
msg_ok "Built Frontend"

msg_info "Building Backend"
cd "$APP_DIR/backend"
$STD go mod download
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /usr/local/bin/mynetwork ./cmd/myNetwork
chmod 0755 /usr/local/bin/mynetwork
msg_ok "Built Backend"

msg_info "Creating Data Directory"
mkdir -p "$DATA_DIR"
msg_ok "Created Data Directory"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/mynetwork.service
[Unit]
Description=myNetwork LAN Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mynetwork -d ${DATA_DIR}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now mynetwork
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

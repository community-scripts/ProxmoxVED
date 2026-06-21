#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://manual.nssurge.com/others/snell.html

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

SNELL_VERSION="v5.0.1"

snell_release_arch() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$arch" in
  amd64 | x86_64)
    echo "amd64"
    ;;
  arm64 | aarch64)
    echo "aarch64"
    ;;
  *)
    msg_error "Unsupported architecture: ${arch}"
    exit 65
    ;;
  esac
}

CLEAN_INSTALL=1 fetch_and_deploy_from_url "https://dl.nssurge.com/snell/snell-server-${SNELL_VERSION}-linux-$(snell_release_arch).zip" "/opt/snell"

msg_info "Installing Snell"
chmod +x /opt/snell/snell-server
ln -sf /opt/snell/snell-server /usr/local/bin/snell-server
echo "${SNELL_VERSION}" >/opt/snell/version
msg_ok "Installed Snell"

msg_info "Configuring Snell"
SNELL_PORT="${SNELL_PORT:-$(shuf -i 30000-65000 -n 1)}"
SNELL_PSK="${SNELL_PSK:-$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c32)}"
mkdir -p /etc/snell
cat <<EOF >/etc/snell/snell-server.conf
[snell-server]
listen = 0.0.0.0:${SNELL_PORT}
psk = ${SNELL_PSK}
ipv6 = true
EOF
chmod 600 /etc/snell/snell-server.conf
msg_ok "Configured Snell"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/snell.service
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/snell
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
Restart=on-failure
RestartSec=5
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now snell
msg_ok "Created Service"

msg_info "Checking Service"
sleep 2
systemctl is-active --quiet snell
msg_ok "Service Running"

motd_ssh
customize
cleanup_lxc

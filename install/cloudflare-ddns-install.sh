#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: edoardop13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/favonia/cloudflare-ddns

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get update
$STD apt-get install -y curl systemd

msg_info "Installing Go"
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | grep -m1 '^go')
GO_TARBALL="${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
INSTALL_DIR="/usr/bin"
echo "📦 Download Go ${GO_VERSION} from ${GO_URL}..."

rm -rf "${INSTALL_DIR}/go"

curl -LO "$GO_URL"
tar -C "$INSTALL_DIR" -xzf "$GO_TARBALL"
rm "$GO_TARBALL"

echo 'export PATH=$PATH:/usr/bin/go/bin' >> ~/.bashrc
source ~/.bashrc
go version

msg_ok "Dependencies installed"

msg_info "Configure Application"

var_cf_api_token="default"
var_cf_api_token=$(whiptail --title "CLOUDFLARE TOKEN" --backtitle "Type the Cloudflare Api Token:" --inputbox "token" 10 60 3>&1 1>&2 2>&3)
msg_ok "Cloudflare Api Token: '${var_cf_api_token}'"

var_cf_domains="default"
var_cf_domains=$(whiptail --title "CLOUDFLARE DOMAINS" --backtitle "Type the domains separated with a comma (example.org,www.example.org)" --inputbox "*.example.com" 10 60 3>&1 1>&2 2>&3)
msg_ok "Cloudflare Domains: '${var_cf_domains}'"

var_cf_proxied="false"
if whiptail --yesno "Proxied?" 8 45; then
    var_cf_proxied="true"
fi
var_cf_ip6_provider="none"
if whiptail --yesno "IPv6 Provider?" 8 45; then
    var_cf_ip6_provider="cloudflare"
else 
    var_cf_ip6_provider="none"
fi

msg_ok "Application Configured"

msg_info "Setting up systemd service"
mkdir -p /root/go
chown -R root:root /root/go
cat <<EOF >/etc/systemd/system/cloudflare-ddns.service
[Unit]
Description=Cloudflare DDNS Service (Go run)
After=network.target

[Service]
Environment="CLOUDFLARE_API_TOKEN=${var_cf_api_token}"
Environment="DOMAINS=${var_cf_domains}"
Environment="PROXIED=${var_cf_proxied}"
Environment="IP6_PROVIDER=${var_cf_ip6_provider}"
Environment="GOPATH=/root/go"
Environment="GOCACHE=/tmp/go-build"
ExecStart=/usr/bin/go/bin/go run github.com/favonia/cloudflare-ddns/cmd/ddns@latest
Restart=always
RestartSec=300

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Systemd service configured"

msg_info "Enabling and starting service"
systemctl daemon-reload
systemctl enable --now cloudflare-ddns.service
msg_ok "Cloudflare DDNS service started"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_ok "Completed Successfully! Cloudflare DDNS is running in the background.\n"

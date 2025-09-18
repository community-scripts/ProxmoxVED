#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: SimplyMinimal
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/tailscale/golink

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  ca-certificates \
  sqlite3
msg_ok "Installed Dependencies"

setup_go

msg_info "Cloning Golink Repository"
$STD git clone https://github.com/tailscale/golink.git /opt/golink
msg_ok "Cloned Golink Repository"

msg_info "Building Golink"
cd /opt/golink || exit
$STD go mod tidy

# Clean Go cache before building to save space
$STD go clean -cache -modcache

# Build with optimizations to reduce space usage
$STD go build -ldflags="-s -w" -o golink ./cmd/golink
chmod +x golink

# Clean up build artifacts
$STD go clean -cache

RELEASE=$(git describe --tags --always 2>/dev/null || echo "main-$(git rev-parse --short HEAD)")
echo "${RELEASE}" >"/opt/${APPLICATION}_version.txt"
msg_ok "Built Golink"

msg_info "Configuring Golink"
mkdir -p /opt/golink/data

# Prompt for Tailscale authentication key
echo ""
echo "Golink can run in two modes:"
echo "1. Development/Testing mode (accessible on port 8080)"
echo "2. Production mode with Tailscale (accessible via Tailscale network at http://go/)"
echo ""
read -p "Do you want to configure Tailscale integration now? (y/N): " -r
echo ""

TAILSCALE_MODE=false
if [[ $REPLY =~ ^[Yy]$ ]]; then
  read -p "Enter your Tailscale auth key (tskey-auth-* or tskey-*): " -r TS_AUTHKEY
  echo ""

  # Validate the auth key format
  if [[ -n "$TS_AUTHKEY" && ("$TS_AUTHKEY" =~ ^tskey-auth- || "$TS_AUTHKEY" =~ ^tskey-) ]]; then
    TAILSCALE_MODE=true
    cat <<EOF >/opt/golink/.env
# Golink configuration with Tailscale
TS_AUTHKEY=$TS_AUTHKEY
EOF
    echo "✓ Tailscale integration configured"
  else
    echo "⚠ Invalid auth key format. Setting up development mode instead."
    echo "  Auth keys should start with 'tskey-auth-' or 'tskey-'"
    cat <<EOF >/opt/golink/.env
# Golink configuration - Development mode
# To enable Tailscale later, add your auth key here:
# TS_AUTHKEY=tskey-auth-your-key-here
EOF
  fi
else
  cat <<EOF >/opt/golink/.env
# Golink configuration - Development mode
# To enable Tailscale later, add your auth key here:
# TS_AUTHKEY=tskey-auth-your-key-here
EOF
fi
if [[ "$TAILSCALE_MODE" == "true" ]]; then
  {
    echo "Golink Configuration - Tailscale Mode"
    echo "===================================="
    echo "Mode: Production with Tailscale integration"
    echo "Access: http://go/ (via Tailscale network)"
    echo ""
    echo "Configuration:"
    echo "- Auth key configured in /opt/golink/.env"
    echo "- Service will join your Tailscale network on first start"
    echo "- Database location: /opt/golink/data/golink.db"
    echo ""
    echo "Note: Ensure MagicDNS is enabled in your Tailscale admin panel"
    echo "      for easy access at http://go/"
  } >~/golink.creds
else
  {
    echo "Golink Configuration - Development Mode"
    echo "======================================="
    echo "Mode: Development/Testing (local access only)"
    echo "Access: http://$(hostname -I | awk '{print $1}'):8080"
    echo ""
    echo "To enable Tailscale later:"
    echo "1. Add TS_AUTHKEY to /opt/golink/.env"
    echo "2. Edit /etc/systemd/system/golink.service"
    echo "3. Remove '-dev-listen :8080' from ExecStart"
    echo "4. Restart service: systemctl restart golink"
    echo ""
    echo "Database location: /opt/golink/data/golink.db"
  } >~/golink.creds
fi
msg_ok "Configured Golink"

msg_info "Creating Service"
if [[ "$TAILSCALE_MODE" == "true" ]]; then
  # Production mode with Tailscale - no dev-listen flag
  cat <<EOF >/etc/systemd/system/golink.service
[Unit]
Description=Golink Private Shortlink Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/golink
ExecStart=/opt/golink/golink -sqlitedb /opt/golink/data/golink.db
EnvironmentFile=-/opt/golink/.env
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
else
  # Development mode - include dev-listen flag
  cat <<EOF >/etc/systemd/system/golink.service
[Unit]
Description=Golink Private Shortlink Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/golink
ExecStart=/opt/golink/golink -sqlitedb /opt/golink/data/golink.db -dev-listen :8080
EnvironmentFile=-/opt/golink/.env
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
fi
systemctl enable -q --now golink
if [[ "$TAILSCALE_MODE" == "true" ]]; then
  msg_ok "Created Service (Tailscale Mode)"
else
  msg_ok "Created Service (Development Mode)"
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

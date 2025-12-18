#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: TechHutTV
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://netbird.io/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

echo ""
echo ' _   _  _____ _____ ____  _   _ _____ ____ '
echo '| \ | ||_   _| ____| _  \| | | | ____| _  \'
echo '| \| |  _ | | |  _| |_| |_  _ __ __ _| | | \'
echo '| . ` |/ _ \ | | |_ | __ <| |  \'__/ _` | | | \'
echo '| |\ | __/ |_| |__| |_) | | | | (__ | |_| |'
echo '|_| \_|\___|\___|\__|____/|_|_| \___|\_____/'
echo ""

msg_info "Installing Dependencies"
$STD apt install -y \
curl \
ca-certificates \
gnupg
msg_ok "Installed Dependencies"

msg_info "Setting up NetBird Repository"
curl -sSL https://pkgs.netbird.io/debian/public.key \
| gpg --dearmor -o /usr/share/keyrings/netbird-archive-keyring.gpg
chmod 0644 /usr/share/keyrings/netbird-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' \
| tee /etc/apt/sources.list.d/netbird.list > /dev/null
$STD apt update
msg_ok "Set up NetBird Repository"

msg_info "Installing NetBird"
$STD apt install -y netbird
msg_ok "Installed NetBird"

msg_info "Enabling NetBird Service"
$STD netbird service install 2>/dev/null || true
$STD netbird service start 2>/dev/null || true
$STD systemctl enable netbird
msg_ok "Enabled NetBird Service"

# NetBird Deployment Type Selection

echo ""
echo -e "${BL}NetBird Deployment Type${CL}"
echo "─────────────────────────────────────────"
echo "Are you using NetBird Managed or Self-Hosted?"
echo ""
echo " 1) NetBird Managed (default) - Use NetBird's managed service"
echo " 2) Self-Hosted - Use your own NetBird management server"
echo ""

read -rp "Select deployment type [1]: " DEPLOYMENT_TYPE
DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-1}"

NETBIRD_MGMT_URL=""
case "$DEPLOYMENT_TYPE" in
1)
msg_info "Using NetBird Managed service"
;;
2)
echo ""
echo -e "${BL}Self-Hosted Configuration${CL}"
echo "─────────────────────────────────────────"
echo "Enter your NetBird management server URL."
echo "Example: https://management.example.com"
echo ""
read -rp "Management URL: " NETBIRD_MGMT_URL

if [[ -z "$NETBIRD_MGMT_URL" ]]; then
msg_warn "No management URL provided. Run 'netbird up --management-url <url>' within the container to connect."
else
# Ensure URL doesn't end with trailing slash
NETBIRD_MGMT_URL="${NETBIRD_MGMT_URL%/}"
msg_info "Management URL configured: ${GN}${NETBIRD_MGMT_URL}${CL}"
fi
;;
*)
msg_warn "Invalid selection. Using NetBird Managed service."
;;
esac

# NetBird Connection Setup

echo ""
echo -e "${BL}NetBird Connection Setup${CL}"
echo "─────────────────────────────────────────"
echo "Choose how to connect to your NetBird network:"
echo ""
echo " 1) Setup Key (default) - Use a pre-generated setup key"
echo " 2) SSO Login - Authenticate via browser with your identity provider"
echo " 3) Skip - Configure later with 'netbird up'"
echo ""

read -rp "Select authentication method [1]: " AUTH_METHOD
AUTH_METHOD="${AUTH_METHOD:-1}"

case "$AUTH_METHOD" in
1)
# Setup Key authentication
echo ""
echo "Enter your NetBird setup key from the NetBird dashboard."
echo ""
read -rp "Setup key: " NETBIRD_SETUP_KEY
echo ""

if [[ -z "$NETBIRD_SETUP_KEY" ]]; then
if [[ -n "$NETBIRD_MGMT_URL" ]]; then
msg_warn "No setup key provided. Run 'netbird up -k <key> --management-url $NETBIRD_MGMT_URL' within the container to connect."
else
msg_warn "No setup key provided. Run 'netbird up -k <key>' within the container to connect."
fi
else
echo -e "Setup key: ${GN}${NETBIRD_SETUP_KEY}${CL}"
read -rp "Press Enter to continue or Ctrl+C to cancel..."

msg_info "Connecting to NetBird with setup key"
if [[ -n "$NETBIRD_MGMT_URL" ]]; then
if netbird up -k "$NETBIRD_SETUP_KEY" --management-url "$NETBIRD_MGMT_URL"; then
msg_ok "Connected to NetBird"
else
msg_warn "Connection failed. Run 'netbird up -k <key> --management-url $NETBIRD_MGMT_URL' within the container to retry."
fi
else
if netbird up -k "$NETBIRD_SETUP_KEY"; then
msg_ok "Connected to NetBird"
else
msg_warn "Connection failed. Run 'netbird up -k <key>' within the container to retry."
fi
fi
fi
;;
2)
# SSO authentication
echo ""
echo -e "${BL}SSO Authentication${CL}"
echo "─────────────────────────────────────────"
echo "A login URL will appear below."
echo "Copy the URL and open it in your browser to authenticate."
echo ""

msg_info "Starting SSO login"
if [[ -n "$NETBIRD_MGMT_URL" ]]; then
netbird login --management-url "$NETBIRD_MGMT_URL" 2>&1 || true
else
netbird login 2>&1 || true
fi
echo ""

msg_info "Connecting to NetBird"
if [[ -n "$NETBIRD_MGMT_URL" ]]; then
if netbird up --management-url "$NETBIRD_MGMT_URL"; then
msg_ok "Connected to NetBird"
else
msg_warn "Connection failed. Run 'netbird up --management-url $NETBIRD_MGMT_URL' within the container to retry."
fi
else
if netbird up; then
msg_ok "Connected to NetBird"
else
msg_warn "Connection failed. Run 'netbird up' within the container to retry."
fi
fi
;;
3)
msg_info "Skipping NetBird connection"
if [[ -n "$NETBIRD_MGMT_URL" ]]; then
msg_ok "Run 'netbird up --management-url $NETBIRD_MGMT_URL' within the container to connect."
else
msg_ok "Run 'netbird up' within the container to connect."
fi
;;
*)
msg_warn "Invalid selection. Run 'netbird up' within the container to connect."
;;
esac

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
msg_ok "Cleaned"

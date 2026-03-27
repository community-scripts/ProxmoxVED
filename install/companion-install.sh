#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: glabutis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bitfocus/companion

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y libusb-1.0-0
msg_ok "Installed Dependencies"

msg_info "Fetching Latest Bitfocus Companion Release"
RELEASE_JSON=$(curl -fsSL "https://api.bitfocus.io/v1/product/companion/packages?limit=20")
PACKAGE_JSON=$(echo "$RELEASE_JSON" | jq -c '(if type == "array" then . else .packages end) | [.[] | select(.target=="linux-tgz" and (.uri | contains("linux-x64")))] | first')
RELEASE=$(echo "$PACKAGE_JSON" | jq -r '.version // empty')
ASSET_URL=$(echo "$PACKAGE_JSON" | jq -r '.uri // empty')
if [[ -z "$RELEASE" || -z "$ASSET_URL" ]]; then
  msg_error "Could not resolve a matching Linux x64 Companion package from the Bitfocus API."
  exit 1
fi
msg_ok "Found Companion v${RELEASE}"

msg_info "Downloading Bitfocus Companion v${RELEASE}"
fetch_and_deploy_from_url "$ASSET_URL" "/opt/companion"
msg_ok "Downloaded and Extracted Bitfocus Companion v${RELEASE}"

msg_info "Installing udev Rules"
if [[ -f /opt/companion/50-companion-headless.rules ]]; then
  cp /opt/companion/50-companion-headless.rules /etc/udev/rules.d/
  udevadm control --reload-rules
  udevadm trigger
fi
msg_ok "Installed udev Rules"

msg_info "Creating companion User"
useradd --system --no-create-home --shell /usr/sbin/nologin companion 2>/dev/null || true
mkdir -p /opt/companion-config
chown -R companion:companion /opt/companion-config
chown -R companion:companion /opt/companion
msg_ok "Created companion User"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/companion.service
[Unit]
Description=Bitfocus Companion
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=companion
ExecStart=/opt/companion/companion_headless.sh --config-dir /opt/companion-config
WorkingDirectory=/opt/companion
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=companion
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now companion
msg_ok "Created Service"

echo "${RELEASE}" >~/.companion

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Borja Garduño (Borja-Garduno)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://airdcpp.net/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-16)

ASSET_URL=$(curl -fsSL https://airdcpp.net/docs/installation/linux-binaries.html |
  grep -oE 'https://web-builds\.airdcpp\.net/stable/airdcpp_[^"]+_64-bit_portable\.tar\.gz' |
  head -1)
if [[ -z "${ASSET_URL}" ]]; then
  msg_error "Could not resolve the official 64-bit portable download URL."
  exit 1
fi

fetch_and_deploy_from_url "${ASSET_URL}" /opt/airdcpp
chmod +x /opt/airdcpp/airdcppd

VERSION=$(get_latest_github_release "airdcpp-web/airdcpp-webclient")
echo "${VERSION}" >~/.airdcpp

msg_info "Configuring AirDCPP"
mkdir -p /opt/airdcpp_data
if ! mountpoint -q /downloads; then
  mkdir -p /downloads
fi
if ! mountpoint -q /share; then
  mkdir -p /share
fi

if ! printf '\n\n%s\n%s\n%s\n' "admin" "${ADMIN_PASS}" "${ADMIN_PASS}" |
  /opt/airdcpp/airdcppd -c=/opt/airdcpp_data --configure; then
  msg_error "AirDCPP --configure failed."
  exit 1
fi

if [[ ! -f /opt/airdcpp_data/DCPlusPlus.xml ]]; then
  cat <<EOF >/opt/airdcpp_data/DCPlusPlus.xml
<DCPlusPlus>
        <Settings>
                <DownloadDirectory type="string">/downloads/</DownloadDirectory>
                <AutoDetectIncomingConnection type="int">0</AutoDetectIncomingConnection>
                <InPort type="int">21248</InPort>
                <UDPPort type="int">21248</UDPPort>
                <TLSPort type="int">21249</TLSPort>
        </Settings>
        <Share Token="0" Name="Default">
                <Directory Virtual="Share">/share/</Directory>
                <NoShare/>
        </Share>
</DCPlusPlus>
EOF
fi
msg_ok "Configured AirDCPP"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/airdcpp.service
[Unit]
Description=AirDC++ Web Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/airdcpp
ExecStart=/opt/airdcpp/airdcppd -c=/opt/airdcpp_data
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now airdcpp
msg_ok "Created Service"

echo -e "${INFO}${YW}Web UI login:${CL} ${GN}admin${CL} / ${GN}${ADMIN_PASS}${CL}"

motd_ssh
customize
cleanup_lxc

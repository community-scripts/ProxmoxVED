#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: aodesser
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Chaptarr/chaptarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="20" setup_nodejs
DOTNET_VERSION="10" DOTNET_TYPE="sdk" setup_dotnet
setup_ffmpeg

msg_info "Installing Yarn"
$STD npm install -g yarn@1.22.19
msg_ok "Installed Yarn"

# Chaptarr only publishes source tarballs and marks every release as a
# GitHub prerelease (beta software), so /releases/latest 404s without this.
GH_INCLUDE_PRERELEASE=1 fetch_and_deploy_gh_release "chaptarr" "Chaptarr/chaptarr" "tarball"

msg_info "Building Chaptarr (Patience)"
cd /opt/chaptarr
$STD yarn install --frozen-lockfile
$STD yarn build
rm -rf /opt/chaptarr_app
$STD dotnet publish src/NzbDrone.Console/Chaptarr.Console.csproj -c Release -f net10.0 -o /opt/chaptarr_app /p:UseAppHost=false
mkdir -p /opt/chaptarr_app/UI
cp -r _output/UI/* /opt/chaptarr_app/UI/
msg_ok "Built Chaptarr"

msg_info "Configuring Chaptarr"
mkdir -p /opt/chaptarr_data
msg_ok "Configured Chaptarr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/chaptarr.service
[Unit]
Description=Chaptarr
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/chaptarr_app
ExecStart=/usr/bin/dotnet /opt/chaptarr_app/Chaptarr.dll -nobrowser -data=/opt/chaptarr_data
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now chaptarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

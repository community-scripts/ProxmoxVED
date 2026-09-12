#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Cathal O'Connor (CathalOConnorRH)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Chaptarr/chaptarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

$STD apt install -y \
  git \
  build-essential

DOTNET_VERSION="10" setup_dotnet
NODE_VERSION="22" setup_nodejs
setup_ffmpeg

$STD npm install -g yarn@1.22.22

if [[ ! -d /opt/chaptarr ]]; then
  git clone --branch develop https://github.com/Chaptarr/chaptarr.git /opt/chaptarr
fi

msg_info "Building Frontend (Yarn)"
cd /opt/chaptarr
$STD yarn install --frozen-lockfile
$STD yarn build
msg_ok "Built Frontend"

msg_info "Building Backend (.NET)"
cd /opt/chaptarr/src
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export NUGET_XMLDOC_MODE=skip
sed -i 's#</Project>#  <PropertyGroup>\n    <NoWarn>$(NoWarn);NU1701;NU1902;CS1591</NoWarn>\n    <GenerateDocumentationFile>false</GenerateDocumentationFile>\n  </PropertyGroup>\n</Project>#' Directory.Build.props
$STD dotnet restore Chaptarr.NoTests.sln -r linux-x64 --disable-parallel /p:RestoreUseStaticGraphEvaluation=true
$STD dotnet publish NzbDrone.Console/Chaptarr.Console.csproj -c Release -f net10.0 -r linux-x64 -o /opt/chaptarr/_output/publish --no-restore
git checkout -- Directory.Build.props
cp -r /opt/chaptarr/_output/UI /opt/chaptarr/_output/publish/
cd /opt/chaptarr
rm -rf _output/UI
msg_ok "Built Backend"

msg_info "Creating Data Directory"
mkdir -p /opt/chaptarr_data
msg_ok "Created Data Directory"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/chaptarr.service
[Unit]
Description=Chaptarr Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/chaptarr
Environment=ASPNETCORE_URLS=http://+:8789
Environment=CHAPTARR_DATA_PATH=/opt/chaptarr_data
ExecStart=/usr/share/dotnet/dotnet /opt/chaptarr/_output/publish/Chaptarr.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now chaptarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

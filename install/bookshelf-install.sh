#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: savagecore
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/pennydreadful/bookshelf

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  git \
  jq \
  xmlstarlet \
  ca-certificates \
  libsqlite3-0
msg_ok "Installed Dependencies"

msg_info "Setting up Microsoft .NET repository"
setup_deb822_repo \
  "microsoft" \
  "https://packages.microsoft.com/keys/microsoft-2025.asc" \
  "https://packages.microsoft.com/debian/12/prod/" \
  "bookworm" \
  "main"
$STD apt-get install -y dotnet-sdk-6.0
msg_ok "Installed .NET SDK 6.0"

NODE_VERSION="20" NODE_MODULE="yarn" setup_nodejs

msg_info "Setup ${APP}"
$STD git clone --branch develop --depth 1 https://github.com/pennydreadful/bookshelf.git /opt/bookshelf-src
cd /opt/bookshelf-src
export READARRVERSION="0.4.20.0"
$STD ./build.sh --backend --frontend --packages -f net6.0 -r linux-x64
mkdir -p /opt/bookshelf/bin
$STD cp -r _artifacts/linux-x64/net6.0/Readarr/* /opt/bookshelf/bin/
chmod +x /opt/bookshelf/bin/Readarr
mkdir -p /var/lib/bookshelf
chmod 775 /var/lib/bookshelf
RELEASE=$(git log -1 --format=%h origin/develop)
cat <<EOF >/opt/bookshelf/package_info
UpdateMethod=External
Branch=develop
PackageVersion=${RELEASE}
PackageAuthor=community-scripts
EOF
echo "${RELEASE}" >/opt/Bookshelf_version.txt
rm -rf /opt/bookshelf-src/_output /opt/bookshelf-src/_artifacts /opt/bookshelf-src/_tests
msg_ok "Setup ${APP}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bookshelf.service
[Unit]
Description=Bookshelf Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
Environment=METADATA_URL=https://hardcover.bookinfo.pro
Environment=HARDCOVER=true
WorkingDirectory=/opt/bookshelf/bin
ExecStart=/opt/bookshelf/bin/Readarr -nobrowser -data=/var/lib/bookshelf
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bookshelf
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

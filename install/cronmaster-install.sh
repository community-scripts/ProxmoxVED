#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fccview/cronmaster

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt install -y pciutils
msg_ok "Installed dependencies"

NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs

setup_deb822_repo \
  "docker" \
  "https://download.docker.com/linux/debian/gpg" \
  "https://download.docker.com/linux/debian" \
  "trixie" \
  "stable"
$STD apt install -y docker-ce-cli
fetch_and_deploy_gh_release "cronmaster" "fccview/cronmaster" "tarball"

msg_info "Setting up CronMaster"
AUTH_PASS="$(openssl rand -base64 18 | cut -c1-13)"
cd /opt/cronmaster
$STD yarn --frozen-lockfile
export NEXT_TELEMETRY_DISABLED=1
$STD yarn build
cat <<EOF >/opt/cronmaster/.env
NODE_ENV=production
APP_URL=
LOCALE=
HOME=
AUTH_PASSWORD=${AUTH_PASS}
PORT=3000
HOSTNAME="0.0.0.0"
NEXT_TELEMETRY_DISABLED=1
EOF
{
  echo "CronMaster Credentials:"
  echo ""
  echo "Password: $AUTH_PASS"
}>>~/cronmaster.creds
msg_ok "Setup CronMaster"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/cronmaster.service
[Unit]
Description=CronMaster Service
After=network.target

[Service]
EnvironmentFile=/opt/cronmaster/.env
WorkingDirectory=/opt/cronmaster
ExecStart=/usr/bin/yarn start
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl start --now -q cronmaster
msg_info "Created Service"

motd_ssh
customize
cleanup_lxc

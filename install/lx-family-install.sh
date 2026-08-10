#!/usr/bin/env bash

# Copyright (c) 2026 community-scripts ORG
# Author: LaxXx Lab (laxxx-lab)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/laxxx-lab/lx-family-planner

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
# The Helper-Scripts completion hook uses the lower-case application slug to
# create `/usr/bin/update`. It is not always exported into the LXC context.
app="${app:-lx-family}"
export app

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# NodeSource keys are ASCII-armored and therefore need the `gpg` executable
# before the Helper-Scripts Node.js repository helper imports them. Checking
# the executable (rather than the `gnupg` meta package) also handles fresh
# Debian containers where that package name may only be a removed-package
# residue.
ensure_dependencies curl ca-certificates gpg

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "lx-family" "laxxx-lab/lx-family-planner" "tarball"

msg_info "Configuring LX Family"
mkdir -p /opt/lx-family/data /opt/lx-family/backups
chmod 700 /opt/lx-family/data /opt/lx-family/backups
cat <<EOF >/opt/lx-family/.env
APP_SECRET="$(node -e "process.stdout.write(require('node:crypto').randomBytes(48).toString('hex'))")"
NODE_ENV=production
PORT=3001
APP_LANGUAGE=de
SESSION_COOKIE_SECURE=auto
REGISTRATION_MODE=first-family
DATABASE_FILE=/opt/lx-family/data/family_planner.sqlite
LEGACY_DATABASE_FILE=/opt/lx-family/data/family_db.json
BACKUP_DIRECTORY=/opt/lx-family/backups
EOF
chmod 600 /opt/lx-family/.env
msg_ok "Configured LX Family"

msg_info "Installing LX Family"
cd /opt/lx-family
$STD npm ci
$STD npm run build
msg_ok "Installed LX Family"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/lx-family.service
[Unit]
Description=LX Family Private Family OS
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lx-family
ExecStart=/usr/bin/node --env-file-if-exists=.env server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now lx-family
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

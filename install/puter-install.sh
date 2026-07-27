#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/HeyPuter/puter

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  git \
  python3
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "puter" "HeyPuter/puter" "tarball"

msg_info "Building Application"
cd /opt/puter
$STD npm ci
$STD npm run build
msg_ok "Built Application"

msg_info "Configuring Application"
mkdir -p /etc/puter/extensions /var/puter/s3-data /var/puter/s3-storage
JWT_SECRET=$(openssl rand -hex 64)
JWT_SECRET_V2=$(openssl rand -hex 64)
URL_SIGNATURE_SECRET=$(openssl rand -hex 64)
cat <<EOF >/etc/puter/config.json
{
  "config_name": "proxmox",
  "env": "prod",
  "domain": "puter.${LOCAL_IP}.nip.io",
  "protocol": "http",
  "port": 4100,
  "pub_port": 4100,
  "allow_nipio_domains": true,
  "jwt_secret": "${JWT_SECRET}",
  "jwt_secret_v2": "${JWT_SECRET_V2}",
  "allow_v1_tokens": true,
  "url_signature_secret": "${URL_SIGNATURE_SECRET}",
  "extensions": ["/etc/puter/extensions"],
  "database": {
    "engine": "sqlite",
    "path": "/var/puter/puter-database.sqlite"
  },
  "redis": {
    "useMock": true
  },
  "s3": {
    "localConfig": {
      "inMemory": false,
      "dataDir": "/var/puter/s3-data",
      "s3StorageDir": "/var/puter/s3-storage"
    }
  },
  "providers": {
    "ollama": { "enabled": false }
  }
}
EOF
cat <<'EXTEOF' >/etc/puter/extensions/subdomain-fix.cjs
'use strict';
// Puter extension: fix Express subdomain offset for multi-part nip.io domains.
// By default Express uses offset=2 (correct for puter.com / puter.localhost).
// For nip.io IP domains (e.g. puter.192.168.0.151.nip.io = 7 parts) the offset
// must equal the domain part count so the homepage route matches correctly.
const { extension } = require('/opt/puter/dist/src/backend/extensions.js');
const domain = (extension.config && extension.config.domain) || 'puter.localhost';
const offset = domain.split('.').length;
if (offset !== 2) {
    extension.registerGlobalMiddleware(function subdomainOffsetFix(req, _res, next) {
        req.app.set('subdomain offset', offset);
        next();
    });
}
EXTEOF
msg_ok "Configured Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/puter.service
[Unit]
Description=Puter
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/puter
Environment=PUTER_CONFIG_PATH=/etc/puter/config.json
ExecStart=/usr/bin/node --enable-source-maps -r /opt/puter/dist/src/backend/telemetry.js /opt/puter/dist/src/backend/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now puter
msg_ok "Created Service"

msg_info "Retrieving Admin Credentials"
for _ in $(seq 1 60); do
  ADMIN_PASS=$(journalctl -u puter --no-pager 2>/dev/null | grep -oP 'password for admin is: \K\S+' | tail -1 || true)
  [[ -n "$ADMIN_PASS" ]] && break
  sleep 2
done
if [[ -n "$ADMIN_PASS" ]]; then
  cat <<EOF >~/puter.creds
Puter Admin Credentials
Username: admin
Password: ${ADMIN_PASS}
EOF
  msg_ok "Retrieved Admin Credentials"
else
  msg_warn "Could not capture admin password automatically; retrieve it with: journalctl -u puter | grep -i password"
fi

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: BrynnJKnight
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://verdaccio.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  ca-certificates \
  build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Installing Verdaccio"
$STD npm install --global verdaccio
msg_ok "Installed Verdaccio"

msg_info "Configuring Verdaccio"
HOST_IP=$(hostname -I | awk '{print $1}')
mkdir -p /etc/verdaccio
mkdir -p /var/lib/verdaccio

cat <<EOF >/etc/verdaccio/config.yaml
# Verdaccio configuration
storage: /var/lib/verdaccio
auth:
  htpasswd:
    file: /var/lib/verdaccio/htpasswd
    max_users: 1000
uplinks:
  npmjs:
    url: https://registry.npmjs.org/
packages:
  '@*/*':
    access: \$all
    publish: \$authenticated
    proxy: npmjs
  '**':
    access: \$all
    publish: \$authenticated
    proxy: npmjs
middlewares:
  audit:
    enabled: true
logs:
  - {type: stdout, format: pretty, level: http}
listen:
  - 0.0.0.0:4873
web:
  enable: true
  title: Verdaccio
  gravatar: true
  sort_packages: asc
  login: true
EOF

chown -R root:root /etc/verdaccio
chown -R root:root /var/lib/verdaccio
chmod -R 755 /etc/verdaccio
chmod -R 755 /var/lib/verdaccio
msg_ok "Configured Verdaccio"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/verdaccio.service
[Unit]
Description=Verdaccio lightweight private npm proxy registry
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/verdaccio --config /etc/verdaccio/config.yaml
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=verdaccio
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now verdaccio
msg_ok "Created Service"

msg_info "Creating Update Script"
cat <<'EOF' >/usr/bin/update
#!/bin/bash
set -euo pipefail
NODE_VERSION="22"
export NVM_DIR="/opt/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use $NODE_VERSION >/dev/null 2>&1

echo "Updating Verdaccio..."
npm update -g verdaccio
systemctl restart verdaccio
echo "Verdaccio has been updated successfully."
EOF
chmod +x /usr/bin/update
msg_ok "Created Update Script"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
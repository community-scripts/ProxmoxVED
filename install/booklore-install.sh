#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y nginx
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "booklore" "adityachandelgit/BookLore" "/opt/booklore"
JAVA_VERSION="21" setup_java
NODE_VERSION="22" setup_nodejs

msg_info "Building Frontend"
cd /opt/booklore/booklore-ui
$STD npm install --force
$STD npm run build --configuration=production
msg_ok "Built Frontend"

msg_info "Building Backend"
cd /opt/booklore/booklore-api
APP_VERSION="0.0.1-Test"
yq eval ".app.version = \"${APP_VERSION}\"" -i src/main/resources/application.yaml
$STD ./gradlew clean build --no-daemon
msg_ok "Built Backend"

msg_info "Creating Systemd Service"
cat <<EOF >/etc/systemd/system/booklore.service
[Unit]
Description=BookLore Java Service
After=network.target

[Service]
User=root
WorkingDirectory=/opt/booklore/booklore-api
ExecStart=/usr/bin/java -jar build/libs/booklore-api-${APP_VERSION}.jar
SuccessExitStatus=143
TimeoutStopSec=10
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now booklore
msg_ok "Created BookLore Service"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/booklore
server {
    listen 80 default_server;
    root /usr/share/nginx/html;
    index index.html;
    location /api/ {
        proxy_pass http://localhost:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/booklore /etc/nginx/sites-enabled/default
$STD systemctl restart nginx
msg_ok "Configured Nginx"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

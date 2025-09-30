#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: prop4n
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.sonarsource.com/sonarqube-server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

JAVA_VERSION="21" setup_java
PG_VERSION="17" setup_postgresql
fetch_and_deploy_gh_release "sonarqube" "SonarSource/sonarqube" "tarball"

msg_info "Installing Postgresql"
DB_NAME="sonarqube"
DB_USER="sonarqube"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
{
  echo "Application Credentials"
  echo "DB_NAME: $DB_NAME"
  echo "DB_USER: $DB_USER"
  echo "DB_PASS: $DB_PASS"
} >>~/sonarqube.creds
msg_ok "Installed PostgreSQL"

msg_info "Configuring SonarQube"
chown -R sonarqube:sonarqube /opt/sonarqube
chmod -R 755 /opt/sonarqube
mkdir -p /opt/sonarqube/conf
cat >/opt/sonarqube/conf/sonar.properties <<EOF
sonar.jdbc.username=${DB_USER}
sonar.jdbc.password=${DB_PASS}
sonar.jdbc.url=jdbc:postgresql://localhost/${DB_NAME}
sonar.web.host=0.0.0.0
sonar.web.port=9000
EOF
chmod +x /opt/sonarqube/bin/linux-x86-64/sonar.sh
msg_ok "Configured SonarQube"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/sonarqube.service
[Unit]
Description=SonarQube service
After=postgresql.service

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonarqube
Group=sonarqube
Restart=on-failure
LimitNOFILE=131072
LimitNPROC=8192

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now sonarqube
msg_ok "Service Created"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

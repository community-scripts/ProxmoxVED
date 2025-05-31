#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: C S P Nanda(cspnanda)
# License: MIT
# https://raw.githubusercontent.com/community-scripts/ProxmoxVE/refs/heads/main/LICENSE 

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt update && apt-get install -y \
  wget \
  curl \
  apt-transport-https \
  gpg
msg_ok "Installed Dependencies"

wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list
apt update
apt-get install -y temurin-21-jdk

METABASE_VERSION=`curl -s https://api.github.com/repos/metabase/metabase/releases/latest|awk -F \" -v RS="," '/tarball_url/ {print $(NF-1)}'|awk -F '/' '{print $NF}'`
METABASE_DIR=/opt/metabase
METABASE_SERVICE_FILE=/etc/systemd/system/metabase.service
mkdir -p $METABASE_DIR
msg_info "Getting metabase jar"
msg_info "https://downloads.metabase.com/$METABASE_VERSION/metabase.jar -> $METABASE_DIR/metabase.jar"
curl https://downloads.metabase.com/$METABASE_VERSION/metabase.jar -o $METABASE_DIR/metabase.jar
msg_ok "Successfully Downloaded metabase jar"

groupadd -r metabase
useradd -r -s /bin/false -g metabase metabase
chown -R metabase:metabase $METABASE_DIR
touch /etc/default/metabase
chmod 640 /etc/default/metabase

cat <<EOF >/etc/default/metabase
MB_PASSWORD_COMPLEXITY=normal
MB_PASSWORD_LENGTH=16
MB_JETTY_HOST=0.0.0.0
MB_JETTY_PORT=3000
MB_DB_TYPE=h2
MB_DB_DBNAME=metabase
MB_EMOJI_IN_LOGS=true
EOF

cat <<EOF >$METABASE_SERVICE_FILE
[Unit]
Description=Metabase server
After=syslog.target
After=network.target

[Service]
WorkingDirectory=/opt/metabase
ExecStart=/usr/bin/java --add-opens java.base/java.nio=ALL-UNNAMED -jar /opt/metabase/metabase.jar
EnvironmentFile=/etc/default/metabase
User=metabase
Type=simple
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=metabase
SuccessExitStatus=143
TimeoutStopSec=120
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

systemctl start metabase.service
systemctl status metabase.service
systemctl enable metabase.service

msg_info "Waiting for metabase to start"
while ! nc -z localhost 3000; do   
  sleep 5 # wait for 3 seconds before check again
done


motd_ssh
customize


msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: aendel
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nightscout/cgm-remote-monitor

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git curl build-essential libssl-dev
msg_ok "Installed Dependencies"

MONGO_VERSION="8.0" setup_mongodb
NODE_VERSION="22" setup_nodejs

msg_info "Installing Nightscout (Patience)"
cd /opt || exit
git clone https://github.com/nightscout/cgm-remote-monitor.git nightscout
cd nightscout || exit
$STD npm install
msg_ok "Installed Nightscout"

msg_info "Creating Service"
useradd -s /bin/bash -m nightscout
chown -R nightscout:nightscout /opt/nightscout

# Create a default my.env file if it doesn't exist, to prevent crash on start if user doesn't configure it immediately?
# Nightscout needs env vars to run. We will create a template.
cat <<EOF > /opt/nightscout/my.env
# DB connection string. 
# MongoDB is installed locally on port 27017. 
# You should create a DB and user in Mongo, or trust localhost auth.
# For simplicity in this script we assume localhost with no auth for local binding or the user must configure it.
# However, the installation guide recommends creating a user.
# For now, we point to localhost test DB.
MONGO_CONNECTION=mongodb://127.0.0.1:27017/nightscout
BASE_URL=http://localhost:1337
API_SECRET=yoursecret123
DISPLAY_UNITS=mg/dl
ENABLE=careportal boluscalc food bwp cage sage iage iob cob basal ar2 rawbg pushover bgi pump openaps pvb linear custom
# Allow HTTP (avoids redirect loops with reverse proxies)
INSECURE_USE_HTTP=true
EOF
chown nightscout:nightscout /opt/nightscout/my.env

cat <<EOF >/etc/systemd/system/nightscout.service
[Unit]
Description=Nightscout CGM Service
After=network.target mongodb.service

[Service]
Type=simple
User=nightscout
WorkingDirectory=/opt/nightscout
EnvironmentFile=/opt/nightscout/my.env
# Some deployments use 'npm start', others 'node server.js'. npm start is safer.
ExecStart=/usr/bin/npm start
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now nightscout
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

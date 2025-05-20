#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: aliaksei135
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/arpanghosh8453/garmin-grafana

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
    gnupg \
    apt-transport-https \
    software-properties-common \
    lsb-base \
    lsb-release \
    gnupg2 \
    python3 \
    python3-requests \
    python3-dotenv
setup_uv
msg_ok "Installed Dependencies"

msg_info "Setting up InfluxDB Repository"
curl -fsSL "https://repos.influxdata.com/influxdata-archive_compat.key" | gpg --dearmor >/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main" >/etc/apt/sources.list.d/influxdata.list
msg_ok "Set up InfluxDB Repository"

# garmin-grafana recommends influxdb v1
# this install chronograf, which is the UI for influxdb. this might be overkill?
msg_info "Installing InfluxDB"
$STD apt-get update
$STD apt-get install -y influxdb
curl -fsSL "https://dl.influxdata.com/chronograf/releases/chronograf_1.10.7_amd64.deb" -o "$(basename "https://dl.influxdata.com/chronograf/releases/chronograf_1.10.7_amd64.deb")"
$STD dpkg -i chronograf_1.10.7_amd64.deb
msg_ok "Installed InfluxDB"

msg_info "Setting up InfluxDB"
$STD sed -i 's/# index-version = "inmem"/index-version = "tsi1"/' /etc/influxdb/influxdb.conf

INFLUXDB_USER="garmin_grafana_user"
INFLUXDB_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
INFLUXDB_NAME="GarminStats"
$STD influx -execute "CREATE DATABASE ${INFLUXDB_NAME}"
$STD influx -execute "CREATE USER ${INFLUXDB_USER} WITH PASSWORD '${INFLUXDB_PASSWORD}'"
$STD influx -execute "GRANT ALL ON ${INFLUXDB_NAME} TO ${INFLUXDB_USER}"
# Start the service
$STD systemctl enable --now influxdb
msg_ok "Set up InfluxDB"

msg_info "Setting up Grafana Repository"
curl -fsSL "https://apt.grafana.com/gpg.key" -o "/usr/share/keyrings/grafana.key"
sh -c 'echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list'
msg_ok "Set up Grafana Repository"

msg_info "Installing Grafana"
$STD apt-get update
$STD apt-get install -y grafana
systemctl start grafana-server
systemctl daemon-reload
systemctl enable --now -q grafana-server.service
# This avoids the "database is locked" error when running the grafana-cli
sleep 20
msg_ok "Installed Grafana"

msg_info "Setting up Grafana"
GRAFANA_USER="admin"
GRAFANA_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
$STD grafana-cli admin reset-admin-password "${GRAFANA_PASS}"
$STD grafana-cli plugins install marcusolsson-hourly-heatmap-panel
$STD systemctl restart grafana-server
# Output credentials to file
{
  echo "Grafana Credentials"
  echo "Grafana User: ${GRAFANA_USER}"
  echo "Grafana Password: ${GRAFANA_PASS}"
} >>~/garmin-grafana.creds
msg_ok "Set up Grafana"

# Setup App
msg_info "Installing garmin-grafana"
RELEASE=$(curl -fsSL https://api.github.com/repos/arpanghosh8453/garmin-grafana/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL -o "${RELEASE}.zip" "https://github.com/arpanghosh8453/garmin-grafana/archive/refs/tags/${RELEASE}.zip"
unzip -q "${RELEASE}.zip"
# Remove the v prefix to RELEASE if it exists
if [[ "${RELEASE}" == v* ]]; then
  RELEASE="${RELEASE:1}"
fi
mv "garmin-grafana-${RELEASE}/" "/opt/garmin-grafana"
mkdir -p /opt/garmin-grafana/.garminconnect
$STD uv sync --locked --project /opt/garmin-grafana/
# Setup grafana provisioning configs
# shellcheck disable=SC2016
sed -i 's/\${DS_GARMIN_STATS}/garmin_influxdb/g' /opt/garmin-grafana/Grafana_Dashboard/Garmin-Grafana-Dashboard.json
sed -i 's/influxdb:8086/localhost:8086/' /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
sed -i "s/influxdb_user/${INFLUXDB_USER}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
sed -i "s/influxdb_secret_password/${INFLUXDB_PASSWORD}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
sed -i "s/GarminStats/${INFLUXDB_NAME}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
# Copy across grafana data
cp -r /opt/garmin-grafana/Grafana_Datasource/* /etc/grafana/provisioning/datasources
cp -r /opt/garmin-grafana/Grafana_Dashboard/* /etc/grafana/provisioning/dashboards
echo "${RELEASE}" >"/opt/garmin-grafana_version.txt"
msg_ok "Installed garmin-grafana"

msg_info "Setting up garmin-grafana"
# Check if using Chinese garmin servers
read -rp "Are you using Garmin in mainland China? (y/N): " prompt
if [[ "${prompt,,}" =~ ^(y|yes|Y)$ ]]; then
  GARMIN_CN="True"
else
  GARMIN_CN="False"
fi

cat <<EOF >/opt/garmin-grafana/.env
INFLUXDB_HOST=localhost
INFLUXDB_PORT=8086
INFLUXDB_ENDPOINT_IS_HTTP=True
INFLUXDB_USERNAME=${INFLUXDB_USER}
INFLUXDB_PASSWORD=${INFLUXDB_PASSWORD}
INFLUXDB_DATABASE=${INFLUXDB_NAME}
GARMIN_IS_CN=${GARMIN_CN}
TOKEN_DIR=/opt/garmin-grafana/.garminconnect
EOF

# garmin-grafana usually prompts the user for email and password (and MFA) on first run,
# then stores a refreshable token. We try to avoid storing user credentials in the env vars
if [ -z "$(ls -A /opt/garmin-grafana/.garminconnect)" ]; then
  read -r -p "Please enter your Garmin Connect Email: " GARMIN_EMAIL
  read -r -p "Please enter your Garmin Connect Password (this is used to generate a token and NOT stored): " GARMIN_PASSWORD
  read -r -p "Please enter your MFA Code (if applicable, leave blank if not): " GARMIN_MFA
  # Run the script once to prompt for credential
  msg_info "Creating Garmin credentials, this will timeout in 60 seconds"
  timeout 60s uv run --env-file /opt/garmin-grafana/.env --project /opt/garmin-grafana/ /opt/garmin-grafana/src/garmin_grafana/garmin_fetch.py <<EOF
${GARMIN_EMAIL}
${GARMIN_PASSWORD}
${GARMIN_MFA}
EOF
  unset GARMIN_EMAIL
  unset GARMIN_PASSWORD
  unset GARMIN_MFA
  # Check if there is anything in the token dir now
  if [ -z "$(ls -A /opt/garmin-grafana/.garminconnect)" ]; then
    msg_error "Failed to create a token"
    exit
  fi
fi

$STD systemctl restart grafana-server

# Add a script to make the manual bulk data import easier
cat <<EOF >~/bulk-import.sh
#!/usr/bin/env bash
if [[ -z \$1 ]]; then
  echo "Usage: \$0 <start_date> <end_date>"
  echo "Example: \$0 2023-01-01 2023-01-31"
  echo "Date format: YYYY-MM-DD"
  echo "This will import data from the start_date to the end_date (inclusive)"
  exit 1
fi

START_DATE="\$1"
if [[ -z \$2 ]]; then
  END_DATE="\$(date +%Y-%m-%d)"
  echo "No end date provided, using today as end date: \${END_DATE}"
else
  END_DATE="\$2"
fi

# Stop the service if running
systemctl stop garmin-grafana

MANUAL_START_DATE="\${START_DATE}" MANUAL_END_DATE="\${END_DATE}" uv run --env-file /opt/garmin-grafana/.env --project /opt/garmin-grafana/ /opt/garmin-grafana/src/garmin_grafana/garmin_fetch.py

# Restart the service
systemctl start garmin-grafana
EOF
chmod +x ~/bulk-import.sh
msg_ok "Set up garmin-grafana"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/garmin-grafana.service
[Unit]
Description=garmin-grafana Service
After=network.target

[Service]
ExecStart=uv run --project /opt/garmin-grafana/ /opt/garmin-grafana/src/garmin_grafana/garmin_fetch.py
Restart=always
EnvironmentFile=/opt/garmin-grafana/.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now garmin-grafana
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f "${RELEASE}".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

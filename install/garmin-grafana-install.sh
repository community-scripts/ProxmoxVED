#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: aliaksei135
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/arpanghosh8453/garmin-grafana

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_uv

setup_deb822_repo "influxdb" \
  "https://repos.influxdata.com/influxdata-archive.key" \
  "https://repos.influxdata.com/debian" \
  "stable" \
  "main"

msg_info "Installing InfluxDB"
$STD apt install -y influxdb
msg_ok "Installed InfluxDB"

msg_info "Installing Chronograf"
CHRONOGRAF_VERSION=$(get_latest_github_release "influxdata/chronograf")
fetch_and_deploy_from_url "https://dl.influxdata.com/chronograf/releases/chronograf_${CHRONOGRAF_VERSION}_amd64.deb" ""
msg_ok "Installed Chronograf"

msg_info "Configuring InfluxDB"
sed -i 's/# index-version = "inmem"/index-version = "tsi1"/' /etc/influxdb/influxdb.conf
$STD systemctl enable --now influxdb
INFLUXDB_USER="garmin_grafana_user"
INFLUXDB_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
INFLUXDB_NAME="GarminStats"
$STD influx -execute "CREATE DATABASE ${INFLUXDB_NAME}"
$STD influx -execute "CREATE USER ${INFLUXDB_USER} WITH PASSWORD '${INFLUXDB_PASSWORD}'"
$STD influx -execute "GRANT ALL ON ${INFLUXDB_NAME} TO ${INFLUXDB_USER}"
msg_ok "Configured InfluxDB"

setup_deb822_repo "grafana" \
  "https://apt.grafana.com/gpg.key" \
  "https://apt.grafana.com" \
  "stable" \
  "main"

msg_info "Installing Grafana"
$STD apt install -y grafana
$STD systemctl enable --now grafana-server
msg_ok "Installed Grafana"

msg_info "Configuring Grafana"
GRAFANA_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
retries=0
while ! grafana-cli admin reset-admin-password "${GRAFANA_PASS}" &>/dev/null; do
  retries=$((retries + 1))
  [[ $retries -ge 30 ]] && break
  sleep 2
done
$STD grafana-cli --homepath /usr/share/grafana plugins install marcusolsson-hourly-heatmap-panel
$STD systemctl restart grafana-server
msg_ok "Configured Grafana"

fetch_and_deploy_gh_release "garmin-grafana" "arpanghosh8453/garmin-grafana" "tarball"

msg_info "Installing Python Dependencies"
mkdir -p /opt/garmin-grafana/.garminconnect
$STD uv sync --locked --project /opt/garmin-grafana/
msg_ok "Installed Python Dependencies"

msg_info "Provisioning Grafana Dashboard & Datasource"
sed -i 's/\${DS_GARMIN_STATS}/garmin_influxdb/g' /opt/garmin-grafana/Grafana_Dashboard/Garmin-Grafana-Dashboard.json
sed -i 's/influxdb:8086/localhost:8086/' /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
sed -i "s/influxdb_user/${INFLUXDB_USER}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
sed -i "s/influxdb_secret_password/${INFLUXDB_PASSWORD}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
sed -i "s/GarminStats/${INFLUXDB_NAME}/" /opt/garmin-grafana/Grafana_Datasource/influxdb.yaml
cp -r /opt/garmin-grafana/Grafana_Datasource/* /etc/grafana/provisioning/datasources
cp -r /opt/garmin-grafana/Grafana_Dashboard/* /etc/grafana/provisioning/dashboards
msg_ok "Provisioned Grafana Dashboard & Datasource"

read -rp "Are you using Garmin in mainland China? (y/N): " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  GARMIN_CN="True"
else
  GARMIN_CN="False"
fi

msg_info "Writing Environment Configuration"
cat <<EOF >/opt/garmin-grafana/.env
INFLUXDB_HOST=localhost
INFLUXDB_PORT=8086
INFLUXDB_ENDPOINT_IS_HTTP=True
INFLUXDB_USERNAME=${INFLUXDB_USER}
INFLUXDB_PASSWORD=${INFLUXDB_PASSWORD}
INFLUXDB_DATABASE=${INFLUXDB_NAME}
GARMIN_IS_CN=${GARMIN_CN}
TOKEN_DIR=/opt/garmin-grafana/.garminconnect
GRAFANA_USER=admin
GRAFANA_PASSWORD=${GRAFANA_PASS}
EOF
msg_ok "Wrote Environment Configuration"

if [[ -z "$(ls -A /opt/garmin-grafana/.garminconnect)" ]]; then
  read -r -p "Please enter your Garmin Connect Email: " GARMIN_EMAIL
  read -r -p "Please enter your Garmin Connect Password (used to generate token, NOT stored): " GARMIN_PASSWORD
  read -r -p "Please enter your MFA Code (leave blank if not applicable): " GARMIN_MFA
  GARMIN_BASE64_PASSWORD=$(echo -n "${GARMIN_PASSWORD}" | base64 -w0)
  msg_info "Creating Garmin credentials (timeout 60s)"
  if [[ -n "${GARMIN_MFA}" ]]; then
    echo "${GARMIN_MFA}" | GARMINCONNECT_EMAIL="${GARMIN_EMAIL}" GARMINCONNECT_BASE64_PASSWORD="${GARMIN_BASE64_PASSWORD}" \
      timeout 60s uv run --env-file /opt/garmin-grafana/.env --project /opt/garmin-grafana/ /opt/garmin-grafana/src/garmin_grafana/garmin_fetch.py
  else
    GARMINCONNECT_EMAIL="${GARMIN_EMAIL}" GARMINCONNECT_BASE64_PASSWORD="${GARMIN_BASE64_PASSWORD}" \
      timeout 60s uv run --env-file /opt/garmin-grafana/.env --project /opt/garmin-grafana/ /opt/garmin-grafana/src/garmin_grafana/garmin_fetch.py </dev/null
  fi
  unset GARMIN_EMAIL GARMIN_PASSWORD GARMIN_MFA GARMIN_BASE64_PASSWORD
  if [[ -z "$(ls -A /opt/garmin-grafana/.garminconnect)" ]]; then
    msg_error "Failed to create token"
    exit 1
  fi
  msg_ok "Created Garmin credentials"
fi

$STD systemctl restart grafana-server

msg_info "Installing Bulk Import Helper"
cat <<'EOF' >/usr/local/bin/garmin-bulk-import
#!/usr/bin/env bash
if [[ -z $1 ]]; then
  echo "Usage: $0 <start_date> [end_date]"
  echo "Example: $0 2023-01-01 2023-01-31"
  exit 1
fi
START_DATE="$1"
END_DATE="${2:-$(date +%Y-%m-%d)}"
systemctl stop garmin-grafana
MANUAL_START_DATE="${START_DATE}" MANUAL_END_DATE="${END_DATE}" uv run --env-file /opt/garmin-grafana/.env --project /opt/garmin-grafana/ /opt/garmin-grafana/src/garmin_grafana/garmin_fetch.py
systemctl start garmin-grafana
EOF
chmod +x /usr/local/bin/garmin-bulk-import
msg_ok "Installed Bulk Import Helper"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/garmin-grafana.service
[Unit]
Description=garmin-grafana Service
After=network.target influxdb.service
Requires=influxdb.service

[Service]
Type=simple
WorkingDirectory=/opt/garmin-grafana
EnvironmentFile=/opt/garmin-grafana/.env
ExecStart=$(which uv) run --project /opt/garmin-grafana/ /opt/garmin-grafana/src/garmin_grafana/garmin_fetch.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now garmin-grafana
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thieneret
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Euro-Office

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Creating RabitMQ configuration"
mkdir -p /etc/rabbitmq
cat <<EOF >/etc/rabbitmq/rabbitmq-env.conf
NODENAME=rabbit@localhost
NODE_IP_ADDRESS=127.0.0.1
NODE_PORT=5672
EOF
msg_ok "Created RabitMQ configuration"

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  git \
  redis-server \
  rabbitmq-server \
  nginx
msg_ok "Installed Dependencies"

setup_yq
PG_VERSION="17" setup_postgresql
PG_DB_NAME="eurooffice" PG_DB_USER="eurooffice" setup_postgresql_db

msg_info "Create documentserver install config"
cat <<EOF >/opt/setup_eo
ds ds/db-type select postgres
ds ds/db-host string localhost
ds ds/db-port string 5432
ds ds/db-user string eurooffice
ds ds/db-pwd password ${PG_DB_PASS}
ds ds/db-name string eurooffice
EOF
debconf-set-selections /opt/setup_eo
msg_ok "Documentserver install config created"

fetch_and_deploy_gh_release "EuroOffice" "Euro-Office/DocumentServer" "binary" "latest" "/opt/eurooffice" "euro-office-documentserver_*.deb"

msg_info "Configuring Euro-Office"
EUO_SECRET=$(openssl rand -hex 32)
yq -i ".services.CoAuthoring.sql.type = \"postgres\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.sql.dbHost = \"127.0.0.1\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.sql.dbPort = \"5432\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.sql.dbName = \"eurooffice\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.sql.dbUser = \"eurooffice\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.sql.dbPass = \"${PG_DB_PASS}\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.token.enable.request.inbox = \"true\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.token.enable.request.outbox = \"true\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.token.enable.browser = \"true\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.token.inbox.header = \"Authorization\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.token.outbox.header = \"Authorization\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.secret.inbox.string = \"${EUO_SECRET}\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.secret.outbox.string = \"${EUO_SECRET}\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.secret.browser.string = \"${EUO_SECRET}\"" /etc/euro-office/documentserver/local.json
yq -i ".services.CoAuthoring.secret.session.string = \"${EUO_SECRET}\"" /etc/euro-office/documentserver/local.json

cat <<EOF >$HOME/.euro-office.creds
Set this in the Nextcloud administration settings Nextcloud Office settings:
Secret key:
${EUO_SECRET}
EOF
msg_ok "Configured Euro-Office"

msg_info "Starting services"
systemctl restart ds-docservice ds-converter ds-metrics
for i in {1..10}; do
  if [[ $(systemctl is-active ds-docservice) == active && $(systemctl is-active ds-converter) == active && $(systemctl is-active ds-metrics) == active ]]; then
	break
  fi
  sleep 1
done
systemctl restart nginx
msg_ok "Services started"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Test Suite for tools.func
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Purpose: Run comprehensive test suite for all setup_* functions from tools.func

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
apt install -y \
  redis-server \
  rabbitmq-server \
  libpq-dev
msg_ok "Installed Dependencies"

JAVA_VERSION="24" setup_java
PG_VERSION="17" PG_MODULES="postgis" setup_postgresql

msg_info "Setting up PostgreSQL"
DB_NAME="reitti_db"
DB_USER="reitti"
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
$STD sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS postgis;"
$STD sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS postgis_topology;"
{
  echo "Reitti Credentials"
  echo "Database Name: $DB_NAME"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
} >>~/reitti.creds
msg_ok "PostgreSQL Setup Completed"

msg_info "Configuring RabbitMQ"
RABBIT_USER="reitti"
RABBIT_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
RABBIT_VHOST="/"
$STD rabbitmqctl add_user "$RABBIT_USER" "$RABBIT_PASS"
$STD rabbitmqctl add_vhost "$RABBIT_VHOST"
$STD rabbitmqctl set_permissions -p "$RABBIT_VHOST" "$RABBIT_USER" ".*" ".*" ".*"
$STD rabbitmqctl set_user_tags "$RABBIT_USER" administrator
{
  echo ""
  echo "Reitti Credentials"
  echo "RabbitMQ User: $RABBIT_USER"
  echo "RabbitMQ Password: $RABBIT_PASS"
} >>~/reitti.creds
msg_ok "Configured RabbitMQ"

USE_ORIGINAL_FILENAME="true" fetch_and_deploy_gh_release "reitti" "dedicatedcode/reitti" "singlefile" "latest" "/opt/reitti" "reitti-app.jar"
mv /opt/reitti/reitti-*.jar /opt/reitti/reitti.jar
USE_ORIGINAL_FILENAME="true" fetch_and_deploy_gh_release "photon" "komoot/photon" "singlefile" "latest" "/opt/photon" "photon*.jar"
mv /opt/photon/photon-*.jar /opt/photon/photon.jar

msg_info "Create Configuration"
cat <<EOF >/opt/reitti/application.properties
# PostgreSQL Database Connection
spring.datasource.url=jdbc:postgresql://127.0.0.1:5432/$DB_NAME
spring.datasource.username=$DB_USER
spring.datasource.password=$DB_PASS
spring.datasource.driver-class-name=org.postgresql.Driver

# Flyway Database Migrations
spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
spring.flyway.baseline-on-migrate=true

# RabbitMQ (Message Queue)
spring.rabbitmq.host=127.0.0.1
spring.rabbitmq.port=5672
spring.rabbitmq.username=$RABBIT_USER
spring.rabbitmq.password=$RABBIT_PASS

# Redis (Cache)
spring.data.redis.host=127.0.0.1
spring.data.redis.port=6379

# Server Port
server.port=8080

# Optional: Logging & Performance
logging.level.root=INFO
spring.jpa.hibernate.ddl-auto=none
spring.datasource.hikari.maximum-pool-size=10

# Photon (Geocoding)
PHOTON_BASE_URL=http://127.0.0.1:2322
PROCESSING_WAIT_TIME=15
PROCESSING_BATCH_SIZE=1000
PROCESSING_WORKERS_PER_QUEUE=4-16

# Disable potentially dangerous features unless needed
DANGEROUS_LIFE=false
EOF

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/reitti.service
[Unit]
Description=Reitti
After=syslog.target network.target

[Service]
Type=simple
WorkingDirectory=/opt/reitti/
Environment=LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
ExecStart=/usr/bin/java --enable-native-access=ALL-UNNAMED -jar -Xmx2g reitti.jar
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/photon.service
[Unit]
Description=Photon Geocoding Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/photon
ExecStart=/usr/bin/java -Xmx2g -jar photon.jar
Restart=on-failure
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now photon
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

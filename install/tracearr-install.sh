#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: durzo
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/connorgallopo/Tracearr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y redis-server
msg_ok "Installed Dependencies"

NODE_VERSION="22"  NODE_MODULE="pnpm@10.24.0" setup_nodejs
PG_VERSION="18" setup_postgresql

msg_info "Installing TimescaleDB"
setup_deb822_repo \
  "timescaledb" \
  "https://packagecloud.io/timescale/timescaledb/gpgkey" \
  "https://packagecloud.io/timescale/timescaledb/debian" \
  "$(get_os_info codename)" \
  "main"
$STD apt install -y \
    timescaledb-2-postgresql-18 \
    timescaledb-tools \
    timescaledb-toolkit-postgresql-18
# give timescaledb-tune 50% of total ram in MB
# we need to leave the rest for redis and the webserver.
# We cant use $RAM_SIZE or $var_ram here, which is annoying.
total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
ram_for_tsdb=$((total_ram_kb / 1024 / 2))
$STD timescaledb-tune -yes -memory "$ram_for_tsdb"MB
$STD systemctl restart postgresql
msg_ok "Installed TimescaleDB"

msg_info "Creating PostgreSQL Database"
DB_NAME=tracearr
DB_USER=tracearr
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
$STD sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;"
$STD sudo -u postgres psql -d $DB_NAME -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
$STD sudo -u postgres psql -d $DB_NAME -c "GRANT ALL ON SCHEMA public TO $DB_USER;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
{
  echo "Dispatcharr Credentials"
  echo "Database Name: $DB_NAME"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
  echo ""
} >>~/tracearr.creds
msg_ok "Created PostgreSQL Database"

fetch_and_deploy_gh_release "tracearr" "connorgallopo/Tracearr" "tarball" "latest" "/opt/tracearr.build"

msg_info "Building Tracearr"
export TZ=$(cat /etc/timezone)
cd /opt/tracearr.build
$STD pnpm install --frozen-lockfile --force
$STD pnpm turbo telemetry disable
$STD pnpm turbo run build --no-daemon --filter=@tracearr/shared --filter=@tracearr/server --filter=@tracearr/web
mkdir -p /opt/tracearr/{packages/shared,apps/server,apps/web,apps/server/src/db}
cp -rf package.json /opt/tracearr/
cp -rf pnpm-workspace.yaml /opt/tracearr/
cp -rf pnpm-lock.yaml /opt/tracearr/
cp -rf apps/server/package.json /opt/tracearr/apps/server/
cp -rf apps/server/dist /opt/tracearr/apps/server/dist
cp -rf apps/web/dist /opt/tracearr/apps/web/dist
cp -rf packages/shared/package.json /opt/tracearr/packages/shared/
cp -rf packages/shared/dist /opt/tracearr/packages/shared/dist
cp -rf apps/server/src/db/migrations /opt/tracearr/apps/server/src/db/migrations
cp -rf data /opt/tracearr/data
rm -rf /opt/tracearr.build
cd /opt/tracearr
$STD pnpm install --prod --frozen-lockfile
msg_ok "Built Tracearr"

msg_info "Configuring Tracearr"
$STD useradd -r -s /bin/false -U tracearr
$STD chown -R tracearr:tracearr /opt/tracearr
install -d -m 750 -o tracearr -g tracearr /data/tracearr
if [ -f /data/tracearr/.jwt_secret ]; then
  export JWT_SECRET=$(cat /data/tracearr/.jwt_secret)
else
  export JWT_SECRET=$(openssl rand -hex 32)
  echo "$JWT_SECRET" > /data/tracearr/.jwt_secret
  chmod 600 /data/tracearr/.jwt_secret
fi

if [ -f /data/tracearr/.cookie_secret ]; then
  export COOKIE_SECRET=$(cat /data/tracearr/.cookie_secret)
else
  export COOKIE_SECRET=$(openssl rand -hex 32)
  echo "$COOKIE_SECRET" > /data/tracearr/.cookie_secret
  chmod 600 /data/tracearr/.cookie_secret
fi
cat <<EOF >/data/tracearr/.env
DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@127.0.0.1:5432/${DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
PORT=3000
HOST=0.0.0.0
NODE_ENV=production
TZ=${TZ}
LOG_LEVEL=info
JWT_SECRET=$JWT_SECRET
COOKIE_SECRET=$COOKIE_SECRET
APP_VERSION=$(cat /root/.tracearr)
#CORS_ORIGIN=http://localhost:5173
#MOBILE_BETA_MODE=true
EOF
chmod 600 /data/tracearr/.env
chown -R tracearr:tracearr /data/tracearr
msg_ok "Configured Tracearr"

msg_info "Creating Services"
cat <<EOF >/data/tracearr/prestart.sh
#!/usr/bin/env bash
# =============================================================================
# Tune PostgreSQL for available resources (runs every startup)
# =============================================================================
# timescaledb-tune automatically optimizes PostgreSQL settings based on
# available RAM and CPU. Safe to run repeatedly - recalculates if resources change.
if command -v timescaledb-tune &> /dev/null; then
    total_ram_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    ram_for_tsdb=\$((total_ram_kb / 1024 / 2))
    timescaledb-tune -yes -memory "\$ram_for_tsdb"MB --quiet 2>/dev/null \
        || echo "Warning: timescaledb-tune failed (non-fatal)"
fi
# =============================================================================
# Ensure TimescaleDB decompression limit is set (for existing databases)
# =============================================================================
# This setting allows migrations to modify compressed hypertable data.
# Without it, bulk UPDATEs on compressed sessions will fail with
# "tuple decompression limit exceeded" errors.
pg_config_file="/etc/postgresql/18/main/postgresql.conf"
if [ -f \$pg_config_file ]; then
    if ! grep -q "max_tuples_decompressed_per_dml_transaction" \$pg_config_file; then
        echo "" >> \$pg_config_file
        echo "# Allow unlimited tuple decompression for migrations on compressed hypertables" >> \$pg_config_file
        echo "timescaledb.max_tuples_decompressed_per_dml_transaction = 0" >> \$pg_config_file
    fi
fi
systemctl restart postgresql
EOF
chmod +x /data/tracearr/prestart.sh
cat <<EOF >/lib/systemd/system/tracearr.service
[Unit]
Description=Tracearr Web Server
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
KillMode=control-group
EnvironmentFile=/data/tracearr/.env
WorkingDirectory=/opt/tracearr
ExecStartPre=+/data/tracearr/prestart.sh
ExecStart=node /opt/tracearr/apps/server/dist/index.js
Restart=on-failure
RestartSec=10
User=tracearr

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now postgresql
systemctl enable -q --now redis-server
systemctl enable -q --now tracearr
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc

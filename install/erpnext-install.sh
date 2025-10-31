#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: JamesonRGrieve
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/frappe/erpnext

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors

if [[ -z "${ERPNEXT_PARENT_INITIALIZED:-}" ]]; then
    setting_up_container
    network_check
    update_os
fi

msg_info "Installing Dependencies"
$STD apt install -y \
    git \
    nginx \
    gettext-base \
    libpango-1.0-0 \
    libharfbuzz0b \
    libpangoft2-1.0-0 \
    libpangocairo-1.0-0 \
    restic \
    gpg \
    libpq-dev \
    wait-for-it \
    media-types \
    wget \
    libffi-dev \
    liblcms2-dev \
    libldap2-dev \
    libmariadb-dev \
    libsasl2-dev \
    libtiff5-dev \
    libwebp-dev \
    pkg-config \
    redis-tools \
    rlwrap \
    tk8.6-dev \
    cron \
    build-essential \
    libbz2-dev \
    supervisor \
    redis-server \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv
msg_ok "Installed prerequisites"

# Configure Redis to listen on 127.0.0.1
sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf

systemctl enable -q --now redis-server

# Wait for Redis to be ready
for i in {1..30}; do
    if redis-cli ping >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Verify Redis is actually listening
if ! ss -tlnp | grep -q ':6379'; then
    msg_error "Redis is running but not listening on port 6379"
    ss -tlnp | grep redis || true
    cat /etc/redis/redis.conf | grep -E '^(bind|port)' || true
    exit 1
fi

msg_ok "Redis server ready"

setup_mariadb
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c20)}"
export DB_ROOT_PASSWORD

for i in {1..30}; do
    if mariadb-admin ping >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

set +e
if mariadb -uroot -e "SELECT 1" >/dev/null 2>&1; then
    mariadb -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL
else
    if sudo mariadb -e "SELECT 1" >/dev/null 2>&1; then
        sudo mariadb <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL
    else
        msg_warn "Could not set MariaDB root password automatically. You may need to run it manually."
    fi
fi
set -e
fetch_and_deploy_gh_release "wkhtmltopdf" "wkhtmltopdf/packaging"

NODE_VERSION="20" NODE_MODULE="yarn" setup_nodejs


msg_info "Preparing frappe user"
if ! id -u frappe >/dev/null 2>&1; then
    useradd -m -s /bin/bash frappe
fi
usermod -aG sudo frappe
echo "frappe ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/frappe
chmod 0440 /etc/sudoers.d/frappe
msg_ok "Prepared frappe user"

msg_info "Bootstrapping frappe bench"



sudo -u frappe -H bash -c '
set -Eeuo pipefail
pip install --user frappe-bench
export PATH="$HOME/.local/bin:$PATH"

bench init --frappe-branch=version-15 \
  --frappe-path=https://github.com/frappe/frappe \
  --no-procfile --no-backups --skip-redis-config-generation \
  "$HOME/bench"

cd "$HOME/bench"

bench set-config -g redis_cache    "redis://127.0.0.1:6379/0"
bench set-config -g redis_queue    "redis://127.0.0.1:6379/1"
bench set-config -g redis_socketio "redis://127.0.0.1:6379/0"

bench get-app --branch=version-15 --resolve-deps erpnext https://github.com/frappe/erpnext

ls -1 apps > sites/apps.txt
'

msg_ok "Bench prepared"

SITE_CONFIG_PATH="/home/frappe/bench/sites/erpnext.local/site_config.json"

msg_info "Configuring ERPNext site"
sudo DB_ROOT_PASSWORD="$DB_ROOT_PASSWORD" -u frappe -H bash -c '
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$PATH"

cd "$HOME/bench"

if [[ ! -f "sites/erpnext.local/site_config.json" ]]; then
    bench new-site erpnext.local \
        --db-name erpnext \
        --db-host localhost \
        --db-port 3306 \
        --mariadb-root-username root \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --admin-password Password123

    bench --site erpnext.local install-app erpnext
    bench --site erpnext.local enable-scheduler
else
    bench --site erpnext.local migrate
fi

bench use erpnext.local
bench build
bench --site erpnext.local clear-cache

# global bench config
bench set-config -g db_host localhost
bench set-config -gp db_port 3306
bench set-config -g  redis_cache    "redis://127.0.0.1:6379/0"
bench set-config -g  redis_queue    "redis://127.0.0.1:6379/1"
bench set-config -g  redis_socketio "redis://127.0.0.1:6379/2"
bench set-config -gp socketio_port 9000
bench set-config -g  default_site erpnext.local
bench set-config -g  serve_default_site true

# per-site config
bench --site erpnext.local set-config enable_scheduler 1
'
msg_ok "Site configured"

# msg_info "Building frontend assets"
# sudo -u frappe -H bash -c "set -Eeuo pipefail
#     cd /home/frappe/bench
#     bench build
# "
# msg_ok "Frontend assets ready"

SITE_DB_PASSWORD=""
if [[ -f "$SITE_CONFIG_PATH" ]]; then
    SITE_DB_PASSWORD=$(jq -r '.db_password // empty' "$SITE_CONFIG_PATH" 2>/dev/null || true)
fi

create_service() {
    local service_name="$1"
    local service_content="$2"
    printf '%s' "$service_content" >/etc/systemd/system/"${service_name}".service
}

msg_info "Creating systemd units"

create_service "erpnext-backend" "[Unit]
Description=ERPNext Backend (Gunicorn)
After=network.target

[Service]
Type=simple
User=frappe
Group=frappe
WorkingDirectory=/home/frappe/bench
Environment=PATH=/home/frappe/bench/env/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/frappe/bench/env/bin/gunicorn --chdir=/home/frappe/bench/sites --bind=0.0.0.0:8000 --threads=4 --workers=2 --worker-class=gthread --worker-tmp-dir=/dev/shm --timeout=120 --preload frappe.app:application
Restart=on-failure

[Install]
WantedBy=multi-user.target
"

create_service "erpnext-frontend" "[Unit]
Description=ERPNext Frontend (nginx)
After=network.target

[Service]
Type=notify
User=root
Group=root
ExecStart=/usr/sbin/nginx -g 'daemon off;'
ExecReload=/usr/sbin/nginx -s reload
KillSignal=QUIT
Restart=always

[Install]
WantedBy=multi-user.target
"

create_service "erpnext-scheduler" "[Unit]
Description=ERPNext Scheduler
After=network.target

[Service]
Type=simple
User=frappe
Group=frappe
WorkingDirectory=/home/frappe/bench
ExecStart=/usr/local/bin/bench schedule
Restart=always

[Install]
WantedBy=multi-user.target
"

create_service "erpnext-websocket" "[Unit]
Description=ERPNext Websocket
After=network.target

[Service]
Type=simple
User=frappe
Group=frappe
WorkingDirectory=/home/frappe/bench
Environment=NODE_ENV=production
Environment=PORT=9000
Environment=SOCKETIO_PORT=9000
ExecStart=/usr/bin/node /home/frappe/bench/apps/frappe/socketio.js
Restart=always

[Install]
WantedBy=multi-user.target
"

create_service "erpnext-worker" "[Unit]
Description=ERPNext Worker (long,default,short)
After=network.target

[Service]
Type=simple
User=frappe
Group=frappe
WorkingDirectory=/home/frappe/bench
ExecStart=/usr/local/bin/bench worker --queue long,default,short
Restart=always

[Install]
WantedBy=multi-user.target
"

msg_ok "Systemd units created"

msg_info "Configuring nginx"
mkdir -p /etc/nginx/conf.d
cat >/etc/nginx/conf.d/erpnext.conf <<EOF_NGINX
upstream erpnext_backend {
    server 127.0.0.1:8000;
}

upstream erpnext_socketio {
    server 127.0.0.1:9000;
}

server {
    listen 80 default_server;
    server_name _;

    access_log /var/log/nginx/erpnext.access.log;
    error_log /var/log/nginx/erpnext.error.log;

    root /home/frappe/bench/sites;

    set_real_ip_from 127.0.0.1;
    real_ip_header X-Forwarded-For;
    real_ip_recursive off;

    client_max_body_size 50m;

    location /assets {
        try_files \$uri =404;
    }

    location /socket.io {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header Origin \$scheme://\$http_host;
        proxy_read_timeout 120;
        proxy_pass http://erpnext_socketio/socket.io;
    }

    location / {
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Frappe-Site-Name \$host;
        proxy_read_timeout 120;
        proxy_pass http://erpnext_backend;
    }
}
EOF_NGINX

    # Create actual log files instead of symlinks (LXC containers don't support /dev/stdout symlinks)
    touch /var/log/nginx/erpnext.access.log
    touch /var/log/nginx/erpnext.error.log
    rm -f /etc/nginx/sites-enabled/default
    systemctl disable -q --now nginx >/dev/null 2>&1 || true
    msg_ok "nginx configured"


chown -R frappe:frappe /home/frappe
msg_ok "Ownership of frappe home set"

msg_info "Enabling services"
systemctl daemon-reload
if ! systemctl enable -q --now erpnext-backend erpnext-frontend erpnext-scheduler erpnext-websocket erpnext-worker; then
    msg_error "Failed to enable services. Checking logs..."
    for svc in erpnext-backend erpnext-frontend erpnext-scheduler erpnext-websocket erpnext-worker; do
        echo "=== Status for $svc ==="
        systemctl status $svc --no-pager || true
        echo "=== Journal for $svc ==="
        journalctl -u $svc -n 50 --no-pager || true
        echo ""
    done
    exit 1
fi
msg_ok "Services enabled"

msg_info "Storing administrator credentials"
{
    echo "ERPNext Administrator"
    echo "Site: erpnext.local
    echo "Password: Password123
    if [[ -n "$SITE_DB_PASSWORD" ]]; then
        echo "Database Password: ${SITE_DB_PASSWORD}"
    fi
} >~/erpnext-admin.creds
chmod 600 ~/erpnext-admin.creds
msg_ok "Administrator credentials stored in ~/erpnext-admin.creds"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
$STD apt -y clean
msg_ok "Cleaned"

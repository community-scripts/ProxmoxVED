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
    apache2 \
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
bench enable-scheduler
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
bench enable-scheduler
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
Description=ERPNext Frontend (Apache)
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStartPre=/usr/sbin/apache2ctl configtest
ExecStart=/usr/sbin/apache2ctl -D FOREGROUND
ExecReload=/usr/sbin/apache2ctl graceful
KillSignal=SIGTERM
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
Environment=PATH=/home/frappe/bench/env/bin:/home/frappe/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/frappe/.local/bin/bench schedule
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
Environment=PATH=/home/frappe/bench/env/bin:/home/frappe/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/frappe/.local/bin/bench worker --queue long,default,short
Restart=always

[Install]
WantedBy=multi-user.target
"

msg_ok "Systemd units created"

msg_info "Configuring Apache"

# Enable required Apache modules
a2enmod proxy proxy_http proxy_wstunnel headers rewrite remoteip

# Disable the default site
a2dissite 000-default

# Create Apache configuration for ERPNext
cat >/etc/apache2/sites-available/erpnext.conf <<EOF_APACHE
<VirtualHost *:80>
    ServerName _

    ErrorLog /var/log/apache2/erpnext.error.log
    CustomLog /var/log/apache2/erpnext.access.log combined

    DocumentRoot /home/frappe/bench/sites

    # Set real IP from proxy
    RemoteIPHeader X-Forwarded-For
    RemoteIPInternalProxy 127.0.0.1

    # Client max body size (50MB)
    LimitRequestBody 52428800

    # Proxy settings
    ProxyRequests Off
    ProxyPreserveHost On
    ProxyTimeout 120

    # Static assets
    <Directory /home/frappe/bench/sites>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Directory /home/frappe/bench/sites/assets>
        Options +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    ProxyPass /assets !

    # Expose site public files (e.g. attachments)
    Alias /files /home/frappe/bench/sites/erpnext.local/public/files
    <Directory /home/frappe/bench/sites/erpnext.local/public/files>
        Options +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    ProxyPass /files !

    # WebSocket proxy for socket.io
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/socket.io/(.*) ws://127.0.0.1:9000/socket.io/\$1 [P,L]

    # Regular socket.io proxy (non-websocket)
    ProxyPass /socket.io http://127.0.0.1:9000/socket.io
    ProxyPassReverse /socket.io http://127.0.0.1:9000/socket.io

    # Backend proxy
    ProxyPass / http://127.0.0.1:8000/
    ProxyPassReverse / http://127.0.0.1:8000/

    # Additional headers for proxy
    RequestHeader set X-Frappe-Site-Name erpnext.local
    RequestHeader set X-Forwarded-Proto "http"
    RequestHeader set X-Forwarded-For %{REMOTE_ADDR}s
</VirtualHost>
EOF_APACHE

    # Enable the ERPNext site
    a2ensite erpnext

    # Create actual log files instead of symlinks (LXC containers don't support /dev/stdout symlinks)
    touch /var/log/apache2/erpnext.access.log
    touch /var/log/apache2/erpnext.error.log

    # Disable the default Apache service as we'll use our custom systemd service
    systemctl disable -q --now apache2 >/dev/null 2>&1 || true

    # Ensure Apache is completely stopped before starting our custom service
    systemctl stop apache2 >/dev/null 2>&1 || true
    systemctl disable apache2 >/dev/null 2>&1 || true
    pkill -9 apache2 >/dev/null 2>&1 || true
    sleep 2

    msg_ok "Apache configured"


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
    echo "Site: erpnext.local"
    echo "Password: Password123"
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

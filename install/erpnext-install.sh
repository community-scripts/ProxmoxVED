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

export DEBIAN_FRONTEND=noninteractive

ROLE="${ERPNEXT_ROLE:-combined}"
FRAPPE_BRANCH="${ERPNEXT_FRAPPE_BRANCH:-version-15}"
FRAPPE_REPO="${ERPNEXT_FRAPPE_REPO:-https://github.com/frappe/frappe}"
ERPNEXT_BRANCH="${ERPNEXT_APP_BRANCH:-version-15}"
ERPNEXT_REPO="${ERPNEXT_APP_REPO:-https://github.com/frappe/erpnext}"
ENABLE_INTERNAL_REDIS="${ERPNEXT_ENABLE_INTERNAL_REDIS:-yes}"
SITE_NAME_DEFAULT="${ERPNEXT_SITE_NAME:-erpnext.local}"
DB_NAME_DEFAULT="${ERPNEXT_DB_NAME:-erpnext}"
DB_HOST_DEFAULT="${ERPNEXT_DB_HOST:-}"
DB_PORT_DEFAULT="${ERPNEXT_DB_PORT:-3306}"
DB_ROOT_USER_DEFAULT="${ERPNEXT_DB_ROOT_USER:-root}"
DB_ROOT_PASS_DEFAULT="${ERPNEXT_DB_ROOT_PASSWORD:-}"
REDIS_CACHE_DEFAULT="${ERPNEXT_REDIS_CACHE:-redis://127.0.0.1:6379/0}"
REDIS_QUEUE_DEFAULT="${ERPNEXT_REDIS_QUEUE:-redis://127.0.0.1:6379/1}"
REDIS_SOCKETIO_DEFAULT="${ERPNEXT_REDIS_SOCKETIO:-redis://127.0.0.1:6379/2}"
SOCKETIO_PORT_DEFAULT="${ERPNEXT_SOCKETIO_PORT:-9000}"
SOCKETIO_FRONTEND_PORT_DEFAULT="${ERPNEXT_SOCKETIO_FRONTEND_PORT:-${SOCKETIO_PORT_DEFAULT}}"
BACKEND_HOST_DEFAULT="${ERPNEXT_BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT_DEFAULT="${ERPNEXT_BACKEND_PORT:-8000}"
SOCKETIO_HOST_DEFAULT="${ERPNEXT_SOCKETIO_HOST:-127.0.0.1}"
FRAPPE_SITE_HEADER_DEFAULT="${ERPNEXT_SITE_NAME_HEADER:-\$host}"
UPSTREAM_REAL_IP_DEFAULT="${ERPNEXT_UPSTREAM_REAL_IP_ADDRESS:-127.0.0.1}"
UPSTREAM_REAL_IP_HEADER_DEFAULT="${ERPNEXT_UPSTREAM_REAL_IP_HEADER:-X-Forwarded-For}"
UPSTREAM_REAL_IP_RECURSIVE_DEFAULT="${ERPNEXT_UPSTREAM_REAL_IP_RECURSIVE:-off}"
PROXY_READ_TIMEOUT_DEFAULT="${ERPNEXT_PROXY_READ_TIMEOUT:-120}"
CLIENT_MAX_BODY_SIZE_DEFAULT="${ERPNEXT_CLIENT_MAX_BODY_SIZE:-50m}"
ADMIN_EMAIL_DEFAULT="${ERPNEXT_ADMIN_EMAIL:-administrator@example.com}"
ADMIN_PASS_DEFAULT="${ERPNEXT_ADMIN_PASSWORD:-}"

if [[ ! "$ROLE" =~ ^(combined|backend|frontend|scheduler|websocket|worker)$ ]]; then
    msg_error "Unsupported ERPNext role: ${ROLE}"
    exit 1
fi

prompt_or_default() {
    local __var_name="$1"
    local __prompt="$2"
    local __default="$3"
    local __silent="${4:-0}"
    local __value="${!__var_name}"

    if [[ -z "$__value" ]]; then
        __value="$__default"
    fi

    if [[ -t 0 ]]; then
        if [[ "$__silent" -eq 1 ]]; then
            read -rsp "$__prompt" __input </dev/tty || true
            echo
        else
            read -rp "$__prompt" __input </dev/tty || true
        fi
        if [[ -n "$__input" ]]; then
            __value="$__input"
        fi
    fi

    printf -v "$__var_name" '%s' "$__value"
}

if [[ -z "$ADMIN_PASS_DEFAULT" ]]; then
    ADMIN_PASS_DEFAULT=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c18)
fi

SITE_NAME="$SITE_NAME_DEFAULT"
DB_NAME="$DB_NAME_DEFAULT"
DB_HOST="$DB_HOST_DEFAULT"
DB_PORT="$DB_PORT_DEFAULT"
DB_ROOT_USER="$DB_ROOT_USER_DEFAULT"
DB_ROOT_PASSWORD="$DB_ROOT_PASS_DEFAULT"
REDIS_CACHE_URL="$REDIS_CACHE_DEFAULT"
REDIS_QUEUE_URL="$REDIS_QUEUE_DEFAULT"
REDIS_SOCKETIO_URL="$REDIS_SOCKETIO_DEFAULT"
SOCKETIO_PORT="$SOCKETIO_PORT_DEFAULT"
SOCKETIO_PUBLIC_PORT="$SOCKETIO_FRONTEND_PORT_DEFAULT"
BACKEND_HOST="$BACKEND_HOST_DEFAULT"
BACKEND_PORT="$BACKEND_PORT_DEFAULT"
SOCKETIO_HOST="$SOCKETIO_HOST_DEFAULT"
FRAPPE_SITE_NAME_HEADER="$FRAPPE_SITE_HEADER_DEFAULT"
UPSTREAM_REAL_IP_ADDRESS="$UPSTREAM_REAL_IP_DEFAULT"
UPSTREAM_REAL_IP_HEADER="$UPSTREAM_REAL_IP_HEADER_DEFAULT"
UPSTREAM_REAL_IP_RECURSIVE="$UPSTREAM_REAL_IP_RECURSIVE_DEFAULT"
PROXY_READ_TIMEOUT="$PROXY_READ_TIMEOUT_DEFAULT"
CLIENT_MAX_BODY_SIZE="$CLIENT_MAX_BODY_SIZE_DEFAULT"
ADMIN_EMAIL="$ADMIN_EMAIL_DEFAULT"
ADMIN_PASSWORD="$ADMIN_PASS_DEFAULT"

prompt_or_default SITE_NAME "Site name [${SITE_NAME}]: " "$SITE_NAME"
prompt_or_default DB_NAME "Database name [${DB_NAME}]: " "$DB_NAME"
prompt_or_default DB_HOST "MariaDB host (required): " "$DB_HOST"
prompt_or_default DB_PORT "MariaDB port [${DB_PORT}]: " "$DB_PORT"
prompt_or_default DB_ROOT_USER "MariaDB admin user [${DB_ROOT_USER}]: " "$DB_ROOT_USER"
prompt_or_default DB_ROOT_PASSWORD "MariaDB admin password (leave blank for none): " "$DB_ROOT_PASSWORD" 1
prompt_or_default REDIS_CACHE_URL "Redis cache URL [${REDIS_CACHE_URL}]: " "$REDIS_CACHE_URL"
prompt_or_default REDIS_QUEUE_URL "Redis queue URL [${REDIS_QUEUE_URL}]: " "$REDIS_QUEUE_URL"
prompt_or_default REDIS_SOCKETIO_URL "Redis socketio URL [${REDIS_SOCKETIO_URL}]: " "$REDIS_SOCKETIO_URL"
prompt_or_default SOCKETIO_PORT "Socket.IO port [${SOCKETIO_PORT}]: " "$SOCKETIO_PORT"
prompt_or_default ADMIN_PASSWORD "Administrator password [hidden]: " "$ADMIN_PASSWORD" 1

if [[ "$ROLE" == "frontend" ]]; then
    prompt_or_default BACKEND_HOST "Backend host [${BACKEND_HOST}]: " "$BACKEND_HOST"
    prompt_or_default BACKEND_PORT "Backend port [${BACKEND_PORT}]: " "$BACKEND_PORT"
    prompt_or_default SOCKETIO_HOST "Socket.IO host [${SOCKETIO_HOST}]: " "$SOCKETIO_HOST"
    prompt_or_default SOCKETIO_PUBLIC_PORT "Socket.IO port for frontend [${SOCKETIO_PUBLIC_PORT}]: " "$SOCKETIO_PUBLIC_PORT"
    prompt_or_default FRAPPE_SITE_NAME_HEADER "Frappe site header [${FRAPPE_SITE_NAME_HEADER}]: " "$FRAPPE_SITE_NAME_HEADER"
    prompt_or_default UPSTREAM_REAL_IP_ADDRESS "Upstream real IP address [${UPSTREAM_REAL_IP_ADDRESS}]: " "$UPSTREAM_REAL_IP_ADDRESS"
    prompt_or_default UPSTREAM_REAL_IP_HEADER "Upstream real IP header [${UPSTREAM_REAL_IP_HEADER}]: " "$UPSTREAM_REAL_IP_HEADER"
    prompt_or_default UPSTREAM_REAL_IP_RECURSIVE "Upstream real IP recursive [${UPSTREAM_REAL_IP_RECURSIVE}]: " "$UPSTREAM_REAL_IP_RECURSIVE"
    prompt_or_default PROXY_READ_TIMEOUT "Proxy read timeout [${PROXY_READ_TIMEOUT}]: " "$PROXY_READ_TIMEOUT"
    prompt_or_default CLIENT_MAX_BODY_SIZE "Client max body size [${CLIENT_MAX_BODY_SIZE}]: " "$CLIENT_MAX_BODY_SIZE"
else
    SOCKETIO_PUBLIC_PORT="$SOCKETIO_PORT"
    BACKEND_HOST="127.0.0.1"
    BACKEND_PORT="8000"
    SOCKETIO_HOST="127.0.0.1"
    FRAPPE_SITE_NAME_HEADER="\$host"
    UPSTREAM_REAL_IP_ADDRESS="127.0.0.1"
    UPSTREAM_REAL_IP_HEADER="X-Forwarded-For"
    UPSTREAM_REAL_IP_RECURSIVE="off"
    PROXY_READ_TIMEOUT="120"
    CLIENT_MAX_BODY_SIZE="50m"
fi

if [[ -z "$DB_HOST" ]]; then
    msg_error "MariaDB host is required for ERPNext installation."
    exit 1
fi

msg_info "Installing Dependencies"
$STD apt-get install -y \
    curl \
    git \
    vim \
    nginx \
    gettext-base \
    file \
    libpango-1.0-0 \
    libharfbuzz0b \
    libpangoft2-1.0-0 \
    libpangocairo-1.0-0 \
    restic \
    gpg \
    mariadb-client \
    less \
    libpq-dev \
    postgresql-client \
    wait-for-it \
    jq \
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
    gcc \
    build-essential \
    libbz2-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    sudo \
    supervisor \
    locales
msg_ok "Installed prerequisites"

if [[ "$ENABLE_INTERNAL_REDIS" == "yes" ]]; then
    msg_info "Installing Redis server"
    $STD apt-get install -y redis-server

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

    if ! redis-cli ping >/dev/null 2>&1; then
        msg_error "Redis failed to start properly"
        systemctl status redis-server
        journalctl -u redis-server -n 50 --no-pager
        ss -tlnp | grep 6379 || true
        exit 1
    fi

    # Verify Redis is actually listening
    if ! ss -tlnp | grep -q ':6379'; then
        msg_error "Redis is running but not listening on port 6379"
        ss -tlnp | grep redis || true
        cat /etc/redis/redis.conf | grep -E '^(bind|port)' || true
        exit 1
    fi

    msg_ok "Redis server ready"
fi

msg_info "Installing wkhtmltopdf"
WKHTML_VERSION="0.12.6.1-3"
WKHTML_DISTRO="bookworm"
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64)
        ;;
    *)
        msg_error "Unsupported architecture for wkhtmltopdf: ${ARCH}"
        exit 1
        ;;
esac
WKHTML_DEB="wkhtmltox_${WKHTML_VERSION}.${WKHTML_DISTRO}_${ARCH}.deb"
cd /tmp || exit
curl -fsSLO "https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTML_VERSION}/${WKHTML_DEB}"
$STD apt-get install -y "./${WKHTML_DEB}"
rm -f "${WKHTML_DEB}"
msg_ok "Installed wkhtmltopdf"

msg_info "Configuring Node.js environment"
NODE_VERSION="20" NODE_MODULE="yarn" setup_nodejs
msg_ok "Node.js ready"

msg_info "Installing Bench"
$STD pip3 install frappe-bench
msg_ok "Installed Bench"

msg_info "Preparing frappe user"
if ! id -u frappe >/dev/null 2>&1; then
    useradd -m -s /bin/bash frappe
fi
usermod -aG sudo frappe
echo "frappe ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/frappe
chmod 0440 /etc/sudoers.d/frappe
msg_ok "Prepared frappe user"

install_bench_stack() {
    sudo -u frappe -H bash -c "set -Eeuo pipefail
        if [[ ! -d /home/frappe/frappe-bench ]]; then
            bench init --frappe-branch=${FRAPPE_BRANCH} --frappe-path=${FRAPPE_REPO} --no-procfile --no-backups --skip-redis-config-generation /home/frappe/frappe-bench
        fi
        cd /home/frappe/frappe-bench

        # Configure Redis URLs immediately after bench init
        bench set-config -g redis_cache '${REDIS_CACHE_URL}'
        bench set-config -g redis_queue '${REDIS_QUEUE_URL}'
        bench set-config -g redis_socketio '${REDIS_SOCKETIO_URL}'

        # Check Redis status before testing connectivity
        echo 'Checking Redis status...'
        systemctl is-active redis-server || (echo 'Redis is not active, restarting...' && sudo systemctl restart redis-server && sleep 2)
        redis-cli ping || (echo 'Redis ping failed' && sudo systemctl status redis-server && sudo ss -tlnp | grep 6379 && exit 1)

        # Verify Redis connectivity using bench's python
        echo 'Testing Redis connectivity from bench...'
        ./env/bin/python3 -c \"
import redis
try:
    r = redis.from_url('${REDIS_CACHE_URL}')
    r.ping()
    print('✓ Redis cache connection successful')
except Exception as e:
    print(f'✗ Redis connection failed: {e}')
    exit(1)
\"

        if [[ ! -d apps/erpnext ]]; then
            bench get-app --branch=${ERPNEXT_BRANCH} --resolve-deps erpnext ${ERPNEXT_REPO}
        fi
        if [[ ! -f sites/apps.txt ]] || ! grep -qx 'erpnext' sites/apps.txt; then
            ls -1 apps >sites/apps.txt
        fi
    "
}

msg_info "Bootstrapping frappe bench"
install_bench_stack
msg_ok "Bench prepared"

apply_bench_globals() {
    sudo -u frappe -H bash -c "set -Eeuo pipefail
        cd /home/frappe/frappe-bench
        bench set-config -g db_host '${DB_HOST}'
        bench set-config -gp db_port '${DB_PORT}'
        bench set-config -g redis_cache '${REDIS_CACHE_URL}'
        bench set-config -g redis_queue '${REDIS_QUEUE_URL}'
        bench set-config -g redis_socketio '${REDIS_SOCKETIO_URL}'
        bench set-config -gp socketio_port '${SOCKETIO_PORT}'
        bench set-config -g default_site '${SITE_NAME}'
        bench set-config -g serve_default_site "true"
        bench --site '${SITE_NAME}' set-config enable_scheduler 1
    "
}

configure_site_data() {
    sudo -u frappe -H bash -c "set -Eeuo pipefail
        cd /home/frappe/frappe-bench
        if [[ ! -f sites/${SITE_NAME}/site_config.json ]]; then
            bench new-site '${SITE_NAME}' \
                --db-name '${DB_NAME}' \
                --db-host '${DB_HOST}' \
                --db-port '${DB_PORT}' \
                --mariadb-root-username '${DB_ROOT_USER}' \
                --mariadb-root-password '${DB_ROOT_PASSWORD}' \
                --admin-password '${ADMIN_PASSWORD}'
            bench --site '${SITE_NAME}' install-app erpnext
            bench --site '${SITE_NAME}' enable-scheduler
        else
            bench --site '${SITE_NAME}' migrate
        fi
        bench use '${SITE_NAME}'
        bench build
        bench --site '${SITE_NAME}' clear-cache
    "
}

SITE_CONFIG_PATH="/home/frappe/frappe-bench/sites/${SITE_NAME}/site_config.json"

if [[ "$ROLE" == "combined" || "$ROLE" == "backend" ]]; then
    msg_info "Configuring ERPNext site"
    configure_site_data
    msg_ok "Site configured"
else
    if [[ ! -f "$SITE_CONFIG_PATH" ]]; then
        msg_error "Site configuration not found at ${SITE_CONFIG_PATH}. Copy the 'sites' directory from your backend or combined container (or mount shared storage) before installing the ${ROLE} role."
        exit 1
    fi
    msg_info "Running database migrations for ${SITE_NAME}"
    sudo -u frappe -H bash -c "set -Eeuo pipefail
        cd /home/frappe/frappe-bench
        bench --site '${SITE_NAME}' migrate
        bench use '${SITE_NAME}'
    "
    msg_ok "Migrations complete"
fi

apply_bench_globals

if [[ "$ROLE" == "frontend" ]]; then
    msg_info "Building frontend assets"
    sudo -u frappe -H bash -c "set -Eeuo pipefail
        cd /home/frappe/frappe-bench
        bench build
    "
    msg_ok "Frontend assets ready"
fi

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
case "$ROLE" in
    combined|backend)
        create_service "erpnext-backend" "[Unit]
Description=ERPNext Backend (Gunicorn)
After=network.target

[Service]
Type=simple
User=frappe
Group=frappe
WorkingDirectory=/home/frappe/frappe-bench
Environment=PATH=/home/frappe/frappe-bench/env/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/frappe/frappe-bench/env/bin/gunicorn --chdir=/home/frappe/frappe-bench/sites --bind=0.0.0.0:8000 --threads=4 --workers=2 --worker-class=gthread --worker-tmp-dir=/dev/shm --timeout=120 --preload frappe.app:application
Restart=on-failure

[Install]
WantedBy=multi-user.target
"
        ;;&
    combined|frontend)
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
        ;;&
    combined|scheduler)
        create_service "erpnext-scheduler" "[Unit]
Description=ERPNext Scheduler
After=network.target

[Service]
Type=simple
User=frappe
Group=frappe
WorkingDirectory=/home/frappe/frappe-bench
ExecStart=/usr/local/bin/bench schedule
Restart=always

[Install]
WantedBy=multi-user.target
"
        ;;&
    combined|websocket)
        create_service "erpnext-websocket" "[Unit]
Description=ERPNext Websocket
After=network.target

[Service]
Type=simple
User=frappe
Group=frappe
WorkingDirectory=/home/frappe/frappe-bench
Environment=NODE_ENV=production
Environment=PORT=${SOCKETIO_PORT}
Environment=SOCKETIO_PORT=${SOCKETIO_PORT}
ExecStart=/usr/bin/node /home/frappe/frappe-bench/apps/frappe/socketio.js
Restart=always

[Install]
WantedBy=multi-user.target
"
        ;;&
    combined|worker)
        create_service "erpnext-worker" "[Unit]
Description=ERPNext Worker (long,default,short)
After=network.target

[Service]
Type=simple
User=frappe
Group=frappe
WorkingDirectory=/home/frappe/frappe-bench
ExecStart=/usr/local/bin/bench worker --queue long,default,short
Restart=always

[Install]
WantedBy=multi-user.target
"
        ;;
esac
msg_ok "Systemd units created"

if [[ "$ROLE" == "combined" || "$ROLE" == "frontend" ]]; then
    msg_info "Configuring nginx"
    backend_target="${BACKEND_HOST}:${BACKEND_PORT}"
    socketio_target="${SOCKETIO_HOST}:${SOCKETIO_PUBLIC_PORT}"
    mkdir -p /etc/nginx/conf.d
    cat >/etc/nginx/conf.d/erpnext.conf <<EOF_NGINX
upstream erpnext_backend {
    server ${backend_target};
}

upstream erpnext_socketio {
    server ${socketio_target};
}

server {
    listen 80 default_server;
    server_name _;

    access_log /var/log/nginx/erpnext.access.log;
    error_log /var/log/nginx/erpnext.error.log;

    root /home/frappe/frappe-bench/sites;

    set_real_ip_from ${UPSTREAM_REAL_IP_ADDRESS};
    real_ip_header ${UPSTREAM_REAL_IP_HEADER};
    real_ip_recursive ${UPSTREAM_REAL_IP_RECURSIVE};

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

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
        proxy_read_timeout ${PROXY_READ_TIMEOUT};
        proxy_pass http://erpnext_socketio/socket.io;
    }

    location / {
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Frappe-Site-Name ${FRAPPE_SITE_NAME_HEADER};
        proxy_read_timeout ${PROXY_READ_TIMEOUT};
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
fi

msg_info "Adjusting ownership"
chown -R frappe:frappe /home/frappe
msg_ok "Ownership set"

msg_info "Enabling services"
case "$ROLE" in
    combined)
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
        ;;
    frontend)
        systemctl daemon-reload
        if ! systemctl enable -q --now erpnext-frontend; then
            msg_error "Failed to enable erpnext-frontend"
            systemctl status erpnext-frontend --no-pager
            journalctl -u erpnext-frontend -n 50 --no-pager
            exit 1
        fi
        ;;
    backend)
        systemctl daemon-reload
        if ! systemctl enable -q --now erpnext-backend; then
            msg_error "Failed to enable erpnext-backend"
            systemctl status erpnext-backend --no-pager
            journalctl -u erpnext-backend -n 50 --no-pager
            exit 1
        fi
        ;;
    scheduler)
        systemctl daemon-reload
        if ! systemctl enable -q --now erpnext-scheduler; then
            msg_error "Failed to enable erpnext-scheduler"
            systemctl status erpnext-scheduler --no-pager
            journalctl -u erpnext-scheduler -n 50 --no-pager
            exit 1
        fi
        ;;
    websocket)
        systemctl daemon-reload
        if ! systemctl enable -q --now erpnext-websocket; then
            msg_error "Failed to enable erpnext-websocket"
            systemctl status erpnext-websocket --no-pager
            journalctl -u erpnext-websocket -n 50 --no-pager
            exit 1
        fi
        ;;
    worker)
        systemctl daemon-reload
        if ! systemctl enable -q --now erpnext-worker; then
            msg_error "Failed to enable erpnext-worker"
            systemctl status erpnext-worker --no-pager
            journalctl -u erpnext-worker -n 50 --no-pager
            exit 1
        fi
        ;;
    *)
        systemctl daemon-reload
        ;;
esac
msg_ok "Services enabled"

if [[ "$ROLE" == "combined" || "$ROLE" == "backend" ]]; then
    {
        echo "ERPNext Administrator"
        echo "Site: ${SITE_NAME}"
        echo "Email: ${ADMIN_EMAIL}"
        echo "Password: ${ADMIN_PASSWORD}"
        if [[ -n "$SITE_DB_PASSWORD" ]]; then
            echo "Database Password: ${SITE_DB_PASSWORD}"
        fi
    } >~/erpnext-admin.creds
    chmod 600 ~/erpnext-admin.creds
    msg_info "Administrator credentials stored in ~/erpnext-admin.creds"
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt-get -y clean
msg_ok "Cleaned"

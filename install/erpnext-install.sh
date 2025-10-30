#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: JamesonRGrieve
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/frappe/erpnext

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container

# Source tools.func for additional helper functions like setup_nodejs
source <(curl -fsSL "${BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main}/misc/tools.func")

export DEBIAN_FRONTEND=noninteractive

# Configuration variables with defaults
ROLE="${ERPNEXT_ROLE:-combined}"
FRAPPE_BRANCH="${ERPNEXT_FRAPPE_BRANCH:-version-15}"
FRAPPE_REPO="${ERPNEXT_FRAPPE_REPO:-https://github.com/frappe/frappe}"
ERPNEXT_BRANCH="${ERPNEXT_APP_BRANCH:-version-15}"
ERPNEXT_REPO="${ERPNEXT_APP_REPO:-https://github.com/frappe/erpnext}"
ENABLE_INTERNAL_REDIS="${ERPNEXT_ENABLE_INTERNAL_REDIS:-yes}"
SITE_NAME_DEFAULT="${ERPNEXT_SITE_NAME:-erpnext.local}"
DB_NAME_DEFAULT="${ERPNEXT_DB_NAME:-${SITE_NAME_DEFAULT//./_}}"
DB_HOST_DEFAULT="${ERPNEXT_DB_HOST:-}"
DB_PORT_DEFAULT="${ERPNEXT_DB_PORT:-3306}"
DB_ROOT_USER_DEFAULT="${ERPNEXT_DB_ROOT_USER:-root}"
DB_ROOT_PASS_DEFAULT="${ERPNEXT_DB_ROOT_PASSWORD:-}"
# FIXED: Separate Redis instances for cache, queue, and socketio
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

# Validate role
if [[ ! "$ROLE" =~ ^(combined|backend|frontend|scheduler|websocket|worker)$ ]]; then
    msg_error "Unsupported ERPNext role: ${ROLE}"
    exit 1
fi

# Helper function for prompts
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

# Generate admin password if not provided
if [[ -z "$ADMIN_PASS_DEFAULT" ]]; then
    ADMIN_PASS_DEFAULT=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c18)
fi

# Initialize variables with defaults
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

# Interactive prompts (only if TTY is available)
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
prompt_or_default ADMIN_EMAIL "Administrator email [${ADMIN_EMAIL}]: " "$ADMIN_EMAIL"
prompt_or_default ADMIN_PASSWORD "Administrator password [hidden]: " "$ADMIN_PASSWORD" 1

# Additional prompts for frontend role
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

# Validate required parameters
if [[ -z "$DB_HOST" ]]; then
    msg_error "MariaDB host is required for ERPNext installation."
    exit 1
fi

msg_info "Installing ERPNext prerequisites"
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

# Test database connection and reprompt if necessary
msg_info "Testing MariaDB connection"
test_db_connection() {
    local password_arg=""
    if [[ -n "$DB_ROOT_PASSWORD" ]]; then
        password_arg="-p${DB_ROOT_PASSWORD}"
    fi

    if mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_ROOT_USER}" ${password_arg} -e "SELECT 1;" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

CONNECTION_ATTEMPTS=0
while ! test_db_connection; do
    CONNECTION_ATTEMPTS=$((CONNECTION_ATTEMPTS + 1))

    if [[ $CONNECTION_ATTEMPTS -eq 1 ]]; then
        msg_error "Failed to connect to MariaDB at ${DB_HOST}:${DB_PORT}"
    fi

    echo ""
    echo "Unable to connect to MariaDB. Please verify your connection details:"
    echo "Current settings:"
    echo "  Host: ${DB_HOST}"
    echo "  Port: ${DB_PORT}"
    echo "  User: ${DB_ROOT_USER}"
    echo ""

    # Reprompt for credentials
    prompt_or_default DB_HOST "MariaDB host [${DB_HOST}]: " "$DB_HOST"
    prompt_or_default DB_PORT "MariaDB port [${DB_PORT}]: " "$DB_PORT"
    prompt_or_default DB_ROOT_USER "MariaDB admin user [${DB_ROOT_USER}]: " "$DB_ROOT_USER"
    prompt_or_default DB_ROOT_PASSWORD "MariaDB admin password: " "$DB_ROOT_PASSWORD" 1

    msg_info "Retrying connection (attempt $((CONNECTION_ATTEMPTS + 1)))..."
done

msg_ok "MariaDB connection successful"

if [[ "$ENABLE_INTERNAL_REDIS" == "yes" ]]; then
    msg_info "Installing Redis server"
    $STD apt-get install -y redis-server

    # Configure Redis to support multiple databases
    sed -i 's/^databases .*/databases 16/' /etc/redis/redis.conf

    systemctl enable -q --now redis-server
    msg_ok "Redis server ready (configured for multiple databases)"
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
$STD pip3 install frappe-bench --break-system-packages
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
        if [[ ! -d apps/erpnext ]]; then
            bench get-app --branch=${ERPNEXT_BRANCH} --resolve-deps erpnext ${ERPNEXT_REPO}
        fi
    "
}

apply_bench_globals() {
    sudo -u frappe -H bash -c "set -Eeuo pipefail
        cd /home/frappe/frappe-bench
        bench set-config -g db_host '${DB_HOST}'
        bench set-config -gp db_port ${DB_PORT}
        bench set-config -g redis_cache '${REDIS_CACHE_URL}'
        bench set-config -g redis_queue '${REDIS_QUEUE_URL}'
        bench set-config -g redis_socketio '${REDIS_SOCKETIO_URL}'
        bench set-config -gp socketio_port ${SOCKETIO_PORT}
    "
}

if [[ "$ROLE" == "combined" || "$ROLE" == "backend" ]]; then
    msg_info "Initializing ERPNext bench"
    install_bench_stack
    msg_ok "Bench initialized"

    msg_info "Applying global bench configuration"
    apply_bench_globals
    msg_ok "Configuration applied"

    SITE_CONFIG_PATH="/home/frappe/frappe-bench/sites/${SITE_NAME}/site_config.json"
    if [[ ! -f "$SITE_CONFIG_PATH" ]]; then
        msg_info "Creating new ERPNext site: ${SITE_NAME}"
        DB_ROOT_PASSWORD_FLAG=""
        if [[ -n "$DB_ROOT_PASSWORD" ]]; then
            DB_ROOT_PASSWORD_FLAG="--mariadb-root-password '${DB_ROOT_PASSWORD}'"
        fi
        sudo -u frappe -H bash -c "set -Eeuo pipefail
            cd /home/frappe/frappe-bench
            bench new-site '${SITE_NAME}' \
                --mariadb-root-username '${DB_ROOT_USER}' \
                ${DB_ROOT_PASSWORD_FLAG} \
                --db-name '${DB_NAME}' \
                --admin-password '${ADMIN_PASSWORD}' \
                --install-app erpnext
        " || {
            msg_error "Failed to create site ${SITE_NAME}"
            exit 1
        }
        msg_ok "Site ${SITE_NAME} created"
    else
        msg_info "Site ${SITE_NAME} already exists"
    fi

    if [[ ! -f "$SITE_CONFIG_PATH" ]]; then
        msg_error "Site config not found at ${SITE_CONFIG_PATH}"
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
    printf '%s' "$service_content" >/etc/systemd/system/${service_name}.service
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

    ln -sf /dev/stdout /var/log/nginx/erpnext.access.log
    ln -sf /dev/stderr /var/log/nginx/erpnext.error.log
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
        systemctl enable -q --now erpnext-backend erpnext-frontend erpnext-scheduler erpnext-websocket erpnext-worker
        ;;
    frontend)
        systemctl daemon-reload
        systemctl enable -q --now erpnext-frontend
        ;;
    backend)
        systemctl daemon-reload
        systemctl enable -q --now erpnext-backend
        ;;
    scheduler)
        systemctl daemon-reload
        systemctl enable -q --now erpnext-scheduler
        ;;
    websocket)
        systemctl daemon-reload
        systemctl enable -q --now erpnext-websocket
        ;;
    worker)
        systemctl daemon-reload
        systemctl enable -q --now erpnext-worker
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
        echo ""
        echo "Redis Configuration:"
        echo "  Cache:    ${REDIS_CACHE_URL}"
        echo "  Queue:    ${REDIS_QUEUE_URL}"
        echo "  SocketIO: ${REDIS_SOCKETIO_URL}"
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

#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: JamesonRGrieve
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/goauthentik/authentik

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors

if [[ -z "${AUTHENTIK_PARENT_INITIALIZED:-}" ]]; then
    setting_up_container
    network_check
    update_os
fi

msg_info "Installing Dependencies"
$STD apt-get install -y \
    curl \
    sudo \
    mc \
    git \
    build-essential \
    pkg-config \
    libffi-dev \
    libssl-dev \
    libpq-dev \
    libxslt-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libxmlsec1-openssl \
    zlib1g-dev \
    libjpeg-dev \
    liblcms2-dev \
    libltdl-dev \
    libkrb5-dev \
    libmaxminddb0 \
    ca-certificates \
    gnupg \
    gettext
msg_ok "Installed Dependencies"

# Setup PostgreSQL
setup_postgresql
DB_NAME="authentik"
DB_USER="authentik"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)

msg_info "Configuring PostgreSQL database"
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
msg_ok "Configured PostgreSQL database"

# Setup Node.js (Authentik uses Node 24)
NODE_VERSION="24" setup_nodejs

# Setup Go
msg_info "Installing Go"
GO_VERSION="1.23.4"
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
rm -f /tmp/go.tar.gz
export PATH=$PATH:/usr/local/go/bin
msg_ok "Installed Go ${GO_VERSION}"

# Setup Python with uv
msg_info "Installing Python build dependencies"
$STD apt-get install -y \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv
msg_ok "Installed Python build dependencies"

setup_uv

# Get latest version from HTML (avoids API rate limit)
msg_info "Fetching Authentik version"
RELEASE=$(curl -fsSL https://github.com/goauthentik/authentik/releases/latest 2>&1 | grep -oP 'goauthentik/authentik/releases/tag/\Kversion/[0-9.]+' | head -1)
if [[ -z "$RELEASE" ]]; then
    RELEASE="version/2025.10.2"
    msg_info "Could not determine latest version, using ${RELEASE}"
fi
msg_ok "Using Authentik ${RELEASE}"

msg_info "Cloning Authentik repository"
if [[ -d /opt/authentik/.git ]]; then
    cd /opt/authentik || exit 1
    git fetch --all --tags
    $STD git checkout "${RELEASE}"
else
    rm -rf /opt/authentik
    $STD git clone --depth 1 --branch "${RELEASE}" https://github.com/goauthentik/authentik.git /opt/authentik
fi
msg_ok "Cloned Authentik ${RELEASE}"

msg_info "Creating authentik user"
if ! id -u authentik >/dev/null 2>&1; then
    useradd --system --home-dir /opt/authentik --shell /bin/bash --no-create-home authentik
fi
chown -R authentik:authentik /opt/authentik
msg_ok "Created authentik user"

# Generate secrets
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -dc 'a-zA-Z0-9' | head -c50)

msg_info "Creating environment configuration"
cat >/opt/authentik/.env <<EOF
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
AUTHENTIK_POSTGRESQL__HOST=localhost
AUTHENTIK_POSTGRESQL__PORT=5432
AUTHENTIK_POSTGRESQL__NAME=${DB_NAME}
AUTHENTIK_POSTGRESQL__USER=${DB_USER}
AUTHENTIK_POSTGRESQL__PASSWORD=${DB_PASS}
AUTHENTIK_ERROR_REPORTING__ENABLED=false
AUTHENTIK_LOG_LEVEL=info
AUTHENTIK_DISABLE_UPDATE_CHECK=false
AUTHENTIK_AVATARS=gravatar,initials
EOF
chown authentik:authentik /opt/authentik/.env
chmod 600 /opt/authentik/.env
msg_ok "Created environment configuration"

msg_info "Setting up Go environment"
sudo -u authentik bash -c 'echo "export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin" >> ~/.bashrc'
sudo -u authentik bash -c 'echo "export GOPATH=\$HOME/go" >> ~/.bashrc'
msg_ok "Configured Go environment"

msg_info "Building web components (this takes several minutes)"
cd /opt/authentik/web || exit 1
sudo -u authentik -H bash -c '
set -Eeuo pipefail
cd /opt/authentik/web
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
export HOME="/opt/authentik"
npm install
npm run build
'
msg_ok "Built web components"

msg_info "Setting up Python virtual environment"
cd /opt/authentik || exit 1
sudo -u authentik -H bash -c '
set -Eeuo pipefail
cd /opt/authentik
export HOME="/opt/authentik"
/usr/local/bin/uv venv /opt/authentik/.venv
source /opt/authentik/.venv/bin/activate
/usr/local/bin/uv pip install poetry-core
'
msg_ok "Created Python virtual environment"

msg_info "Installing Python dependencies (this takes several minutes)"
cd /opt/authentik || exit 1
sudo -u authentik -H bash -c '
set -Eeuo pipefail
cd /opt/authentik
export HOME="/opt/authentik"
source /opt/authentik/.venv/bin/activate
/usr/local/bin/uv sync --frozen --no-dev || pip install -e .
'
msg_ok "Installed Python dependencies"

msg_info "Building Go server binary"
cd /opt/authentik || exit 1
sudo -u authentik mkdir -p /opt/authentik/bin
sudo -u authentik -H bash -c '
set -Eeuo pipefail
cd /opt/authentik
export PATH="/usr/local/go/bin:$PATH"
export HOME="/opt/authentik"
export GOPATH="/opt/authentik/go"
CGO_ENABLED=1 go build -o /opt/authentik/bin/authentik ./cmd/server
'
msg_ok "Built Go server binary"

msg_info "Running database migrations"
cd /opt/authentik || exit 1
sudo -u authentik -H bash -c '
set -Eeuo pipefail
cd /opt/authentik
export HOME="/opt/authentik"
source /opt/authentik/.venv/bin/activate
set -a && source /opt/authentik/.env && set +a
python manage.py migrate
'
msg_ok "Database migrations complete"

msg_info "Creating directories"
install -d -m 0750 -o authentik -g authentik /opt/authentik/media
install -d -m 0750 -o authentik -g authentik /opt/authentik/certs
install -d -m 0750 -o authentik -g authentik /opt/authentik/custom-templates
install -d -m 0750 -o authentik -g authentik /var/log/authentik
msg_ok "Created directories"

echo "${RELEASE}" >/opt/authentik_version.txt

create_service() {
    local service_name="$1"
    local service_content="$2"
    printf '%s' "$service_content" >/etc/systemd/system/"${service_name}".service
}

msg_info "Creating systemd services"

create_service "authentik-server" "[Unit]
Description=Authentik Server
After=network.target postgresql.service
Wants=postgresql.service
Documentation=https://goauthentik.io/docs

[Service]
Type=simple
User=authentik
Group=authentik
WorkingDirectory=/opt/authentik
EnvironmentFile=/opt/authentik/.env
Environment=PATH=/opt/authentik/.venv/bin:/opt/authentik/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/opt/authentik/bin/authentik server
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
"

create_service "authentik-worker" "[Unit]
Description=Authentik Background Worker
After=network.target postgresql.service authentik-server.service
Wants=postgresql.service
Documentation=https://goauthentik.io/docs

[Service]
Type=simple
User=authentik
Group=authentik
WorkingDirectory=/opt/authentik
EnvironmentFile=/opt/authentik/.env
Environment=PATH=/opt/authentik/.venv/bin:/opt/authentik/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/opt/authentik/bin/authentik worker
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
"

msg_ok "Created systemd services"

msg_info "Enabling services"
systemctl daemon-reload
if ! systemctl enable -q --now authentik-server authentik-worker; then
    msg_error "Failed to enable services. Checking logs..."
    for svc in authentik-server authentik-worker; do
        echo "=== Status for $svc ==="
        systemctl status "$svc" --no-pager || true
        echo "=== Journal for $svc ==="
        journalctl -u "$svc" -n 50 --no-pager || true
        echo ""
    done
    exit 1
fi
msg_ok "Services enabled"

# Wait for server to be ready
msg_info "Waiting for Authentik to start"
for i in {1..60}; do
    if curl -fsS http://127.0.0.1:9000/-/health/ready/ >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! curl -fsS http://127.0.0.1:9000/-/health/ready/ >/dev/null 2>&1; then
    msg_info "Server starting (may take a moment to fully initialize)"
fi
msg_ok "Authentik started"

msg_info "Storing credentials"
{
    echo "Authentik Credentials"
    echo "====================="
    echo ""
    echo "Web Interface: http://$(hostname -I | awk '{print $1}'):9000"
    echo "Initial Setup: http://$(hostname -I | awk '{print $1}'):9000/if/flow/initial-setup/"
    echo ""
    echo "Database Credentials"
    echo "--------------------"
    echo "Database Name: ${DB_NAME}"
    echo "Database User: ${DB_USER}"
    echo "Database Password: ${DB_PASS}"
    echo ""
    echo "Secret Key: ${AUTHENTIK_SECRET_KEY}"
    echo ""
    echo "NOTE: Complete the initial setup wizard to create your admin account."
    echo "The default admin username will be 'akadmin'."
} >~/authentik.creds
chmod 600 ~/authentik.creds
msg_ok "Credentials stored in ~/authentik.creds"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt-get -y clean
msg_ok "Cleaned"

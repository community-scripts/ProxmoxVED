# Plane.so Bare Metal LXC Helper Script — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a ProxmoxVE community helper script that installs Plane.so v1.2.2 bare metal in an LXC container.

**Architecture:** Reverse-engineer Plane's Docker Compose (12 services) into native systemd services. Frontends (web, admin, space) are static builds served by Nginx. Backend is Django/Gunicorn + Celery workers. Infrastructure: PostgreSQL 16, Redis, RabbitMQ, MinIO.

**Tech Stack:** Python 3.12, Node.js 22, pnpm, turbo, Django, Celery, Gunicorn, Uvicorn, PostgreSQL, Redis, RabbitMQ, MinIO, Nginx

---

## Pre-work: Setup Fork

```bash
cd /Users/msaul/Documents/codes/proxmox/ProxmoxVE
git remote add fork https://github.com/onionrings29/ProxmoxVE.git 2>/dev/null || true
git checkout -b feat/add-plane
```

---

### Task 1: Create JSON Metadata (`frontend/public/json/plane.json`)

**Files:**
- Create: `frontend/public/json/plane.json`

**Step 1: Write the JSON file**

```json
{
    "name": "Plane",
    "slug": "plane",
    "categories": [
        25
    ],
    "date_created": "2026-02-25",
    "type": "ct",
    "updateable": true,
    "privileged": false,
    "interface_port": 80,
    "documentation": "https://developers.plane.so/self-hosting/overview",
    "website": "https://plane.so",
    "logo": "https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/plane.webp",
    "config_path": "/opt/plane/apps/api/.env",
    "description": "Open-source project tracking tool that helps teams plan, track, and manage their software projects with issues, cycles, and modules.",
    "install_methods": [
        {
            "type": "default",
            "script": "ct/plane.sh",
            "resources": {
                "cpu": 4,
                "ram": 8192,
                "hdd": 30,
                "os": "Debian",
                "version": "13"
            }
        }
    ],
    "default_credentials": {
        "username": null,
        "password": null
    },
    "notes": [
        {
            "text": "First user to sign up becomes the instance admin. Initial build takes 10-15 minutes.",
            "type": "info"
        },
        {
            "text": "Configuration file is at: `/opt/plane/apps/api/.env`. Credentials are saved to `~/plane.creds`.",
            "type": "info"
        }
    ]
}
```

**Step 2: Commit**

```bash
git add frontend/public/json/plane.json
git commit -m "feat: add Plane JSON metadata"
```

---

### Task 2: Create CT Script (`ct/plane.sh`)

**Files:**
- Create: `ct/plane.sh`

**Step 1: Write the CT script**

```bash
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: onionrings29
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://plane.so

APP="Plane"
var_tags="${var_tags:-project-management}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/plane ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "plane" "makeplane/plane"; then
    msg_info "Stopping Services"
    systemctl stop plane-api plane-worker plane-beat plane-live
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/plane/apps/api/.env /opt/plane-env.bak
    msg_ok "Backed up Data"

    msg_info "Downloading Update"
    RELEASE=$(get_latest_github_release "makeplane/plane")
    curl -fsSL "https://github.com/makeplane/plane/archive/refs/tags/${RELEASE}.tar.gz" -o /tmp/plane.tar.gz
    tar -xzf /tmp/plane.tar.gz -C /tmp
    rm -rf /opt/plane/apps /opt/plane/packages /opt/plane/package.json /opt/plane/pnpm-lock.yaml /opt/plane/pnpm-workspace.yaml /opt/plane/turbo.json
    cp -r /tmp/plane-*/apps /opt/plane/
    cp -r /tmp/plane-*/packages /opt/plane/
    cp /tmp/plane-*/package.json /opt/plane/
    cp /tmp/plane-*/pnpm-lock.yaml /opt/plane/
    cp /tmp/plane-*/pnpm-workspace.yaml /opt/plane/
    cp /tmp/plane-*/turbo.json /opt/plane/
    rm -rf /tmp/plane.tar.gz /tmp/plane-*
    msg_ok "Downloaded Update"

    msg_info "Restoring Config"
    cp /opt/plane-env.bak /opt/plane/apps/api/.env
    rm /opt/plane-env.bak
    msg_ok "Restored Config"

    msg_info "Rebuilding Frontend (Patience)"
    cd /opt/plane
    export NODE_OPTIONS="--max-old-space-size=4096"
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    $STD corepack enable pnpm
    $STD pnpm install --frozen-lockfile
    $STD pnpm turbo run build --filter=web --filter=admin --filter=space --filter=live
    msg_ok "Rebuilt Frontend"

    msg_info "Updating Python Dependencies"
    cd /opt/plane/apps/api
    $STD /opt/plane-venv/bin/pip install --upgrade -r requirements/production.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Running Migrations"
    cd /opt/plane/apps/api
    $STD /opt/plane-venv/bin/python manage.py migrate
    $STD /opt/plane-venv/bin/python manage.py collectstatic --noinput
    msg_ok "Ran Migrations"

    echo "${RELEASE}" >/opt/plane_version.txt

    msg_info "Starting Services"
    systemctl start plane-api plane-worker plane-beat plane-live
    msg_ok "Started Services"

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
```

**Step 2: Commit**

```bash
git add ct/plane.sh
git commit -m "feat: add Plane CT script"
```

---

### Task 3: Create Install Script (`install/plane-install.sh`)

**Files:**
- Create: `install/plane-install.sh`

This is the largest file. The install script performs:

1. Install system dependencies (build tools, libpq, xmlsec, etc.)
2. Install Node.js 22, PostgreSQL 16, Redis, RabbitMQ, MinIO
3. Clone Plane v1.2.2 source
4. Build frontends with pnpm + turbo
5. Setup Python venv + install API dependencies
6. Configure .env with generated secrets
7. Run Django migrations
8. Create MinIO uploads bucket
9. Create 5 systemd services (api, worker, beat, live, minio)
10. Configure Nginx reverse proxy
11. Cleanup

**Step 1: Write the install script**

```bash
#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: onionrings29
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://plane.so

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  nginx \
  build-essential \
  libpq-dev \
  libxml2-dev \
  libxslt1-dev \
  libxmlsec1-dev \
  libxmlsec1-openssl \
  pkg-config \
  python3-dev \
  python3-venv \
  redis-server \
  erlang-base \
  erlang-asn1 \
  erlang-crypto \
  erlang-eldap \
  erlang-ftp \
  erlang-inets \
  erlang-mnesia \
  erlang-os-mon \
  erlang-parsetools \
  erlang-public-key \
  erlang-runtime-tools \
  erlang-snmp \
  erlang-ssl \
  erlang-syntax-tools \
  erlang-tftp \
  erlang-tools \
  erlang-xmerl \
  rabbitmq-server
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
PG_DB_NAME="plane" PG_DB_USER="plane" setup_postgresql_db
get_lxc_ip

msg_info "Configuring RabbitMQ"
$STD rabbitmqctl add_vhost plane
$STD rabbitmqctl add_user plane plane
$STD rabbitmqctl set_permissions -p plane plane ".*" ".*" ".*"
msg_ok "Configured RabbitMQ"

msg_info "Installing MinIO"
curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio
chmod +x /usr/local/bin/minio
mkdir -p /opt/minio/data
MINIO_ACCESS_KEY=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
MINIO_SECRET_KEY=$(openssl rand -base64 36 | tr -dc 'a-zA-Z0-9' | head -c32)
cat <<EOF >/etc/default/minio
MINIO_ROOT_USER="${MINIO_ACCESS_KEY}"
MINIO_ROOT_PASSWORD="${MINIO_SECRET_KEY}"
MINIO_VOLUMES="/opt/minio/data"
EOF
cat <<EOF >/etc/systemd/system/minio.service
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server \$MINIO_VOLUMES --console-address ":9090"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now minio
msg_ok "Installed MinIO"

msg_info "Downloading Plane (Patience)"
RELEASE=$(get_latest_github_release "makeplane/plane")
curl -fsSL "https://github.com/makeplane/plane/archive/refs/tags/${RELEASE}.tar.gz" -o /tmp/plane.tar.gz
tar -xzf /tmp/plane.tar.gz -C /tmp
mv /tmp/plane-*/ /opt/plane
rm -f /tmp/plane.tar.gz
echo "${RELEASE}" >/opt/plane_version.txt
msg_ok "Downloaded Plane"

msg_info "Building Frontend Apps (Patience)"
cd /opt/plane
export NODE_OPTIONS="--max-old-space-size=4096"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD corepack enable pnpm
$STD pnpm install --frozen-lockfile
$STD pnpm turbo run build --filter=web --filter=admin --filter=space --filter=live
msg_ok "Built Frontend Apps"

msg_info "Setting up Python API"
python3 -m venv /opt/plane-venv
$STD /opt/plane-venv/bin/pip install --upgrade pip
$STD /opt/plane-venv/bin/pip install -r /opt/plane/apps/api/requirements/production.txt
msg_ok "Set up Python API"

msg_info "Configuring Plane"
SECRET_KEY=$(openssl rand -hex 32)
MACHINE_SIG=$(echo -n "$(hostname)-$(date +%s)" | sha256sum | head -c64)
cat <<EOF >/opt/plane/apps/api/.env
DEBUG=0
CORS_ALLOWED_ORIGINS=http://${LOCAL_IP}

POSTGRES_USER=plane
POSTGRES_PASSWORD=${PG_DB_PASS}
POSTGRES_HOST=localhost
POSTGRES_DB=plane
POSTGRES_PORT=5432
DATABASE_URL=postgresql://plane:${PG_DB_PASS}@localhost:5432/plane

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_URL=redis://localhost:6379/

RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USER=plane
RABBITMQ_PASSWORD=plane
RABBITMQ_VHOST=plane
AMQP_URL=amqp://plane:plane@localhost:5672/plane

AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}
AWS_S3_ENDPOINT_URL=http://localhost:9000
AWS_S3_BUCKET_NAME=uploads
FILE_SIZE_LIMIT=5242880

USE_MINIO=1
MINIO_ENDPOINT_SSL=0
SECRET_KEY=${SECRET_KEY}
MACHINE_SIGNATURE=${MACHINE_SIG}

WEB_URL=http://${LOCAL_IP}
ADMIN_BASE_URL=http://${LOCAL_IP}
ADMIN_BASE_PATH=/god-mode
SPACE_BASE_URL=http://${LOCAL_IP}
SPACE_BASE_PATH=/spaces
APP_BASE_URL=http://${LOCAL_IP}
APP_BASE_PATH=
LIVE_BASE_URL=http://${LOCAL_IP}
LIVE_BASE_PATH=/live

GUNICORN_WORKERS=2
LIVE_SERVER_SECRET_KEY=$(openssl rand -hex 16)
API_KEY_RATE_LIMIT=60/minute
EOF
msg_ok "Configured Plane"

msg_info "Running Database Migrations"
cd /opt/plane/apps/api
set -a
source /opt/plane/apps/api/.env
set +a
$STD /opt/plane-venv/bin/python manage.py migrate
$STD /opt/plane-venv/bin/python manage.py collectstatic --noinput
msg_ok "Ran Database Migrations"

msg_info "Creating MinIO Bucket"
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc
$STD /usr/local/bin/mc alias set plane http://localhost:9000 "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"
$STD /usr/local/bin/mc mb plane/uploads --ignore-existing
msg_ok "Created MinIO Bucket"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/plane-api.service
[Unit]
Description=Plane API
After=network.target postgresql.service redis-server.service rabbitmq-server.service minio.service

[Service]
Type=simple
WorkingDirectory=/opt/plane/apps/api
EnvironmentFile=/opt/plane/apps/api/.env
ExecStart=/opt/plane-venv/bin/gunicorn -w 2 -k uvicorn.workers.UvicornWorker plane.asgi:application --bind 0.0.0.0:8000 --max-requests 1200 --max-requests-jitter 1000 --access-logfile -
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/plane-worker.service
[Unit]
Description=Plane Celery Worker
After=plane-api.service

[Service]
Type=simple
WorkingDirectory=/opt/plane/apps/api
EnvironmentFile=/opt/plane/apps/api/.env
ExecStart=/opt/plane-venv/bin/celery -A plane worker -l info
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/plane-beat.service
[Unit]
Description=Plane Celery Beat
After=plane-api.service

[Service]
Type=simple
WorkingDirectory=/opt/plane/apps/api
EnvironmentFile=/opt/plane/apps/api/.env
ExecStart=/opt/plane-venv/bin/celery -A plane beat -l info
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/plane-live.service
[Unit]
Description=Plane Live Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/plane
ExecStart=/usr/bin/node apps/live/dist/index.js
Restart=on-failure
RestartSec=5
Environment=PORT=3100

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now plane-api
systemctl enable -q --now plane-worker
systemctl enable -q --now plane-beat
systemctl enable -q --now plane-live
msg_ok "Created Services"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/conf.d/plane.conf
upstream plane-api {
    server 127.0.0.1:8000;
}

upstream plane-live {
    server 127.0.0.1:3100;
}

upstream plane-minio {
    server 127.0.0.1:9000;
}

server {
    listen 80 default_server;
    server_name _;
    client_max_body_size 5M;

    # API and auth
    location /api/ {
        proxy_pass http://plane-api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /auth/ {
        proxy_pass http://plane-api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Django static files
    location /static/ {
        alias /opt/plane/apps/api/static/;
    }

    # Live (WebSocket)
    location /live/ {
        proxy_pass http://plane-live;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # MinIO uploads
    location /uploads/ {
        proxy_pass http://plane-minio;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Spaces frontend (static)
    location /spaces/ {
        alias /opt/plane/apps/space/build/client/;
        try_files \$uri \$uri/ /spaces/index.html;
    }

    location /spaces {
        return 301 /spaces/;
    }

    # Admin frontend (static)
    location /god-mode/ {
        alias /opt/plane/apps/admin/build/client/;
        try_files \$uri \$uri/ /god-mode/index.html;
    }

    location /god-mode {
        return 301 /god-mode/;
    }

    # Default: web frontend (static)
    location / {
        root /opt/plane/apps/web/build/client;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
$STD systemctl reload nginx
msg_ok "Configured Nginx"

msg_info "Saving Credentials"
{
    echo "Plane Credentials"
    echo "================================"
    echo "Database User: plane"
    echo "Database Password: ${PG_DB_PASS}"
    echo "MinIO Access Key: ${MINIO_ACCESS_KEY}"
    echo "MinIO Secret Key: ${MINIO_SECRET_KEY}"
    echo "Secret Key: ${SECRET_KEY}"
    echo "Config: /opt/plane/apps/api/.env"
} >~/plane.creds
msg_ok "Saved Credentials"

motd_ssh
customize
cleanup_lxc
```

**Step 2: Commit**

```bash
git add install/plane-install.sh
git commit -m "feat: add Plane install script"
```

---

### Task 4: Push to Fork

**Step 1: Push branch to onionrings29/ProxmoxVE**

```bash
git push fork feat/add-plane
```

---

### Task 5: Test (manual, on Proxmox)

After pushing, test on the actual Proxmox host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/onionrings29/ProxmoxVE/feat/add-plane/ct/plane.sh)"
```

Verify:
- Container creates successfully
- All services start (systemctl status plane-api plane-worker plane-beat plane-live minio)
- Web UI accessible at http://CONTAINER_IP
- Can sign up and create a workspace

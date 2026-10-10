#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/IgnisDa/ryot

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  nginx
msg_ok "Installed Dependencies"

NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs
PG_VERSION="18" setup_postgresql
PG_DB_NAME="ryot" PG_DB_USER="ryot" PG_DB_EXTENSIONS="uuid-ossp,pg_trgm" setup_postgresql_db

fetch_and_deploy_gh_release "ryot" "IgnisDa/ryot" "tarball"
RUST_TOOLCHAIN="$(sed -n 's/^channel = "\(.*\)"/\1/p' /opt/ryot/rust-toolchain.toml)" RUST_PROFILE="minimal" setup_rust

msg_info "Building Ryot (Patience)"
cd /opt/ryot
$STD yarn workspaces focus @ryot/root @ryot/frontend @ryot/transactional
$STD yarn workspace @ryot/transactional build
$STD yarn workspace @ryot/transactional copy-templates
APP_VERSION="v$(cat ~/.ryot)" UNKEY_ROOT_KEY="" CARGO_PROFILE_RELEASE_LTO=false CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
  $STD cargo build --locked --release --bin backend
mv /opt/ryot/target/release/backend /opt/ryot/backend
$STD yarn workspace @ryot/frontend build
$STD yarn workspaces focus @ryot/frontend --production
rm -rf /opt/ryot/target ~/.cargo/registry ~/.cargo/git ~/.yarn/berry
msg_ok "Built Ryot"

msg_info "Configuring Ryot"
mkdir -p /opt/ryot_data
cat <<EOF >/opt/ryot_data/.env
DATABASE_URL=postgres://ryot:${PG_DB_PASS}@127.0.0.1:5432/ryot
SERVER_ADMIN_ACCESS_TOKEN=$(openssl rand -hex 32)
SERVER_BACKEND_HOST=127.0.0.1
SERVER_BACKEND_PORT=5000
FRONTEND_URL=http://${LOCAL_IP}:8000
USERS_ALLOW_REGISTRATION=true
API_URL=http://127.0.0.1:5000
SESSION_SECRET=$(random_password 32)
MOVIES_AND_SHOWS_TMDB_ACCESS_TOKEN=
VIDEO_GAMES_TWITCH_CLIENT_ID=
VIDEO_GAMES_TWITCH_CLIENT_SECRET=
EOF
chmod 600 /opt/ryot_data/.env
msg_ok "Configured Ryot"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/ryot-backend.service
[Unit]
Description=Ryot Backend
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ryot
EnvironmentFile=/opt/ryot_data/.env
ExecStart=/opt/ryot/backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/ryot-frontend.service
[Unit]
Description=Ryot Frontend
After=network.target ryot-backend.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ryot/apps/frontend
EnvironmentFile=/opt/ryot_data/.env
Environment=NODE_ENV=production
Environment=HOST=127.0.0.1
Environment=PORT=3000
ExecStart=/opt/ryot/apps/frontend/node_modules/.bin/react-router-serve ./build/server/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ryot-backend ryot-frontend
msg_ok "Created Services"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/ryot
server {
    listen 8000;
    server_name _;
    client_max_body_size 0;

    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    location /backend {
        rewrite ^/backend/?(.*)\$ /\$1 break;
        proxy_pass http://127.0.0.1:5000;
    }

    location /_i/ {
        proxy_pass http://127.0.0.1:5000/webhooks/integrations/;
    }

    location /u/ {
        rewrite ^/u/(.*)\$ /api/sharing/\$1?isAccountDefault=true break;
        proxy_pass http://127.0.0.1:3000;
    }

    location /_s/ {
        proxy_pass http://127.0.0.1:3000/api/sharing/;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
    }
}
EOF
nginx_enable_site "ryot"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc

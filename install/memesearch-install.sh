#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/meme-search/meme-search

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  pkg-config \
  libpq-dev \
  libvips42t64
msg_ok "Installed Dependencies"

PG_VERSION="17" PG_MODULES="pgvector" setup_postgresql
PG_DB_NAME="memesearch" PG_DB_USER="memesearch" PG_DB_EXTENSIONS="vector" setup_postgresql_db
PYTHON_VERSION="3.12" setup_uv
setup_hwaccel

fetch_and_deploy_gh_release "memesearch" "meme-search/meme-search" "tarball"
RUBY_VERSION="$(sed 's/^ruby-//' /opt/memesearch/meme_search/meme_search_app/.ruby-version)" RUBY_INSTALL_RAILS="false" setup_ruby

msg_info "Configuring Meme Search"
mkdir -p /opt/memesearch_data/{memes/direct-uploads,models,generator} /app/public
# The generator hardcodes /app/db for its job queue and /app/public/memes as the meme root
ln -s /opt/memesearch_data/generator /app/db
ln -s /opt/memesearch_data/memes /app/public/memes
rm -rf /opt/memesearch/meme_search/meme_search_app/public/memes
ln -s /opt/memesearch_data/memes /opt/memesearch/meme_search/meme_search_app/public/memes
# Rails reaches the generator by its compose service name
cat <<EOF >>/etc/hosts
127.0.0.1 image_to_text_generator
EOF
cat <<EOF >/opt/memesearch_data/.env
RAILS_ENV=production
SECRET_KEY_BASE=$(openssl rand -hex 64)
DATABASE_URL=postgres://memesearch:${PG_DB_PASS}@localhost:5432/memesearch
MEME_SEARCH_ALLOWED_HOSTS=${LOCAL_IP}
APP_HOST=127.0.0.1
GEN_PORT=8000
HF_HOME=/opt/memesearch_data/models
EOF
chmod 600 /opt/memesearch_data/.env
msg_ok "Configured Meme Search"

msg_info "Building Meme Search"
export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
cd /opt/memesearch/meme_search/meme_search_app
$STD bundle config set --local deployment true
$STD bundle config set --local without "development test"
$STD bundle install
$STD bundle exec bootsnap precompile --gemfile app/ lib/
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 $STD ./bin/rails assets:precompile
set -a
source /opt/memesearch_data/.env
set +a
$STD ./bin/rails db:prepare
msg_ok "Built Meme Search"

msg_info "Installing Meme Search Generator"
cd /opt/memesearch/meme_search/image_to_text_generator
$STD uv venv --python 3.12 .venv
# Plain PyPI torch drags in ~3 GB of CUDA libraries; take them only when an NVIDIA GPU is passed through
$STD uv pip install --python .venv/bin/python -r requirements.txt --torch-backend "$([[ -e /dev/nvidia0 ]] && echo auto || echo cpu)"
msg_ok "Installed Meme Search Generator"

msg_info "Creating Meme Search Services"
cat <<EOF >/etc/systemd/system/memesearch.service
[Unit]
Description=Meme Search
After=network.target postgresql.service memesearch-generator.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/memesearch/meme_search/meme_search_app
EnvironmentFile=/opt/memesearch_data/.env
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/memesearch/meme_search/meme_search_app/bin/rails server -b 0.0.0.0 -p 3000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/memesearch-jobs.service
[Unit]
Description=Meme Search Jobs
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/memesearch/meme_search/meme_search_app
EnvironmentFile=/opt/memesearch_data/.env
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/memesearch/meme_search/meme_search_app/bin/jobs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/memesearch-generator.service
[Unit]
Description=Meme Search Image-to-Text Generator
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/memesearch/meme_search/image_to_text_generator/app
EnvironmentFile=/opt/memesearch_data/.env
ExecStart=/opt/memesearch/meme_search/image_to_text_generator/.venv/bin/python app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now memesearch-generator memesearch memesearch-jobs
msg_ok "Created Meme Search Services"

motd_ssh
customize
cleanup_lxc

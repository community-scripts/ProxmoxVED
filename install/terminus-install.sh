#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jaworek
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/usetrmnl/terminus
#
# SYNC CHECKLIST (run when updating to new Terminus version):
# 1. Check .config/setup/.env.tt for new/changed environment variables
#    https://github.com/usetrmnl/terminus/blob/main/.config/setup/.env.tt
# 2. Check Dockerfile for system dependencies (apt install line)
#    https://github.com/usetrmnl/terminus/blob/main/Dockerfile
# 3. Check .node-version for Node.js version
#    https://github.com/usetrmnl/terminus/blob/main/.node-version
# 4. Check compose.yml for PostgreSQL version
#    https://github.com/usetrmnl/terminus/blob/main/compose.yml
# 5. Check bin/setup for any new setup steps (development only, adapt for production)
#    https://github.com/usetrmnl/terminus/blob/main/bin/setup
# 6. Check .ruby-version for Ruby version; update RUBY_VERSION below if changed
# 7. Update NODE_VERSION and PG_VERSION variables below if changed
# 8. Update .env template in this script if new vars added
# 9. Test fresh install and update path before merging

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
  git \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  libyaml-dev \
  libpq-dev \
  imagemagick \
  gsfonts \
  redis-server \
  chromium \
  fonts-noto-cjk \
  libjemalloc2
msg_ok "Installed Dependencies"

NODE_VERSION="26" setup_nodejs
PG_VERSION="18" setup_postgresql
PG_DB_NAME="terminus" PG_DB_USER="terminus" setup_postgresql_db

# Terminus requires Ruby 4.0.x (per .ruby-version). Debian 13 only provides Ruby 3.3.x.
# setup_ruby uses rbenv/ruby-build to compile exact version from source (~10-20 mins).
RUBY_VERSION="4.0.6" RUBY_INSTALL_RAILS="false" setup_ruby

msg_info "Fetching latest version"
# Terminus uses tags only (no GitHub Releases). Standard functions query /releases (404).
# Timed curl avoids hangs from github_api_call (no max-time / interactive token prompt).
ensure_dependencies jq
gh_auth=()
[[ -n "${GITHUB_TOKEN:-}" ]] && gh_auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
LATEST_TAG=$(
  curl -fsSL --connect-timeout 10 --max-time 30 \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${gh_auth[@]}" \
    "https://api.github.com/repos/usetrmnl/terminus/tags?per_page=1" |
    jq -r '.[0].name // empty'
) || true
if [[ -z "$LATEST_TAG" ]]; then
  msg_error "Could not fetch latest Terminus tag from GitHub (network/rate limit?)"
  msg_error "Retry later or: export GITHUB_TOKEN=\"ghp_...\""
  exit 1
fi
echo "$LATEST_TAG" >~/.terminus
msg_ok "Latest version: $LATEST_TAG"

msg_info "Downloading Terminus"
curl -fsSL --connect-timeout 10 --max-time 120 \
  "https://github.com/usetrmnl/terminus/archive/refs/tags/$LATEST_TAG.tar.gz" \
  -o /tmp/terminus.tar.gz
tar --no-same-owner -xzf /tmp/terminus.tar.gz -C /tmp
mkdir -p /opt/terminus
shopt -s dotglob nullglob
cp -r /tmp/terminus-*/. /opt/terminus/
shopt -u dotglob nullglob
rm -rf /tmp/terminus*

msg_info "Initializing Git repository"
# Init git repo so Terminus version helper (git_link) can resolve commit SHA.
# Without this, git rev-parse fails -> UI shows "Latest (ahead of X.Y.Z)" with 404 link.
# Mirrors upstream Dockerfile which clones bare repo with tags.
cd /opt/terminus
git init -q
git config user.email "terminus@local"
git config user.name "Terminus"
git add -A
git commit -m "Release $LATEST_TAG" -q
git tag "$LATEST_TAG"
GIT_SHA=$(git rev-parse --short HEAD)
msg_ok "Downloaded Terminus"

msg_info "Configuring Application"
TERMINUS_SECRET=$(openssl rand -hex 64)
TERMINUS_VERSION=$(cat ~/.terminus)
cat <<EOF >/opt/terminus/.env
HANAMI_ENV=production
HANAMI_SERVE_ASSETS=true
HANAMI_PORT=2300
API_URI=http://${LOCAL_IP}:2300
APP_SECRET=${TERMINUS_SECRET}
DATABASE_URL=postgresql://terminus:${PG_DB_PASS}@localhost:5432/terminus
DATABASE_NAME=terminus
DATABASE_USER=terminus
DATABASE_PASSWORD=${PG_DB_PASS}
DATABASE_HOST=localhost
DATABASE_PORT=5432
GIT_TAG=${TERMINUS_VERSION}
GIT_LATEST_SHA=${GIT_SHA}
KEYVALUE_URL=redis://localhost:6379/0
KEYVALUE_DATABASE=0
KEYVALUE_PASSWORD=
KEYVALUE_PORT=6379
EOF
msg_ok "Configured Application"

msg_info "Installing Ruby Dependencies"
cd /opt/terminus
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(rbenv init - bash)" 2>/dev/null || true
$STD bundle config set --local without 'development test quality tools'
$STD bundle install
msg_ok "Installed Ruby Dependencies"

msg_info "Installing JavaScript Dependencies"
$STD npm install
msg_ok "Installed JavaScript Dependencies"

msg_info "Preparing Database"
cd /opt/terminus
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(rbenv init - bash)" 2>/dev/null || true
set -a
source /opt/terminus/.env
set +a
$STD bundle exec hanami db prepare
msg_ok "Prepared Database"

msg_info "Compiling Assets"
cd /opt/terminus
$STD bundle exec hanami assets compile
msg_ok "Compiled Assets"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/terminus-web.service
[Unit]
Description=Terminus Web Server
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/terminus
EnvironmentFile=/opt/terminus/.env
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
ExecStart=/root/.rbenv/shims/bundle exec puma --config ./config/puma.rb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/terminus-worker.service
[Unit]
Description=Terminus Sidekiq Worker
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/terminus
EnvironmentFile=/opt/terminus/.env
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
ExecStart=/root/.rbenv/shims/bundle exec sidekiq -r ./config/sidekiq.rb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now terminus-web terminus-worker
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
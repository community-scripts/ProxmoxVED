#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: jaworek
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/usetrmnl/terminus

APP="Terminus"
var_tags="${var_tags:-trmnl;epaper;byos}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/terminus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for updates"
  # Terminus uses tags only (no GitHub Releases). Standard check_for_gh_release → /releases (404).
  # Fetch tags with timeouts; avoid get_latest_gh_tag/github_api_call which can hang on
  # network stalls or block on interactive GITHUB_TOKEN prompts during rate limits.
  ensure_dependencies jq
  local gh_auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && gh_auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  LATEST_TAG=$(
    curl -fsSL --connect-timeout 10 --max-time 30 \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${gh_auth[@]}" \
      "https://api.github.com/repos/usetrmnl/terminus/tags?per_page=1" |
      jq -r '.[0].name // empty'
  ) || true
  CURRENT_VERSION=$(cat ~/.terminus 2>/dev/null || echo "none")

  if [[ -z "$LATEST_TAG" ]]; then
    msg_error "Could not fetch latest Terminus tag from GitHub (network/rate limit?)"
    msg_error "Retry later or: export GITHUB_TOKEN=\"ghp_...\""
    exit
  fi

  if [[ "$LATEST_TAG" == "$CURRENT_VERSION" ]]; then
    msg_ok "Already up to date (${CURRENT_VERSION})"
    exit
  fi
  msg_ok "Update available: ${CURRENT_VERSION} → ${LATEST_TAG}"

  msg_info "Stopping Services"
  systemctl stop terminus-web terminus-worker
  msg_ok "Stopped Services"

  create_backup /opt/terminus/.env

  msg_info "Downloading Terminus $LATEST_TAG"
  curl -fsSL --connect-timeout 10 --max-time 120 \
    "https://github.com/usetrmnl/terminus/archive/refs/tags/$LATEST_TAG.tar.gz" \
    -o /tmp/terminus.tar.gz
  rm -rf /opt/terminus/*
  tar --no-same-owner -xzf /tmp/terminus.tar.gz -C /tmp
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
  echo "$LATEST_TAG" >~/.terminus
  msg_ok "Downloaded Terminus $LATEST_TAG"

  msg_info "Restoring Configuration"
  restore_backup
  if ! grep -q "HANAMI_SERVE_ASSETS" /opt/terminus/.env; then
    echo "HANAMI_SERVE_ASSETS=true" >>/opt/terminus/.env
  fi
  sed -i "s|^GIT_TAG=.*|GIT_TAG=$LATEST_TAG|" /opt/terminus/.env
  sed -i "s|^GIT_LATEST_SHA=.*|GIT_LATEST_SHA=$GIT_SHA|" /opt/terminus/.env
  msg_ok "Restored Configuration"

  msg_info "Installing Dependencies"
  export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
  eval "$(rbenv init - bash)" 2>/dev/null || true
  cd /opt/terminus
  $STD bundle install
  $STD npm install
  msg_ok "Installed Dependencies"

  msg_info "Running Database Migrations"
  cd /opt/terminus
  export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
  eval "$(rbenv init - bash)" 2>/dev/null || true
  set -a
  source /opt/terminus/.env
  set +a
  $STD bundle exec hanami db migrate
  msg_ok "Ran Database Migrations"

  msg_info "Compiling Assets"
  cd /opt/terminus
  $STD bundle exec hanami assets compile
  msg_ok "Compiled Assets"

  msg_info "Starting Services"
  systemctl start terminus-web terminus-worker
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2300${CL}"

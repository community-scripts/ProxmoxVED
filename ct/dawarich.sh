#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Freika/dawarich

APP="Dawarich"
var_tags="${var_tags:-location;tracking;gps}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-15}"
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

  if [[ ! -d /opt/dawarich ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "dawarich" "Freika/dawarich"; then
    msg_info "Stopping Services"
    systemctl stop dawarich-web dawarich-worker
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp -r /opt/dawarich/app/storage /opt/dawarich_storage_backup 2>/dev/null || true
    cp /opt/dawarich/app/config/master.key /opt/dawarich_master.key 2>/dev/null || true
    cp /opt/dawarich/app/config/credentials.yml.enc /opt/dawarich_credentials.yml.enc 2>/dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "dawarich" "Freika/dawarich" "tarball" "latest" "/opt/dawarich/app"
    RUBY_VERSION=$(cat /opt/dawarich/app/.ruby-version 2>/dev/null || echo "3.4.6")
    RUBY_VERSION=${RUBY_VERSION} RUBY_INSTALL_RAILS="false" HOME=/home/dawarich setup_ruby

    source /opt/dawarich/.env
    export PATH="/home/dawarich/.rbenv/shims:/home/dawarich/.rbenv/bin:$PATH"
    eval "$(/home/dawarich/.rbenv/bin/rbenv init - bash)"
    cd /opt/dawarich/app
    chown -R dawarich:dawarich /home/dawarich/.rbenv
    chown -R dawarich:dawarich /opt/dawarich

    msg_info "Running Migrations"
    cat <<'EOF' >/opt/dawarich/update_script.sh
#!/bin/bash
source /opt/dawarich/.env
export PATH="/home/dawarich/.rbenv/shims:/home/dawarich/.rbenv/bin:$PATH"
eval "$(/home/dawarich/.rbenv/bin/rbenv init - bash)"
cd /opt/dawarich/app
bundle config set --local deployment 'true'
bundle config set --local without 'development test'
bundle install
SECRET_KEY_BASE_DUMMY=1 bundle exec rake assets:precompile
bundle exec rails db:migrate
bundle exec rake data:migrate
EOF
    chmod +x /opt/dawarich/update_script.sh
    $STD sudo -u dawarich bash /opt/dawarich/update_script.sh
    rm -f /opt/dawarich/update_script.sh
    msg_ok "Ran Migrations"

    msg_info "Restoring Data"
    cp -r /opt/dawarich_storage_backup/. /opt/dawarich/app/storage/ 2>/dev/null || true
    cp /opt/dawarich_master.key /opt/dawarich/app/config/master.key 2>/dev/null || true
    cp /opt/dawarich_credentials.yml.enc /opt/dawarich/app/config/credentials.yml.enc 2>/dev/null || true
    rm -rf /opt/dawarich_storage_backup /opt/dawarich_master.key /opt/dawarich_credentials.yml.enc
    chown -R dawarich:dawarich /opt/dawarich
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start dawarich-web dawarich-worker
    msg_ok "Started Services"
    msg_ok "Updated Successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"

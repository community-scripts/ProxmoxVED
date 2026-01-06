#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# Co-Author: SunFlowerOwl
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/manyfold3d/manyfold

APP="Manyfold"
var_tags="${var_tags:-3d}"
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
    if [[ ! -d /opt/manyfold ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    if check_for_gh_release "manyfold" "manyfold3d/manyfold"; then
        msg_info "Stopping Service"
        systemctl stop manyfold.target manyfold-rails.1 manyfold-default_worker.1 manyfold-performance_worker.1
        msg_ok "Stopped Service"

        msg_info "Backing up data"
        source /opt/manyfold/.env
        mv /opt/manyfold/app/storage /opt/manyfold/app/tmp /opt/manyfold/app/config/credentials.yml.enc /opt/manyfold/app/config/master.key ~/
        $STD tar -cvzf "/opt/manyfold_${APP_VERSION}_backup.tar.gz" /opt/manyfold/app/
        rm -rf /opt/manyfold/app/
        msg_ok "Backed-up data"

        fetch_and_deploy_gh_release "manyfold" "manyfold3d/manyfold" "tarball" "latest" "/opt/manyfold/app"

        msg_info "Configuring manyfold environment"
        RUBY_INSTALL_VERSION=$(cat /opt/manyfold/app/.ruby-version)
        YARN_VERSION=$(grep '"packageManager":' /opt/manyfold/app/package.json | sed -E 's/.*"(yarn@[0-9\.]+)".*/\1/')
        RELEASE=$(get_latest_github_release "manyfold3d/manyfold")
        sed -i "s/^export APP_VERSION=.*/export APP_VERSION=$RELEASE/" "/opt/manyfold/.env"
        cat <<EOF >/opt/manyfold/user_setup.sh
#!/bin/bash

source /opt/manyfold/.env
export PATH="/home/manyfold/.rbenv/bin:\$PATH"
eval "\$(/home/manyfold/.rbenv/bin/rbenv init - bash)"
cd /opt/manyfold/app
rbenv global $RUBY_INSTALL_VERSION
gem install bundler
bundle install
gem install sidekiq
gem install foreman
corepack enable yarn
corepack prepare $YARN_VERSION --activate
corepack use $YARN_VERSION
bin/rails db:migrate
bin/rails assets:precompile
EOF
        msg_ok "Configured manyfold environment"

        RUBY_VERSION=${RUBY_INSTALL_VERSION} RUBY_INSTALL_RAILS="true" HOME=/home/manyfold setup_ruby

        msg_info "Installing Manyfold"
        chown -R manyfold:manyfold /home/manyfold/.rbenv
        rm -rf /opt/manyfold/app/storage /opt/manyfold/app/tmp /opt/manyfold/app/config/credentials.yml.enc
        mv ~/storage ~/tmp /opt/manyfold/app/
        mv ~/credentials.yml.enc ~/master.key /opt/manyfold/app/config/
        chown -R manyfold:manyfold /opt/manyfold
        chmod +x /opt/manyfold/user_setup.sh
        $STD sudo -u manyfold bash /opt/manyfold/user_setup.sh
        rm -f /opt/manyfold/user_setup.sh
        msg_ok "Installed manyfold"

        msg_info "Restoring Service"
        source /opt/manyfold/.env
        export PATH="/home/manyfold/.rbenv/shims:/home/manyfold/.rbenv/bin:$PATH"
        $STD foreman export systemd /etc/systemd/system -a manyfold -u manyfold -f /opt/manyfold/app/Procfile
        for f in /etc/systemd/system/manyfold-*.service; do
            sed -i "s|/bin/bash -lc '|/bin/bash -lc 'source /opt/manyfold/.env \&\& |" "$f"
        done
        systemctl enable -q --now manyfold.target manyfold-rails.1 manyfold-default_worker.1 manyfold-performance_worker.1
        msg_ok "Restored Service"
    fi

    msg_info "Cleaning up"
    $STD apt -y autoremove
    $STD apt -y autoclean
    $STD apt -y clean
    msg_ok "Cleaned"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"

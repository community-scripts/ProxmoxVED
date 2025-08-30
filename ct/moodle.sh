#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/EEJoshua/ProxmoxVED/refs/heads/moodle/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: EEJoshua
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://moodle.org/

APP="Moodle"
var_tags="${var_tags:-lms;php}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /var/www/moodle/version.php ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Preparing repository"
  $STD git config --system --add safe.directory /var/www/moodle || true

  BRANCH="$(runuser -u www-data -- git -C /var/www/moodle rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'MOODLE_500_STABLE')"
  msg_info "Updating $APP (${BRANCH})"
  $STD runuser -u www-data -- git -C /var/www/moodle fetch --all --prune
  $STD runuser -u www-data -- git -C /var/www/moodle checkout -B "${BRANCH}" "origin/${BRANCH}"
  $STD runuser -u www-data -- git -C /var/www/moodle reset --hard "origin/${BRANCH}"
  $STD runuser -u www-data -- /usr/bin/php /var/www/moodle/admin/cli/maintenance.php --enable
  $STD runuser -u www-data -- /usr/bin/php /var/www/moodle/admin/cli/upgrade.php --non-interactive
  $STD runuser -u www-data -- /usr/bin/php /var/www/moodle/admin/cli/purge_caches.php
  $STD runuser -u www-data -- /usr/bin/php /var/www/moodle/admin/cli/maintenance.php --disable
  msg_ok "Update Successful"
  exit
}

start
build_container

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
echo -e "${INFO}${YW} Database and Admin credentials are saved in ~/moodle.creds${CL} inside the LXC"
#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: reptil1990
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://mailcow.email/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Removing default MTA"
$STD systemctl stop postfix 2>/dev/null
$STD systemctl disable postfix 2>/dev/null
$STD apt-get purge -y postfix 2>/dev/null
msg_ok "Removed default MTA"

msg_info "Installing Docker"
setup_docker
msg_ok "Installed Docker"

msg_info "Cloning Mailcow"
$STD git clone https://github.com/mailcow/mailcow-dockerized.git /opt/mailcow-dockerized
msg_ok "Cloned Mailcow"

read -r -p "${TAB3}Enter Mailcow FQDN (e.g., mail.example.com): " MAILCOW_FQDN
if [[ -z "$MAILCOW_FQDN" ]]; then
  msg_error "FQDN cannot be empty!"
  exit 1
fi

echo -e "${TAB3}Select Mailcow Branch:"
echo -e "${TAB3}  1) stable (recommended)"
echo -e "${TAB3}  2) nightly"
read -r -p "${TAB3}Enter choice [1-2, default: 1]: " MAILCOW_BRANCH_CHOICE
case "${MAILCOW_BRANCH_CHOICE}" in
  2) MAILCOW_BRANCH="nightly" ;;
  *) MAILCOW_BRANCH="stable" ;;
esac

msg_info "Generating Mailcow Configuration (${MAILCOW_BRANCH})"
cd /opt/mailcow-dockerized
MAILCOW_HOSTNAME="$MAILCOW_FQDN" MAILCOW_TZ="$tz" MAILCOW_BRANCH="$MAILCOW_BRANCH" $STD ./generate_config.sh
msg_ok "Generated Mailcow Configuration"

msg_info "Applying LXC-specific adjustments"
# Redis: Comment out sysctls (not supported in unprivileged LXC)
sed -i '/redis-mailcow:/,/restart:/{
  /sysctls:/,/net\.core\.somaxconn/{
    s/^/#/
  }
}' /opt/mailcow-dockerized/docker-compose.yml

# Dovecot: Reduce nproc ulimit for unprivileged container
sed -i '/dovecot-mailcow:/,/restart:/{
  s/nproc: 65536/nproc: 30000/
}' /opt/mailcow-dockerized/docker-compose.yml
msg_ok "Applied LXC-specific adjustments"

msg_info "Pulling Mailcow Docker Images"
cd /opt/mailcow-dockerized
$STD docker compose pull
msg_ok "Pulled Mailcow Docker Images"

msg_info "Starting Mailcow"
cd /opt/mailcow-dockerized
$STD docker compose up -d
msg_ok "Started Mailcow"

motd_ssh
customize
cleanup_lxc

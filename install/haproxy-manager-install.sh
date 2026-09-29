#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Alex Van de Putte (avandeputte)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/avandeputte/haproxy-manager

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# The release .deb carries everything: acme.sh inside the package, and
# haproxy, keepalived and the Python dependencies through Depends.
fetch_and_deploy_gh_release "haproxy-manager" "avandeputte/haproxy-manager" "binary" "latest" "/opt/haproxy-manager" "haproxy-manager_*_all.deb"

msg_info "Starting HAProxy Cluster Manager"
# The package is installed under SYSTEMD_OFFLINE, so its own restart is a
# no-op here; start it explicitly and wait for the UI to answer.
systemctl enable -q --now haproxy-manager
for _ in {1..30}; do
  curl -fs -o /dev/null http://127.0.0.1:8080/ && break
  sleep 2
done
msg_ok "Started HAProxy Cluster Manager"

msg_info "Saving Credentials"
# The package seeds a random administrator login and API key on first install
# and keeps them in its data directory; surface them where every script does.
{
  cat /var/lib/haproxy-manager/admin-credentials.txt
  echo "api-key: $(cat /var/lib/haproxy-manager/api-key.txt)"
} >>~/haproxy-manager.creds
chmod 600 ~/haproxy-manager.creds
msg_ok "Saved Credentials to ~/haproxy-manager.creds"

motd_ssh
customize
cleanup_lxc

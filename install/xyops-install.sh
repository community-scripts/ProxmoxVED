#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: audricrosier
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://xyops.io/ | Docs: https://docs.xyops.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y build-essential python3-setuptools
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
fetch_and_deploy_gh_release "xyops" "pixlcore/xyops" "tarball"

msg_info "Building xyOps"
cd /opt/xyops
$STD npm install
$STD node bin/build.js dist
msg_ok "Built xyOps"

msg_info "Configuring xyOps"
cat <<EOF >/opt/xyops/.env
XYOPS_hostname=${LOCAL_IP}
XYOPS_masters=${LOCAL_IP}
XYOPS_base_app_url=http://${LOCAL_IP}:5522
TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
EOF

cat <<EOF >/etc/systemd/system/xyops.service
[Unit]
Description=xyOps Conductor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/xyops
EnvironmentFile=/opt/xyops/.env
ExecStart=/usr/bin/node --max-old-space-size=4096 /opt/xyops/lib/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now xyops
msg_ok "Configured xyOps"

msg_info "Waiting for xyOps to become ready"
for _ in $(seq 1 30); do
  curl -fsS "http://127.0.0.1:5522/api/app/ping" >/dev/null 2>&1 && break
  sleep 2
done
msg_ok "xyOps is ready"

msg_info "Installing Local xySat Worker"
# xyOps only bundles a satellite/worker with its Docker image; a bare-metal
# install has to add one via the same API the "Add Server" UI button calls.
# The conductor's default admin/admin login is only valid until the first
# real browser sign-in (force_password_change is set), so this has to run
# now rather than being left as a manual post-install step.
LOGIN_RESP=$(curl -fsS -c /tmp/xyops_cookies.txt -X POST "http://127.0.0.1:5522/api/user/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}')
CSRF_TOKEN=$(echo "$LOGIN_RESP" | grep -o '"csrf_token":"[^"]*"' | cut -d'"' -f4)

# The API rejects the session cookie alone with {"code":"session"} - it also
# requires the CSRF token from the login response as an explicit header.
SAT_RESP=$(curl -fsS -b /tmp/xyops_cookies.txt -X POST "http://127.0.0.1:5522/api/app/get_satellite_token" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: ${CSRF_TOKEN}" \
  -d "{\"title\":\"${HN}-local\",\"enabled\":true,\"icon\":\"\",\"groups\":[]}")
SAT_TOKEN=$(echo "$SAT_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

curl -fsS "http://127.0.0.1:5522/api/app/satellite/install?t=${SAT_TOKEN}" | $STD sh
rm -f /tmp/xyops_cookies.txt

# xyOps only looks for a satellite at boot; it wasn't there for the first
# start above, so restart once now that /opt/xyops/satellite exists.
systemctl restart xyops
msg_ok "Installed Local xySat Worker"

motd_ssh
customize
cleanup_lxc

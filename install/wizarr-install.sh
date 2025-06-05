#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/wizarrrr/wizarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  sqlite3
msg_ok "Installed Dependencies"

setup_uv
NODE_VERSION="22" install_node_and_modules

msg_info "Installing ${APPLICATION}"
RELEASE=$(curl -s https://api.github.com/repos/wizarrrr/wizarr/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL "https://github.com/wizarrrr/wizarr/archive/refs/tags/${RELEASE}.zip" -o /tmp/"$RELEASE".zip
unzip -q /tmp/"$RELEASE".zip
mv wizarr-${RELEASE}/ /opt/wizarr
cd /opt/wizarr
uv -q sync --locked
uv -q run pybabel compile -d app/translations
$STD npm --prefix app/static install
mkdir -p ./.cache
uv -q run flask db upgrade
echo "${RELEASE}" >/opt/wizarr_version.txt
msg_ok "Installed ${APPLICATION}"

msg_info "Creating env, start script and service"
LOCAL_IP="$(hostname -I | awk '{print $1}')"
cat <<EOF >/opt/wizarr/.env
APP_URL=http://${LOCAL_IP}
DISABLE_BUILTIN_AUTH=false
LOG_LEVEL=INFO
EOF

cat <<EOF >/opt/wizarr/start.sh
#!/usr/bin/env bash

uv run gunicorn \
    --config gunicorn.conf.py \
    --preload \
    --workers 4 \
    --bind 0.0.0.0:5690 \
    --umask 007 \
    run:app
EOF
chmod u+x /opt/wizarr/start.sh

cat <<EOF >/etc/systemd/system/wizarr.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/wizarr
EnvironmentFile=/opt/wizarr/.env
ExecStart=/opt/wizarr/start.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now wizarr.service
msg_ok "Created env, start script and service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f /tmp/"$RELEASE".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

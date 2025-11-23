#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: rrole
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://wanderer.to

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os


msg_info "Installing dependencies"
$STD apt-get update
$STD apt-get upgrade
$STD apt-get install --no-install-recommends -y \
  git \
  golang-go \
  npm \
  nodejs 
msg_ok "Installded Dependencies"

INSTALL_DIR="/opt/${APPLICATION}"
SRC_DIR="${INSTALL_DIR}/source"
DB_DIR="${SRC_DIR}/db"
SEARCH_DIR="${SRC_DIR}/search"
WEB_DIR="${SRC_DIR}/web"
DATA_DIR="${INSTALL_DIR}/data"
PB_DB_LOCATION="${DATA_DIR}/pb_data"
MEILI_DB_LOCATION="${DATA_DIR}/meili_data"


mkdir -p "$INSTALL_DIR"
mkdir -p "$SRC_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$PB_DB_LOCATION"
mkdir -p "$MEILI_DB_LOCATION"

$STD fetch_and_deploy_gh_release "wanderer" "Flomp/wanderer" "tarball" "latest" "$SRC_DIR"

msg_info "Installing ${APPLICATION} (patience)"
cd $SEARCH_DIR
$STD fetch_and_deploy_gh_release "meilisearch" "meilisearch/meilisearch" "binary" "latest" "$SEARCH_DIR"
$STD meilisearch &
$STD sleep 1
$STD kill %%
cd $DB_DIR
$STD go mod tidy && $STD go build
cd $WEB_DIR
$STD npm i -s vitest
$STD npm ci --omit=dev
$STD npm run build
msg_ok "Installed ${APPLICATION}"

msg_info "Modifying user, creating env file, scripts & services"
MEILI_KEY=$(openssl rand -hex 32)
POCKETBASE_KEY=$(openssl rand -hex 16)
LOCAL_IP="$(hostname -I | awk '{print $1}')"

cat <<EOF >"${INSTALL_DIR}"/.env
ORIGIN=http://${LOCAL_IP}:3000
MEILI_HTTP_ADDR=${LOCAL_IP}:7700
MEILI_URL=http://${LOCAL_IP}:7700
MEILI_MASTER_KEY=${MEILI_KEY}
PB_URL=${LOCAL_IP}:8090
PUBLIC_POCKETBASE_URL=http://${LOCAL_IP}:8090
PUBLIC_VALHALLA_URL=https://valhalla1.openstreetmap.de
POCKETBASE_ENCRYPTION_KEY=${POCKETBASE_KEY}
PB_DB_LOCATION=${PB_DB_LOCATION}
MEILI_DB_PATH=${MEILI_DB_LOCATION}
EOF
cat <<EOF >"${INSTALL_DIR}"/start.sh
#!/usr/bin/env bash

trap "kill 0" EXIT

cd ${SEARCH_DIR} && meilisearch --master-key \$MEILI_MASTER_KEY &
cd ${DB_DIR} && ./pocketbase serve --http=\$PB_URL --dir=\$PB_DB_LOCATION &
cd ${WEB_DIR} && node build &

wait -n
EOF
chmod +x  "${INSTALL_DIR}"/start.sh
cat <<EOF >/etc/systemd/system/"${APPLICATION}"-web.service
[Unit]
Description=${APPLICATION}
After=network.target
StartLimitIntervalSec=10
StartLimitBurst=5

[Service]
Type=simple
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/bin/bash ${INSTALL_DIR}/start.sh
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
sleep 1
systemctl enable -q --now "$APPLICATION"-web.service
msg_ok "Modified user, created env file, scripts and services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt clean -y
msg_ok "Cleaned"

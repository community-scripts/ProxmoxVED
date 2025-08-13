#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: b3nw
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vrtmrz/obsidian-livesync

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  mc \
  apt-transport-https
msg_ok "Installed Dependencies"

msg_info "Installing Apache CouchDB"
ERLANG_COOKIE=$(openssl rand -base64 32)
ADMIN_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)"
export COUCHDB_USER=admin
export COUCHDB_PASSWORD=${ADMIN_PASS}
debconf-set-selections <<< "couchdb couchdb/cookie string $ERLANG_COOKIE"
debconf-set-selections <<< "couchdb couchdb/mode select standalone"
debconf-set-selections <<< "couchdb couchdb/bindaddress string 0.0.0.0"
debconf-set-selections <<< "couchdb couchdb/adminpass password $COUCHDB_PASSWORD"
debconf-set-selections <<< "couchdb couchdb/adminpass_again password $COUCHDB_PASSWORD"
curl -fsSL https://couchdb.apache.org/repo/keys.asc | gpg --dearmor -o /usr/share/keyrings/couchdb-archive-keyring.gpg
VERSION_CODENAME="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"
echo "deb [signed-by=/usr/share/keyrings/couchdb-archive-keyring.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ ${VERSION_CODENAME} main" >/etc/apt/sources.list.d/couchdb.sources.list
$STD apt-get update
$STD apt-get install -y couchdb
msg_ok "Installed Apache CouchDB."

msg_info "Initializing CouchDB for Obsidian LiveSync"
systemctl restart couchdb >/dev/null 2>&1 || true

AUTH="-u ${COUCHDB_USER}:${COUCHDB_PASSWORD}"
BASE="http://127.0.0.1:5984/_node/_local/_config"
curl -fsS $AUTH -X PUT "$BASE/chttpd/enable_cors" -H "Content-Type: application/json" -d '"true"' >/dev/null
curl -fsS $AUTH -X PUT "$BASE/cors/origins"        -H "Content-Type: application/json" -d '"*"' >/dev/null
curl -fsS $AUTH -X PUT "$BASE/cors/credentials"    -H "Content-Type: application/json" -d '"true"' >/dev/null
curl -fsS $AUTH -X PUT "$BASE/cors/methods"        -H "Content-Type: application/json" -d '"GET,PUT,POST,HEAD,DELETE,OPTIONS"' >/dev/null
curl -fsS $AUTH -X PUT "$BASE/cors/headers"        -H "Content-Type: application/json" -d '"accept,authorization,content-type,origin,referer,user-agent"' >/dev/null
msg_ok "Initialized CouchDB for Obsidian LiveSync"

DB_NAME="obsidiannotes"
curl -fsS -o /dev/null -w '' $AUTH -X PUT "http://127.0.0.1:5984/${DB_NAME}" || true

COUCH_VER=$(couchdb -V 2>/dev/null | awk '{print $3}')
[[ -z "$COUCH_VER" ]] && COUCH_VER=$(dpkg -s couchdb 2>/dev/null | awk -F': ' '/^Version:/{print $2}')
echo "${COUCH_VER:-unknown}" >/opt/"${APP}"_version.txt

RPY="no"
if command -v whiptail >/dev/null 2>&1; then
  if whiptail --title "Reverse Proxy" --yesno "Will you access CouchDB via an existing reverse proxy (HTTPS domain)?" 10 70; then
    RPY="yes"
    EXTERNAL_HOST=$(whiptail --inputbox "Enter external hostname (e.g., livesync.example.com)" 10 70 --title "External Host" 3>&1 1>&2 2>&3)
    EXTERNAL_PORT=$(whiptail --inputbox "Enter external port (443 for HTTPS)" 10 70 443 --title "External Port" 3>&1 1>&2 2>&3)
  fi
fi

IP_ADDR=$(hostname -I | awk '{print $1}')
HOST_URL="http://${IP_ADDR}:5984"
if [[ "$RPY" == "yes" && -n "$EXTERNAL_HOST" ]]; then
  if [[ "$EXTERNAL_PORT" == "443" || -z "$EXTERNAL_PORT" ]]; then
    HOST_URL="https://${EXTERNAL_HOST}"
  else
    HOST_URL="https://${EXTERNAL_HOST}:${EXTERNAL_PORT}"
  fi
fi
if ! command -v deno >/dev/null 2>&1; then
  curl -fsSL https://deno.land/install.sh | bash -s -- -q >/dev/null 2>&1
  export PATH="$HOME/.deno/bin:$PATH"
fi
echo "" | tee -a ~/"${APP}".creds
echo "Generating Setup URI using upstream tool..." | tee -a ~/"${APP}".creds
(
  export hostname="$HOST_URL"
  export database="$DB_NAME"
  export username="$COUCHDB_USER"
  export password="$COUCHDB_PASSWORD"
  deno run -A https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/flyio/generate_setupuri.ts
) 2>&1 | tee -a ~/"${APP}".creds

if [[ "$RPY" == "yes" && -n "$EXTERNAL_HOST" ]]; then
  echo "" | tee -a ~/"${APP}".creds
  echo "Reverse proxy quick notes:" | tee -a ~/"${APP}".creds
  echo "- External URL: $HOST_URL" | tee -a ~/"${APP}".creds
  echo "- Backend (CouchDB): http://${IP_ADDR}:5984" | tee -a ~/"${APP}".creds
  echo "" | tee -a ~/"${APP}".creds
  echo "Nginx (server block snippet):" | tee -a ~/"${APP}".creds
  cat <<'NGINX' | tee -a ~/"${APP}".creds
location / {
  proxy_pass http://BACKEND:5984;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-Proto https;
  add_header Access-Control-Allow-Origin "app://obsidian.md,capacitor://localhost,http://localhost" always;
  add_header Access-Control-Allow-Methods "GET,PUT,POST,HEAD,DELETE,OPTIONS" always;
  add_header Access-Control-Allow-Headers "accept,authorization,content-type,origin,referer,user-agent" always;
  add_header Access-Control-Allow-Credentials "true" always;
}
NGINX
  echo "Replace BACKEND with ${IP_ADDR}." | tee -a ~/"${APP}".creds
  echo "" | tee -a ~/"${APP}".creds
  echo "Traefik labels (docker-compose):" | tee -a ~/"${APP}".creds
  cat <<'TRAEFIK' | tee -a ~/"${APP}".creds
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.obsidian.rule=Host(`YOUR_DOMAIN`)"
  - "traefik.http.routers.obsidian.entrypoints=websecure"
  - "traefik.http.routers.obsidian.tls=true"
  - "traefik.http.services.obsidian.loadbalancer.server.port=5984"
  - "traefik.http.routers.obsidian.middlewares=obsidiancors"
  - "traefik.http.middlewares.obsidiancors.headers.accesscontrolallowmethods=GET,PUT,POST,HEAD,DELETE,OPTIONS"
  - "traefik.http.middlewares.obsidiancors.headers.accesscontrolallowheaders=accept,authorization,content-type,origin,referer,user-agent"
  - "traefik.http.middlewares.obsidiancors.headers.accesscontrolalloworiginlist=app://obsidian.md,capacitor://localhost,http://localhost"
  - "traefik.http.middlewares.obsidiancors.headers.accesscontrolmaxage=3600"
  - "traefik.http.middlewares.obsidiancors.headers.addvaryheader=true"
  - "traefik.http.middlewares.obsidiancors.headers.accessControlAllowCredentials=true"
TRAEFIK
  echo "Replace YOUR_DOMAIN with ${EXTERNAL_HOST}." | tee -a ~/"${APP}".creds
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

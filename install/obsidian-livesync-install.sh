#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/vrtmrz/obsidian-livesync

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing CouchDB"
DEBIAN_FRONTEND=noninteractive $STD apt install -y couchdb
msg_ok "Installed CouchDB"

msg_info "Configuring CouchDB"
COUCHDB_PASSWORD="$(openssl rand -hex 24)"
mkdir -p /etc/couchdb/local.d /opt/obsidian-livesync
cat <<EOF >/etc/couchdb/local.d/obsidian-livesync.ini
[couchdb]
single_node = true
max_document_size = 50000000

[admins]
admin = ${COUCHDB_PASSWORD}

[chttpd]
bind_address = 0.0.0.0
port = 5984
max_http_request_size = 4294967296

[chttpd_auth]
require_valid_user = true

[httpd]
enable_cors = true
WWW-Authenticate = Basic realm="couchdb"

[cors]
credentials = true
origins = app://obsidian.md,capacitor://localhost,http://localhost
headers = accept, authorization, content-type, origin, referer
methods = GET, PUT, POST, HEAD, DELETE
max_age = 3600
EOF
cat <<EOF >/opt/obsidian-livesync/.env
COUCHDB_URL=http://${LOCAL_IP}:5984
COUCHDB_USER=admin
COUCHDB_PASSWORD=${COUCHDB_PASSWORD}
COUCHDB_DATABASE=obsidiannotes
EOF
chmod 600 /opt/obsidian-livesync/.env
msg_ok "Configured CouchDB"

msg_info "Creating LiveSync Database"
systemctl enable -q --now couchdb
curl -fsS -u "admin:${COUCHDB_PASSWORD}" -X PUT http://127.0.0.1:5984/obsidiannotes >/dev/null
msg_ok "Created LiveSync Database"

motd_ssh
customize
cleanup_lxc

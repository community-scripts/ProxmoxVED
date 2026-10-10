#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/teamhanko/hanko

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="17" setup_postgresql
PG_DB_NAME="hanko" PG_DB_USER="hanko" setup_postgresql_db

fetch_and_deploy_gh_release "hanko" "teamhanko/hanko" "prebuild" "latest" "/opt/hanko" "hanko_Linux_$(arch_resolve "x86_64" "arm64").tar.gz" "backend/"

msg_info "Configuring Hanko"
mkdir -p /opt/hanko_data
# v3 reads the top-level secret_keys and cors keys; with the secrets.keys the upstream README
# still shows it signs with its built-in default key, and server.public.cors is ignored
cat <<EOF >/opt/hanko_data/config.yaml
database:
  host: localhost
  port: "5432"
  database: hanko
  user: hanko
  password: ${PG_DB_PASS}
  dialect: postgres
secret_keys:
  - $(random_password 32)
server:
  public:
    address: ":8000"
  admin:
    address: "127.0.0.1:8001"
service:
  name: Hanko Authentication Service
cors:
  allow_origins:
    - https://app.example.com
webauthn:
  relying_party:
    id: example.com
    origins:
      - https://app.example.com
email_delivery:
  from_address: noreply@example.com
  from_name: Hanko
  smtp:
    host: localhost
    port: "465"
    user: ""
    password: ""
EOF
chmod 600 /opt/hanko_data/config.yaml
$STD /opt/hanko/hanko migrate up --config /opt/hanko_data/config.yaml
msg_ok "Configured Hanko"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/hanko.service
[Unit]
Description=Hanko
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/hanko_data
ExecStart=/opt/hanko/hanko serve all --config /opt/hanko_data/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hanko
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

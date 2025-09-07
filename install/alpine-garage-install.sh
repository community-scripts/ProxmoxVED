#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://garagehq.deuxfleurs.fr/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Preparing directories"
mkdir -p /var/lib/garage/meta /var/lib/garage/data /var/lib/garage/snapshots
msg_ok "Prepared directories"

msg_info "Setup Garage packages"
$STD apk add --no-cache garage garage-openrc openssl
msg_ok "Setup Garage packages"

# msg_info "Generating RPC secret"
# if [[ ! -s /etc/garage.rpc_secret ]]; then
#   openssl rand -hex 32 | tr -d '\n' >/etc/garage.rpc_secret
#   chmod 600 /etc/garage.rpc_secret
# fi
# msg_ok "Generated RPC secret"

# msg_info "Generating tokens"
# if [[ ! -s /etc/garage.tokens.env ]]; then
#   ADMIN_TOKEN="$(openssl rand -base64 32)"
#   METRICS_TOKEN="$(openssl rand -base64 32)"
#   cat >/etc/garage.tokens.env <<EOF
# GARAGE_ADMIN_TOKEN="${ADMIN_TOKEN}"
# GARAGE_METRICS_TOKEN="${METRICS_TOKEN}"
# EOF
#   chmod 600 /etc/garage.tokens.env
# else
#   source /etc/garage.tokens.env
#   ADMIN_TOKEN="${GARAGE_ADMIN_TOKEN}"
#   METRICS_TOKEN="${GARAGE_METRICS_TOKEN}"
# fi
# msg_ok "Generated tokens"

msg_info "Writing config"
if [[ ! -f /etc/garage.toml ]]; then
  cat >/etc/garage.toml <<EOF
replication_factor = 1
consistency_mode = "consistent"

metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
metadata_snapshots_dir = "/var/lib/garage/snapshots"

db_engine = "lmdb"
metadata_fsync = true
data_fsync = false
metadata_auto_snapshot_interval = "6h"

rpc_bind_addr = "0.0.0.0:3901"
rpc_public_addr = "127.0.0.1:3901"
allow_world_readable_secrets = false

[s3_api]
api_bind_addr = "0.0.0.0:3900"
s3_region = "garage"
root_domain = ".s3.garage"

[s3_web]
bind_addr = "0.0.0.0:3902"
root_domain = ".web.garage"
add_host_to_metrics = true

[admin]
api_bind_addr = "0.0.0.0:3903"
metrics_require_token = false
EOF
fi
msg_ok "Wrote config"

msg_info "Enable + start service"
$STD rc-update add garage default
$STD rc-service garage restart || $STD rc-service garage start
$STD rc-service garage status || true
msg_ok "Service active"

msg_info "Setup Node"
garage node id
NODE_ID=$(garage node id | cut -d@ -f1)
garage layout assign $NODE_ID --capacity 1T
garage layout apply
garage status
msg_ok "Node setup"

motd_ssh
customize

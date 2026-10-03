#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Josua Blejeru (josuablejeru)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nisshi-io/nisshi

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_nisshi_storage:-}" ]]; then
  var_nisshi_storage=$(prompt_select "Nisshi storage engine:" 1 60 "sqlite" "s3" "postgres")
fi
if [[ "$var_nisshi_storage" == "postgres" && -z "${var_nisshi_postgres_url:-}" ]]; then
  var_nisshi_postgres_url=$(prompt_password "PostgreSQL URL (postgres://user:pass@host/db):" "" 120)
fi
if [[ "$var_nisshi_storage" == "s3" && -z "${var_nisshi_s3_bucket:-}" ]]; then
  var_nisshi_s3_bucket=$(prompt_input "S3 bucket for Nisshi storage:" "" 120)
fi

if [[ -z "${var_nisshi_iceberg_catalog:-}" ]]; then
  var_nisshi_iceberg_catalog=$(prompt_input "Iceberg REST catalog URL (Enter to skip):" "" 60)
fi
if [[ -n "$var_nisshi_iceberg_catalog" ]]; then
  if [[ -z "${var_nisshi_lake_location:-}" ]]; then
    var_nisshi_lake_location=$(prompt_input "Data lake location:" "s3://lake/" 120)
  fi
  if [[ -z "${var_nisshi_iceberg_warehouse:-}" ]]; then
    var_nisshi_iceberg_warehouse=$(prompt_input "Iceberg warehouse (Enter to skip):" "" 60)
  fi
fi

if [[ "$var_nisshi_storage" == "s3" ]] || [[ -n "$var_nisshi_iceberg_catalog" && "${var_nisshi_lake_location:-}" == s3://* ]]; then
  if [[ -z "${var_nisshi_s3_endpoint:-}" ]]; then
    var_nisshi_s3_endpoint=$(prompt_input "S3 endpoint URL (Enter for AWS):" "" 120)
  fi
  if [[ -z "${var_nisshi_s3_region:-}" ]]; then
    var_nisshi_s3_region=$(prompt_input "S3 region:" "us-east-1" 60)
  fi
  if [[ -z "${var_nisshi_s3_access_key:-}" ]]; then
    var_nisshi_s3_access_key=$(prompt_input "S3 access key ID:" "" 120)
  fi
  if [[ -z "${var_nisshi_s3_secret_key:-}" ]]; then
    var_nisshi_s3_secret_key=$(prompt_password "S3 secret access key:" "" 120)
  fi
fi

if [[ -z "${var_nisshi_otlp_endpoint:-}" ]]; then
  var_nisshi_otlp_endpoint=$(prompt_input "OTLP metrics endpoint URL (Enter to skip):" "" 60)
fi
if [[ -n "$var_nisshi_otlp_endpoint" && -z "${var_nisshi_otlp_headers:-}" ]]; then
  var_nisshi_otlp_headers=$(prompt_password "OTLP headers, e.g. Authorization=Bearer <token> (Enter to skip):" "" 60)
fi

# A half-configured service would leave the broker crash-looping, so drop it.
if [[ -z "${var_nisshi_s3_access_key:-}" || -z "${var_nisshi_s3_secret_key:-}" ]]; then
  if [[ "$var_nisshi_storage" == "s3" ]]; then
    msg_warn "S3 credentials are missing - using SQLite storage"
    var_nisshi_storage="sqlite"
  fi
  if [[ -n "$var_nisshi_iceberg_catalog" && "${var_nisshi_lake_location:-}" == s3://* ]]; then
    msg_warn "S3 credentials are missing - skipping the Iceberg data lake"
    var_nisshi_iceberg_catalog=""
  fi
fi
case "$var_nisshi_storage" in
s3)
  if [[ -n "${var_nisshi_s3_bucket:-}" ]]; then
    STORAGE_ENGINE="s3://${var_nisshi_s3_bucket}/"
  else
    msg_warn "No S3 bucket given - using SQLite storage"
    STORAGE_ENGINE="sqlite://nisshi.db"
  fi
  ;;
postgres)
  if [[ -n "${var_nisshi_postgres_url:-}" ]]; then
    STORAGE_ENGINE="$var_nisshi_postgres_url"
  else
    msg_warn "No PostgreSQL URL given - using SQLite storage"
    STORAGE_ENGINE="sqlite://nisshi.db"
  fi
  ;;
*)
  STORAGE_ENGINE="sqlite://nisshi.db"
  ;;
esac

fetch_and_deploy_gh_release "nisshi" "nisshi-io/nisshi" "prebuild" "latest" "/opt/nisshi" "nisshi-$(arch_resolve "x86_64" "aarch64")-unknown-linux-*.tar.gz"

if [[ "$STORAGE_ENGINE" == postgres://* || "$STORAGE_ENGINE" == postgresql://* ]]; then
  # The broker creates its tables on SQLite but not on PostgreSQL, where it
  # fails every request until the schema exists. postgresql-client is installed
  # only on this path, for the one psql call that loads it.
  msg_info "Loading Nisshi Schema into PostgreSQL"
  $STD apt install -y postgresql-client
  $STD psql "$STORAGE_ENGINE" -v ON_ERROR_STOP=1 -f /opt/nisshi/etc/initdb.d/010-schema.sql
  msg_ok "Loaded Nisshi Schema into PostgreSQL"
fi

msg_info "Configuring Nisshi"
mkdir -p /var/lib/nisshi/schema
cat <<EOF >/opt/nisshi/.env
CLUSTER_ID=nisshi
LISTENER_URL=tcp://0.0.0.0:9092
ADVERTISED_LISTENER_URL=tcp://${LOCAL_IP}:9092
STORAGE_ENGINE=${STORAGE_ENGINE}
RUST_LOG=warn
EOF
if [[ "$STORAGE_ENGINE" == s3://* || -n "$var_nisshi_iceberg_catalog" && "${var_nisshi_lake_location:-}" == s3://* ]]; then
  cat <<EOF >>/opt/nisshi/.env
AWS_ACCESS_KEY_ID=${var_nisshi_s3_access_key}
AWS_SECRET_ACCESS_KEY=${var_nisshi_s3_secret_key}
AWS_DEFAULT_REGION=${var_nisshi_s3_region}
EOF
  if [[ -n "${var_nisshi_s3_endpoint:-}" ]]; then
    cat <<EOF >>/opt/nisshi/.env
AWS_ENDPOINT=${var_nisshi_s3_endpoint}
EOF
  fi
  if [[ "${var_nisshi_s3_endpoint:-}" == http://* ]]; then
    cat <<EOF >>/opt/nisshi/.env
AWS_ALLOW_HTTP=true
EOF
  fi
fi
if [[ -n "$var_nisshi_iceberg_catalog" ]]; then
  # Paths in file:// URLs resolve against the working directory: /var/lib/nisshi/schema
  cat <<EOF >>/opt/nisshi/.env
SCHEMA_REGISTRY=file://schema
DATA_LAKE=${var_nisshi_lake_location}
ICEBERG_CATALOG=${var_nisshi_iceberg_catalog}
EOF
  if [[ -n "${var_nisshi_iceberg_warehouse:-}" ]]; then
    cat <<EOF >>/opt/nisshi/.env
ICEBERG_WAREHOUSE=${var_nisshi_iceberg_warehouse}
EOF
  fi
fi
if [[ -n "$var_nisshi_otlp_endpoint" ]]; then
  cat <<EOF >>/opt/nisshi/.env
OTEL_EXPORTER_OTLP_ENDPOINT=${var_nisshi_otlp_endpoint}
EOF
  if [[ -n "${var_nisshi_otlp_headers:-}" ]]; then
    cat <<EOF >>/opt/nisshi/.env
OTEL_EXPORTER_OTLP_HEADERS=${var_nisshi_otlp_headers}
EOF
  fi
fi
chmod 600 /opt/nisshi/.env
msg_ok "Configured Nisshi"

msg_info "Creating Service"
# The SQLite path is relative to WorkingDirectory, which keeps the database
# out of /opt/nisshi where an update would wipe it. The data lake is a
# subcommand of the broker, not an option.
cat <<EOF >/etc/systemd/system/nisshi.service
[Unit]
Description=Nisshi Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/nisshi
EnvironmentFile=/opt/nisshi/.env
ExecStart=/opt/nisshi/bin/nisshi broker${var_nisshi_iceberg_catalog:+ iceberg}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nisshi
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

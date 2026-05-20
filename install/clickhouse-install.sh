#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://clickhouse.com

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_clickhouse

msg_info "Configuring ClickHouse"
cat <<EOF >/etc/clickhouse-server/config.d/listen.xml
<clickhouse>
    <listen_host>0.0.0.0</listen_host>
</clickhouse>
EOF
systemctl restart clickhouse-server
msg_ok "Configured ClickHouse"

if [[ "${CLICKSTACK:-}" == "yes" ]]; then
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3
  msg_ok "Installed Dependencies"

  setup_mongodb
  NODE_VERSION="22" setup_nodejs

  msg_info "Initializing ClickHouse Schema"
  clickhouse client -n <<'EOSQL'
CREATE DATABASE IF NOT EXISTS default;

CREATE TABLE IF NOT EXISTS default.otel_logs
(
    `Timestamp` DateTime64(9) CODEC(Delta(8), ZSTD(1)),
    `TimestampTime` DateTime DEFAULT toDateTime(Timestamp),
    `TraceId` String CODEC(ZSTD(1)),
    `SpanId` String CODEC(ZSTD(1)),
    `TraceFlags` UInt8,
    `SeverityText` LowCardinality(String) CODEC(ZSTD(1)),
    `SeverityNumber` UInt8,
    `ServiceName` LowCardinality(String) CODEC(ZSTD(1)),
    `Body` String CODEC(ZSTD(1)),
    `ResourceSchemaUrl` LowCardinality(String) CODEC(ZSTD(1)),
    `ResourceAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `ScopeSchemaUrl` LowCardinality(String) CODEC(ZSTD(1)),
    `ScopeName` String CODEC(ZSTD(1)),
    `ScopeVersion` LowCardinality(String) CODEC(ZSTD(1)),
    `ScopeAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `LogAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    INDEX idx_trace_id TraceId TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_scope_attr_key mapKeys(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_scope_attr_value mapValues(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_log_attr_key mapKeys(LogAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_log_attr_value mapValues(LogAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_lower_body lower(Body) TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 8
)
ENGINE = MergeTree
PARTITION BY toDate(TimestampTime)
PRIMARY KEY (ServiceName, TimestampTime)
ORDER BY (ServiceName, TimestampTime, Timestamp)
TTL TimestampTime + toIntervalDay(30)
SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1;

CREATE TABLE IF NOT EXISTS default.otel_traces
(
    `Timestamp` DateTime64(9) CODEC(Delta(8), ZSTD(1)),
    `TraceId` String CODEC(ZSTD(1)),
    `SpanId` String CODEC(ZSTD(1)),
    `ParentSpanId` String CODEC(ZSTD(1)),
    `TraceState` String CODEC(ZSTD(1)),
    `SpanName` LowCardinality(String) CODEC(ZSTD(1)),
    `SpanKind` LowCardinality(String) CODEC(ZSTD(1)),
    `ServiceName` LowCardinality(String) CODEC(ZSTD(1)),
    `ResourceAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `ScopeName` String CODEC(ZSTD(1)),
    `ScopeVersion` String CODEC(ZSTD(1)),
    `SpanAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `Duration` UInt64 CODEC(ZSTD(1)),
    `StatusCode` LowCardinality(String) CODEC(ZSTD(1)),
    `StatusMessage` String CODEC(ZSTD(1)),
    `Events.Timestamp` Array(DateTime64(9)) CODEC(ZSTD(1)),
    `Events.Name` Array(LowCardinality(String)) CODEC(ZSTD(1)),
    `Events.Attributes` Array(Map(LowCardinality(String), String)) CODEC(ZSTD(1)),
    `Links.TraceId` Array(String) CODEC(ZSTD(1)),
    `Links.SpanId` Array(String) CODEC(ZSTD(1)),
    `Links.TraceState` Array(String) CODEC(ZSTD(1)),
    `Links.Attributes` Array(Map(LowCardinality(String), String)) CODEC(ZSTD(1)),
    INDEX idx_trace_id TraceId TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_span_attr_key mapKeys(SpanAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_span_attr_value mapValues(SpanAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_duration Duration TYPE minmax GRANULARITY 1,
    INDEX idx_lower_span_name lower(SpanName) TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 8
)
ENGINE = MergeTree
PARTITION BY toDate(Timestamp)
ORDER BY (ServiceName, SpanName, toDateTime(Timestamp))
TTL toDate(Timestamp) + toIntervalDay(30)
SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1;

CREATE TABLE IF NOT EXISTS default.hyperdx_sessions
(
    `Timestamp` DateTime64(9) CODEC(Delta(8), ZSTD(1)),
    `TimestampTime` DateTime DEFAULT toDateTime(Timestamp),
    `TraceId` String CODEC(ZSTD(1)),
    `SpanId` String CODEC(ZSTD(1)),
    `TraceFlags` UInt8,
    `SeverityText` LowCardinality(String) CODEC(ZSTD(1)),
    `SeverityNumber` UInt8,
    `ServiceName` LowCardinality(String) CODEC(ZSTD(1)),
    `Body` String CODEC(ZSTD(1)),
    `ResourceSchemaUrl` LowCardinality(String) CODEC(ZSTD(1)),
    `ResourceAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `ScopeSchemaUrl` LowCardinality(String) CODEC(ZSTD(1)),
    `ScopeName` String CODEC(ZSTD(1)),
    `ScopeVersion` LowCardinality(String) CODEC(ZSTD(1)),
    `ScopeAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `LogAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    INDEX idx_trace_id TraceId TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_scope_attr_key mapKeys(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_scope_attr_value mapValues(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_log_attr_key mapKeys(LogAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_log_attr_value mapValues(LogAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_body Body TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 8
)
ENGINE = MergeTree
PARTITION BY toDate(TimestampTime)
PRIMARY KEY (ServiceName, TimestampTime)
ORDER BY (ServiceName, TimestampTime, Timestamp)
TTL TimestampTime + toIntervalDay(30)
SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1;
EOSQL
  msg_ok "Initialized ClickHouse Schema"

  fetch_and_deploy_gh_release "otelcol" "open-telemetry/opentelemetry-collector-releases" "prebuild" "latest" "/opt/otelcol" "otelcol-contrib_*_linux_amd64.tar.gz"

  msg_info "Configuring OTel Collector"
  cat <<'EOF' >/opt/otelcol/config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  fluentforward:
    endpoint: 0.0.0.0:24225

processors:
  batch:
    timeout: 5s
    send_batch_size: 10000

exporters:
  clickhouse:
    endpoint: tcp://127.0.0.1:9000?dial_timeout=10s
    database: default
    create_schema: false
    logs_table_name: otel_logs
    traces_table_name: otel_traces

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  pipelines:
    logs:
      receivers: [otlp, fluentforward]
      processors: [batch]
      exporters: [clickhouse]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [clickhouse]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [clickhouse]
EOF
  msg_ok "Configured OTel Collector"

  fetch_and_deploy_gh_release "clickstack" "hyperdxio/hyperdx" "tarball" "latest" "/opt/clickstack"

  msg_info "Enabling Corepack"
  cd /opt/clickstack
  $STD corepack enable
  YARN_SPEC=$(node -e "const p=require('./package.json');process.stdout.write(p.packageManager||'yarn@stable')" 2>/dev/null || echo "yarn@stable")
  $STD corepack prepare "${YARN_SPEC}" --activate
  msg_ok "Enabled Corepack"

  msg_info "Building HyperDX"
  $STD yarn install
  $STD yarn workspace @hyperdx/common-utils run build
  rm -rf /opt/clickstack/packages/api/build
  yarn workspace @hyperdx/api exec tsc >>"$(get_active_logfile)" 2>&1 || true
  $STD yarn workspace @hyperdx/api exec tsc-alias
  cp -r /opt/clickstack/packages/api/src/opamp/proto /opt/clickstack/packages/api/build/opamp/ 2>/dev/null || true
  [[ -f /opt/clickstack/packages/api/build/index.js ]] || {
    msg_error "HyperDX API build failed: build/index.js not found"
    exit 1
  }
  $STD yarn workspace @hyperdx/app run build
  msg_ok "Built HyperDX"

  msg_info "Configuring ClickStack"
  HYPERDX_API_KEY=$(openssl rand -hex 16)

  cat <<EOF >/opt/clickstack/.env
FRONTEND_URL=http://${LOCAL_IP}:8080
HYPERDX_API_KEY=${HYPERDX_API_KEY}
HYPERDX_API_PORT=8000
HYPERDX_APP_PORT=8080
HYPERDX_APP_URL=http://${LOCAL_IP}
HYPERDX_LOG_LEVEL=info
MONGO_URI=mongodb://127.0.0.1:27017/hyperdx
SERVER_URL=http://127.0.0.1:8000
PORT=8000
OPAMP_PORT=4320
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_SERVICE_NAME=hdx-oss-app
NODE_ENV=production
IS_LOCAL_APP_MODE=DANGEROUSLY_is_local_app_mode💀
NEXT_PUBLIC_IS_LOCAL_MODE=true
DEFAULT_CONNECTIONS=[{"name":"Local ClickHouse","host":"http://127.0.0.1:8123","username":"default","password":""}]
DEFAULT_SOURCES=[{"name":"Logs","kind":"log","connection":"Local ClickHouse","from":"otel_logs","timestampValueExpression":"Timestamp","defaultTableSelectExpression":"*","serviceNameExpression":"ServiceName","bodyExpression":"Body","severityTextExpression":"SeverityText","traceIdExpression":"TraceId","spanIdExpression":"SpanId","traceSourceId":"Traces","sessionSourceId":"Sessions"},{"name":"Traces","kind":"trace","connection":"Local ClickHouse","from":"otel_traces","timestampValueExpression":"Timestamp","defaultTableSelectExpression":"*","serviceNameExpression":"ServiceName","bodyExpression":"SpanName","durationExpression":"Duration / 1000000","traceIdExpression":"TraceId","spanIdExpression":"SpanId","parentSpanIdExpression":"ParentSpanId","statusCodeExpression":"StatusCode","statusMessageExpression":"StatusMessage","logSourceId":"Logs","sessionSourceId":"Sessions"},{"name":"Sessions","kind":"session","connection":"Local ClickHouse","from":"hyperdx_sessions","timestampValueExpression":"Timestamp","defaultTableSelectExpression":"*","serviceNameExpression":"ServiceName","bodyExpression":"Body","severityTextExpression":"SeverityText","traceIdExpression":"TraceId","spanIdExpression":"SpanId","logSourceId":"Logs","traceSourceId":"Traces"}]
EOF
  msg_ok "Configured ClickStack"

  msg_info "Creating Services"
  cat <<EOF >/etc/systemd/system/clickstack-otel.service
[Unit]
Description=ClickStack OTel Collector
After=network.target clickhouse-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/otelcol
ExecStart=/opt/otelcol/otelcol-contrib --config /opt/otelcol/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/clickstack-api.service
[Unit]
Description=ClickStack HyperDX API
After=network.target mongod.service clickhouse-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/clickstack/packages/api
EnvironmentFile=/opt/clickstack/.env
ExecStart=/usr/bin/node /opt/clickstack/packages/api/build/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/clickstack-app.service
[Unit]
Description=ClickStack HyperDX Frontend
After=network.target clickstack-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/clickstack/packages/app
EnvironmentFile=/opt/clickstack/.env
Environment=PORT=8080
Environment=HOSTNAME=0.0.0.0
ExecStart=/usr/bin/node /opt/clickstack/node_modules/next/dist/bin/next start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now clickstack-otel
  systemctl enable -q --now clickstack-api
  systemctl enable -q --now clickstack-app
  msg_ok "Created Services"
fi

motd_ssh
customize
cleanup_lxc

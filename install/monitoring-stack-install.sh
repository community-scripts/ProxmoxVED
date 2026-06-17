#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Watashi (Watashi199) | Co-author: OpenAI Codex (GPT-5)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://grafana.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

GRAFANA_PORT="3000"
PROMETHEUS_PORT="9090"
ALERTMANAGER_PORT="9093"
LOKI_PORT="3100"
NODE_EXPORTER_PORT="9100"
ALLOY_PORT="12345"

setup_deb822_repo "grafana" \
  "https://apt.grafana.com/gpg.key" \
  "https://apt.grafana.com" \
  "stable" \
  "main"

msg_info "Installing Dependencies"
$STD apt install -y \
  alloy \
  grafana \
  loki \
  prometheus \
  prometheus-alertmanager \
  prometheus-node-exporter
msg_ok "Installed Dependencies"

mkdir -p \
  /opt/monitoring-stack \
  /etc/alertmanager \
  /etc/alloy \
  /etc/grafana/provisioning/dashboards \
  /etc/grafana/provisioning/datasources \
  /etc/prometheus/rules \
  /var/lib/alertmanager \
  /var/lib/alloy \
  /var/lib/grafana/dashboards \
  /var/lib/loki/chunks \
  /var/lib/loki/rules \
  /var/lib/loki/tmp \
  /var/lib/prometheus

if [[ -f /opt/monitoring-stack/.env ]]; then
  set -a
  # shellcheck source=/dev/null
  source /opt/monitoring-stack/.env
  set +a
fi

GRAFANA_USER="${GRAFANA_USER:-admin}"
if [[ -z "${GRAFANA_PASSWORD:-}" ]]; then
  GRAFANA_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
fi
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
MONITORING_INSTANCE_NAME="${MONITORING_INSTANCE_NAME:-monitoring-stack}"

msg_info "Writing Environment Configuration"
cat <<EOF >/opt/monitoring-stack/.env
GRAFANA_USER=${GRAFANA_USER}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL}
MONITORING_INSTANCE_NAME=${MONITORING_INSTANCE_NAME}
GRAFANA_PORT=${GRAFANA_PORT}
PROMETHEUS_PORT=${PROMETHEUS_PORT}
ALERTMANAGER_PORT=${ALERTMANAGER_PORT}
LOKI_PORT=${LOKI_PORT}
NODE_EXPORTER_PORT=${NODE_EXPORTER_PORT}
ALLOY_PORT=${ALLOY_PORT}
EOF
chmod 600 /opt/monitoring-stack/.env
msg_ok "Wrote Environment Configuration"

msg_info "Configuring Prometheus"
cat <<EOF >/etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitoring_instance: ${MONITORING_INSTANCE_NAME}

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - 127.0.0.1:${ALERTMANAGER_PORT}

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - 127.0.0.1:${PROMETHEUS_PORT}

  - job_name: node_exporter
    static_configs:
      - targets:
          - 127.0.0.1:${NODE_EXPORTER_PORT}

  - job_name: loki
    static_configs:
      - targets:
          - 127.0.0.1:${LOKI_PORT}

  - job_name: alloy
    static_configs:
      - targets:
          - 127.0.0.1:${ALLOY_PORT}
EOF

cat <<'EOF' >/etc/prometheus/rules/monitoring-stack.yml
groups:
  - name: monitoring-stack
    rules:
      - alert: Watchdog
        expr: vector(1)
        labels:
          severity: none
        annotations:
          summary: Monitoring watchdog

      - alert: PrometheusTargetMissing
        expr: up == 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: Scrape target unavailable
          description: '{{ $labels.job }} on {{ $labels.instance }} is unreachable.'
EOF
msg_ok "Configured Prometheus"

msg_info "Configuring Alertmanager"
if [[ -n "${DISCORD_WEBHOOK_URL}" ]]; then
  cat <<EOF >/etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by:
    - alertname
    - job
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h
  receiver: default-webhook

receivers:
  - name: default-webhook
    webhook_configs:
      - url: ${DISCORD_WEBHOOK_URL}
        send_resolved: true
EOF
else
  cat <<'EOF' >/etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by:
    - alertname
    - job
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h
  receiver: default-receiver

receivers:
  - name: default-receiver
EOF
fi
msg_ok "Configured Alertmanager"

msg_info "Configuring Loki"
cat <<EOF >/etc/loki/config.yml
auth_enabled: false

server:
  http_listen_address: 127.0.0.1
  http_listen_port: ${LOKI_PORT}

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://127.0.0.1:${ALERTMANAGER_PORT}
  storage:
    type: local
    local:
      directory: /var/lib/loki/rules
  ring:
    kvstore:
      store: inmemory
  rule_path: /var/lib/loki/tmp

analytics:
  reporting_enabled: false

limits_config:
  allow_structured_metadata: false

pattern_ingester:
  enabled: false
EOF
msg_ok "Configured Loki"

msg_info "Configuring Alloy"
cat <<EOF >/etc/alloy/config.alloy
logging {
  level  = "info"
  format = "logfmt"
}

local.file_match "system_logs" {
  path_targets = [
    {
      __path__ = "/var/log/*.log",
      job      = "varlogs",
      instance = "${MONITORING_INSTANCE_NAME}",
    },
    {
      __path__ = "/var/log/*/*.log",
      job      = "varlogs",
      instance = "${MONITORING_INSTANCE_NAME}",
    },
  ]
}

loki.source.file "system_logs" {
  targets    = local.file_match.system_logs.targets
  forward_to = [loki.write.local.receiver]
}

loki.source.journal "journald" {
  forward_to = [loki.write.local.receiver]
  max_age    = "24h"
  labels = {
    job      = "journald",
    instance = "${MONITORING_INSTANCE_NAME}",
  }
}

loki.write "local" {
  endpoint {
    url = "http://127.0.0.1:${LOKI_PORT}/loki/api/v1/push"
  }
}
EOF
msg_ok "Configured Alloy"

msg_info "Provisioning Grafana"
cat <<EOF >/etc/grafana/provisioning/datasources/monitoring-stack.yml
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:${PROMETHEUS_PORT}
    isDefault: true
    editable: false

  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://127.0.0.1:${LOKI_PORT}
    editable: false

  - name: Alertmanager
    uid: alertmanager
    type: alertmanager
    access: proxy
    url: http://127.0.0.1:${ALERTMANAGER_PORT}
    jsonData:
      implementation: prometheus
      handleGrafanaManagedAlerts: false
    editable: false
EOF

cat <<'EOF' >/etc/grafana/provisioning/dashboards/monitoring-stack.yml
apiVersion: 1
providers:
  - name: Monitoring Stack
    orgId: 1
    folder: Monitoring Stack
    type: file
    disableDeletion: false
    editable: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
EOF
msg_ok "Provisioned Grafana"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.console.templates=/usr/share/prometheus/consoles --web.console.libraries=/usr/share/prometheus/console_libraries --web.listen-address=0.0.0.0:${PROMETHEUS_PORT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/prometheus-alertmanager.service
[Unit]
Description=Prometheus Alertmanager Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/prometheus-alertmanager --config.file=/etc/alertmanager/alertmanager.yml --storage.path=/var/lib/alertmanager --web.listen-address=0.0.0.0:${ALERTMANAGER_PORT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/prometheus-node-exporter.service
[Unit]
Description=Prometheus Node Exporter Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/prometheus-node-exporter --web.listen-address=127.0.0.1:${NODE_EXPORTER_PORT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/loki.service
[Unit]
Description=Loki Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/loki -config.file=/etc/loki/config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/alloy.service
[Unit]
Description=Alloy Service
After=network.target loki.service
Requires=loki.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/alloy run --disable-reporting --storage.path=/var/lib/alloy --server.http.listen-addr=127.0.0.1:${ALLOY_PORT} /etc/alloy/config.alloy
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now prometheus
systemctl enable -q --now prometheus-alertmanager
systemctl enable -q --now prometheus-node-exporter
systemctl enable -q --now loki
systemctl enable -q --now alloy
systemctl enable -q --now grafana-server
msg_ok "Created Services"

msg_info "Configuring Grafana"
retries=0
while ! grafana-cli --homepath /usr/share/grafana admin reset-admin-password "${GRAFANA_PASSWORD}" &>/dev/null; do
  retries=$((retries + 1))
  if [[ ${retries} -ge 30 ]]; then
    msg_error "Failed to reset Grafana admin password"
    exit 1
  fi
  sleep 2
done
$STD systemctl restart grafana-server
msg_ok "Configured Grafana"

motd_ssh
customize
cleanup_lxc

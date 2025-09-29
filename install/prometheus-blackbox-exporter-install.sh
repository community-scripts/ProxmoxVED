#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Marfnl
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/prometheus/blackbox_exporter

# Import Functions and Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Install package
msg_info "Installing Prometheus Blackbox Exporter"
export DEBIAN_FRONTEND=noninteractive
$STD apt-get update
$STD apt-get install -y --no-install-recommends prometheus-blackbox-exporter ca-certificates curl
msg_ok "Installed Prometheus Blackbox Exporter"

# Configure exporter
msg_info "Configuring Blackbox Exporter"
# Minimal default config: just HTTP 2xx module
cat >/etc/prometheus/blackbox-exporter.yml <<'EOF'
modules:
  http_2xx:
    prober: http
EOF

# Ensure it listens on all interfaces:9115 and uses our config
sed -i 's|^ARGS=.*|ARGS="--config.file=/etc/prometheus/blackbox-exporter.yml --web.listen-address=0.0.0.0:9115"|' \
  /etc/default/prometheus-blackbox-exporter
msg_ok "Configured Blackbox Exporter"

# Enable service
msg_info "Enabling Service"
systemctl daemon-reload
systemctl enable -q --now prometheus-blackbox-exporter
msg_ok "Service Enabled"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

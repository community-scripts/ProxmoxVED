#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jacob-masse (jacob-masse)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://flowtriq.com

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  libpcap-dev \
  tcpdump
msg_ok "Installed Dependencies"

msg_info "Installing Flowtriq Agent"
$STD pip install --break-system-packages ftagent[full]
msg_ok "Installed Flowtriq Agent"

msg_info "Setting Up Configuration"
mkdir -p /etc/ftagent
mkdir -p /var/lib/ftagent/pcaps
cat <<EOF >/etc/ftagent/config.json
{
  "api_key": "",
  "node_uuid": "",
  "api_base": "https://flowtriq.com/api/v1",
  "interface": "auto",
  "pcap_enabled": true,
  "pcap_dir": "/var/lib/ftagent/pcaps",
  "pcap_max_packets": 10000,
  "pcap_max_seconds": 60,
  "pcap_retention_days": 7,
  "log_file": "/var/log/ftagent.log",
  "log_level": "INFO",
  "dynamic_threshold": true,
  "baseline_window_minutes": 60,
  "threshold_multiplier": 3.0,
  "heartbeat_interval": 30,
  "metrics_interval": 10
}
EOF
msg_ok "Set Up Configuration"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/ftagent.service
[Unit]
Description=Flowtriq DDoS Detection Agent
Documentation=https://flowtriq.com/docs?section=agent
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/ftagent
Restart=on-failure
RestartSec=10s
User=root
Group=root
RuntimeDirectory=ftagent
StateDirectory=ftagent
LogsDirectory=ftagent
PrivateTmp=true
NoNewPrivileges=false
ProtectHome=read-only
ProtectSystem=strict
ReadWritePaths=/var/lib/ftagent /var/log /etc/ftagent
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ftagent

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

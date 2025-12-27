#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: hoholms
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/grafana/loki

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Loki"
$STD apk add loki
$STD sed -i '/http_addr/s/127.0.0.1/0.0.0.0/g' /etc/conf.d/loki
$STD rc-service loki start
$STD rc-update add loki default
$STD mkdir /tmp/loki/
$STD chown -R loki:grafana /tmp/loki/
$STD mkdir /var/log/loki/
$STD chown -R loki:grafana /var/log/loki/
$STD chmod 755 /etc/loki/loki-local-config.yaml
$STD sed -i '/^querier:/,/enable_multi_variant_queries: false/ s/^/#/' /etc/loki/loki-local-config.yaml
$STD echo "output_log=\"\${output_log:-/var/log/loki/output.log}\"" >> /etc/init.d/loki
$STD echo "error_log=\"\${error_log:-/var/log/loki/error.log}\"" >> /etc/init.d/loki
$STD echo "start_stop_daemon_args=\"\${SSD_OPTS} -1 \${output_log} -2 \${error_log}\"" >> /etc/init.d/loki
$STD rc-service loki restart
msg_ok "Installed Loki"

msg_info "Installing Promtail"
$STD apk add loki-promtail
$STD sed -i '/http_addr/s/127.0.0.1/0.0.0.0/g' /etc/conf.d/loki
$STD rc-service loki-promtail start
$STD rc-update add loki-promtail default
msg_ok "Installed Promtail"

motd_ssh
customize

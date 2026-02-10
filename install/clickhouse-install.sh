#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Ali M. Jaradat (amjaradat01)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://clickhouse.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_clickhouse

msg_info "Configuring ClickHouse"
mkdir -p /etc/clickhouse-server/config.d
cat <<EOF >/etc/clickhouse-server/config.d/listen.xml
<clickhouse>
    <listen_host>0.0.0.0</listen_host>
</clickhouse>
EOF

cat <<EOF >/etc/security/limits.d/clickhouse.conf
clickhouse      soft    nofile  262144
clickhouse      hard    nofile  262144
EOF
msg_ok "Configured ClickHouse"

motd_ssh
customize
cleanup_lxc

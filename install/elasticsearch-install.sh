#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.elastic.co/elasticsearch

# shellcheck disable=SC1091
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y apt-transport-https
msg_ok "Installed Dependencies"

setup_deb822_repo "elasticsearch" \
  "https://artifacts.elastic.co/GPG-KEY-elasticsearch" \
  "https://artifacts.elastic.co/packages/9.x/apt" \
  "stable" \
  "main"

msg_info "Installing Elasticsearch"
$STD apt install -y elasticsearch
msg_ok "Installed Elasticsearch"

msg_info "Configuring Elasticsearch"
ES_CONFIG="/etc/elasticsearch/elasticsearch.yml"
# Bind to all interfaces so the node is reachable from the LXC network
sed -i 's|^#\?network.host:.*|network.host: 0.0.0.0|' "$ES_CONFIG"
grep -q '^network.host:' "$ES_CONFIG" || echo "network.host: 0.0.0.0" >>"$ES_CONFIG"
sed -i 's|^#\?http.port:.*|http.port: 9200|' "$ES_CONFIG"
grep -q '^http.port:' "$ES_CONFIG" || echo "http.port: 9200" >>"$ES_CONFIG"
# Single-node deployment: skip cluster bootstrap checks and master election
sed -i 's|^cluster.initial_master_nodes:|#cluster.initial_master_nodes:|' "$ES_CONFIG"
grep -q '^discovery.type:' "$ES_CONFIG" || echo "discovery.type: single-node" >>"$ES_CONFIG"
msg_ok "Configured Elasticsearch"

msg_info "Starting Elasticsearch"
systemctl enable -q --now elasticsearch
msg_ok "Started Elasticsearch"

msg_info "Setting elastic Password"
sleep 5
ELASTIC_PASSWORD="$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s)"
{
  echo "Elasticsearch Credentials"
  echo "URL: https://127.0.0.1:9200"
  echo "User: elastic"
  echo "Password: ${ELASTIC_PASSWORD}"
} >/root/elasticsearch.creds
chmod 600 /root/elasticsearch.creds
msg_ok "Set elastic Password"

msg_info "Checking Elasticsearch"
for i in {1..30}; do
  if curl -sk -u "elastic:${ELASTIC_PASSWORD}" "https://127.0.0.1:9200" >/dev/null; then
    break
  fi
  sleep 2
done
curl -sk -u "elastic:${ELASTIC_PASSWORD}" "https://127.0.0.1:9200" >/dev/null
msg_ok "Elasticsearch Running"

motd_ssh
customize
cleanup_lxc

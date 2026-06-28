#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.elastic.co/kibana

# shellcheck disable=SC1091
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

kibana_es_hosts_yaml() {
  local host
  local hosts="${KIBANA_ES_HOSTS:-https://127.0.0.1:9200}"
  local first=1
  local IFS=,
  local out="["

  for host in $hosts; do
    host="${host//[[:space:]]/}"
    if [[ -n "$host" ]]; then
      if [[ $first -eq 0 ]]; then
        out+=", "
      fi
      out+="\"${host}\""
      first=0
    fi
  done
  out+="]"
  echo "$out"
}

msg_info "Installing Dependencies"
$STD apt install -y apt-transport-https
msg_ok "Installed Dependencies"

setup_deb822_repo "elasticsearch" \
  "https://artifacts.elastic.co/GPG-KEY-elasticsearch" \
  "https://artifacts.elastic.co/packages/9.x/apt" \
  "stable" \
  "main"

msg_info "Installing Kibana"
$STD apt install -y kibana
msg_ok "Installed Kibana"

msg_info "Configuring Kibana"
KIBANA_CONFIG="/etc/kibana/kibana.yml"
cat <<EOF >"$KIBANA_CONFIG"
server.host: "0.0.0.0"
server.port: 5601
EOF

# Generate encryption keys for saved objects, reporting and security
/usr/share/kibana/bin/kibana-encryption-keys generate -q >>"$KIBANA_CONFIG" 2>/dev/null || true
chown root:kibana "$KIBANA_CONFIG"
chmod 660 "$KIBANA_CONFIG"
msg_ok "Configured Kibana"

if [[ -n "${KIBANA_ENROLLMENT_TOKEN:-}" ]]; then
  msg_info "Enrolling Kibana with Elasticsearch"
  $STD /usr/share/kibana/bin/kibana-setup --enrollment-token "${KIBANA_ENROLLMENT_TOKEN}"
  msg_ok "Enrolled Kibana with Elasticsearch"
else
  msg_info "Connecting Kibana to Elasticsearch"
  {
    echo "elasticsearch.hosts: $(kibana_es_hosts_yaml)"
    echo "elasticsearch.username: \"${KIBANA_ES_USERNAME:-kibana_system}\""
    if [[ -n "${KIBANA_ES_PASSWORD:-}" ]]; then
      echo "elasticsearch.password: \"${KIBANA_ES_PASSWORD}\""
    fi
    echo "elasticsearch.ssl.verificationMode: none"
  } >>"$KIBANA_CONFIG"
  msg_ok "Connected Kibana to Elasticsearch"
fi

msg_info "Starting Kibana"
systemctl enable -q --now kibana
msg_ok "Started Kibana"

msg_info "Checking Kibana"
for i in {1..60}; do
  if curl -sk "http://127.0.0.1:5601/api/status" | grep -q '"level":"available"'; then
    break
  fi
  sleep 3
done
msg_ok "Kibana Running"

motd_ssh
customize
cleanup_lxc

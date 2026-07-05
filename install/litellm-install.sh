#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# Co-Authors: MickLesk, tremor021 (prior pip/Prisma versions)
# Refactor: Docker Compose official stack (community contribution preserved)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Pinned upstream compose artifacts (BerriAI/litellm)
LITELLM_REF="79a6b8f7f0cd"
LITELLM_RAW="https://raw.githubusercontent.com/BerriAI/litellm/${LITELLM_REF}"
LITELLM_DIR="/opt/litellm"

setup_docker

msg_info "Fetching LiteLLM Docker Compose stack (${LITELLM_REF})"
mkdir -p "$LITELLM_DIR"
cd "$LITELLM_DIR"
curl -fsSL "${LITELLM_RAW}/docker-compose.yml" -o docker-compose.yml
curl -fsSL "${LITELLM_RAW}/prometheus.yml" -o prometheus.yml
msg_ok "Fetched compose files"

msg_info "Generating secrets"
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 16)"
LITELLM_SALT_KEY="sk-$(openssl rand -hex 16)"
POSTGRES_PASSWORD="$(openssl rand -hex 16)"

cat <<EOF >"$LITELLM_DIR/.env"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}"
LITELLM_SALT_KEY="${LITELLM_SALT_KEY}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
EOF

# Replace example credentials from upstream compose with generated secrets
sed -i "s/dbpassword9090/${POSTGRES_PASSWORD}/g" "$LITELLM_DIR/docker-compose.yml"
if grep -q "dbpassword9090" "$LITELLM_DIR/docker-compose.yml"; then
  msg_error "Failed to replace default Postgres password in docker-compose.yml"
  exit 150
fi

# Bind auxiliary services to localhost only (proxy stays on :4000)
sed -i 's/- "5432:5432"/- "127.0.0.1:5432:5432"/' "$LITELLM_DIR/docker-compose.yml"
sed -i 's/- "9090:9090"/- "127.0.0.1:9090:9090"/' "$LITELLM_DIR/docker-compose.yml"
msg_ok "Generated secrets and hardened port bindings"

msg_info "Starting LiteLLM stack (Patience)"
cd "$LITELLM_DIR"
$STD docker compose up -d

msg_info "Waiting for LiteLLM health check"
CONTAINER_ID=""
for i in $(seq 1 90); do
  if curl -sf "http://127.0.0.1:4000/health/liveliness" >/dev/null 2>&1; then
    msg_ok "LiteLLM is healthy"
    break
  fi
  CONTAINER_ID=$(docker ps -q --filter "name=litellm-litellm" | head -1)
  if [[ -n "$CONTAINER_ID" ]]; then
    STATUS=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "$CONTAINER_ID" 2>/dev/null || echo "starting")
    if [[ "$STATUS" == "unhealthy" ]]; then
      msg_error "LiteLLM container is unhealthy — check: docker compose logs litellm"
      docker compose logs litellm 2>/dev/null | tail -30
      exit 150
    fi
  fi
  sleep 2
  if [[ "$i" -eq 90 ]]; then
    msg_error "LiteLLM did not become healthy within 180s"
    docker compose logs litellm 2>/dev/null | tail -30
    exit 150
  fi
done

cat <<EOF >~/litellm.creds
LiteLLM Credentials
URL: http://${LOCAL_IP}:4000
Master Key: ${LITELLM_MASTER_KEY}
Salt Key: ${LITELLM_SALT_KEY}
Postgres Password: ${POSTGRES_PASSWORD}

Note: LITELLM_SALT_KEY cannot be changed after adding models to the proxy.
EOF
chmod 600 ~/litellm.creds
msg_ok "Saved credentials to ~/litellm.creds"

motd_ssh
customize
cleanup_lxc

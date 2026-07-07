#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# Co-Authors: MickLesk, tremor021 (prior pip/Prisma versions)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  python3-dev \
  libpq-dev \
  openssl \
  curl \
  gnupg \
  sudo
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="litellm" PG_DB_USER="litellm" setup_postgresql_db
PYTHON_VERSION="3.12" USE_UVX="YES" setup_uv

fetch_and_deploy_gh_release "litellm" "BerriAI/litellm" "tarball" "latest" "/opt/litellm"

# #region agent log
_debug_log() {
  local hid="$1" msg="$2" data="$3"
  printf '%s\n' "{\"sessionId\":\"691d2a\",\"runId\":\"post-fix\",\"hypothesisId\":\"${hid}\",\"location\":\"litellm-install.sh\",\"message\":\"${msg}\",\"data\":${data},\"timestamp\":$(date +%s%3N)}" >>/tmp/debug-691d2a.log
}
# #endregion

msg_info "Installing LiteLLM (Patience)"
cd /opt/litellm
$STD uv venv .venv
$STD uv pip install --python .venv/bin/python prisma
$STD uv pip install --python .venv/bin/python -e ".[proxy]"
msg_ok "Installed LiteLLM"

msg_info "Configuring LiteLLM"
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 16)"
LITELLM_SALT_KEY="sk-$(openssl rand -hex 16)"
DATABASE_URL="postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}"

cat <<EOF >/opt/litellm/litellm.yaml
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: ${DATABASE_URL}
  store_model_in_db: true
litellm_settings:
  salt_key: ${LITELLM_SALT_KEY}
EOF

export DATABASE_URL
# #region agent log
_debug_log "H2" "PATH before prisma generate" "{\"path\":\"${PATH}\",\"venv_prisma_client_py\":\"$([ -x /opt/litellm/.venv/bin/prisma-client-py ] && echo yes || echo no)\"}"
# #endregion
export PATH="/opt/litellm/.venv/bin:${PATH}"
# #region agent log
_debug_log "H4" "PATH after venv prepend" "{\"path\":\"${PATH}\"}"
# #endregion
$STD .venv/bin/prisma generate --schema=/opt/litellm/schema.prisma
_prisma_gen_rc=$?
# #region agent log
_debug_log "H4" "prisma generate finished" "{\"exit_code\":${_prisma_gen_rc}}"
# #endregion
[[ "${_prisma_gen_rc}" -eq 0 ]] || exit "${_prisma_gen_rc}"
$STD .venv/bin/litellm --config /opt/litellm/litellm.yaml --use_prisma_db_push --skip_server_startup
msg_ok "Configured LiteLLM"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/litellm.service
[Unit]
Description=LiteLLM Proxy
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/litellm
Environment=DATABASE_URL=${DATABASE_URL}
ExecStart=/opt/litellm/.venv/bin/litellm --config /opt/litellm/litellm.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now litellm
msg_ok "Created Service"

msg_info "Waiting for LiteLLM health check"
for i in $(seq 1 90); do
  if curl -sf "http://127.0.0.1:4000/health/liveliness" >/dev/null 2>&1; then
    msg_ok "LiteLLM is healthy"
    break
  fi
  if ! systemctl is-active --quiet litellm; then
    msg_error "LiteLLM service is not running — check: journalctl -u litellm -n 50"
    journalctl -u litellm -n 30 --no-pager 2>/dev/null
    exit 150
  fi
  sleep 2
  if [[ "$i" -eq 90 ]]; then
    msg_error "LiteLLM did not become healthy within 180s"
    journalctl -u litellm -n 30 --no-pager 2>/dev/null
    exit 150
  fi
done

cat <<EOF >~/litellm.creds
LiteLLM Credentials
URL: http://${LOCAL_IP}:4000
Master Key: ${LITELLM_MASTER_KEY}
Salt Key: ${LITELLM_SALT_KEY}
Postgres Password: ${PG_DB_PASS}

Note: LITELLM_SALT_KEY cannot be changed after adding models to the proxy.
EOF
chmod 600 ~/litellm.creds
msg_ok "Saved credentials to ~/litellm.creds"

motd_ssh
customize
cleanup_lxc

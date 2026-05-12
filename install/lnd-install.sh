#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Hiago Dutra (hiagopdutra)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/lightningnetwork/lnd

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

LND_DIR="/opt/lnd"
LND_DATA_DIR="${LND_DIR}/data"
LND_CONF="${LND_DIR}/lnd.conf"
RTL_DIR="/opt/rtl"
RTL_CONFIG="${RTL_DIR}/RTL-Config.json"
SCB_SCRIPT="/usr/local/bin/scb-backup"
SCB_ENV_FILE="/etc/lnd-scb-backup.env"
SCB_GIT_ASKPASS="/usr/local/bin/scb-git-askpass"

BITCOIN_NETWORK="${BITCOIN_NETWORK:-mainnet}"
LND_ALIAS="${LND_ALIAS:-$(hostname)}"
BITCOIND_RPC_HOST="${BITCOIND_RPC_HOST:-127.0.0.1}"
BITCOIND_RPC_PORT="${BITCOIND_RPC_PORT:-8332}"
BITCOIND_ZMQ_RAWBLOCK_PORT="${BITCOIND_ZMQ_RAWBLOCK_PORT:-28332}"
BITCOIND_ZMQ_RAWTX_PORT="${BITCOIND_ZMQ_RAWTX_PORT:-28333}"
BITCOIND_RPC_USER="${BITCOIND_RPC_USER:-bitcoin}"
BITCOIND_RPC_PASS="${BITCOIND_RPC_PASS:-}"
ENABLE_RTL="${ENABLE_RTL:-no}"
ENABLE_TOR="${ENABLE_TOR:-no}"
RTL_PASSWORD="${RTL_PASSWORD:-}"
ENABLE_SCB_BACKUP="${ENABLE_SCB_BACKUP:-no}"
SCB_BACKUP_MODE="${SCB_BACKUP_MODE:-local}"
SCB_BACKUP_DIR="${SCB_BACKUP_DIR:-/opt/lnd/backups}"
SCB_GIT_REMOTE_URL="${SCB_GIT_REMOTE_URL:-https://github.com/YOUR_USER/lnd-scb-backup.git}"
SCB_GIT_BRANCH="${SCB_GIT_BRANCH:-main}"
SCB_GIT_AUTH_METHOD="${SCB_GIT_AUTH_METHOD:-https}"
SCB_GIT_USERNAME="${SCB_GIT_USERNAME:-x-access-token}"
SCB_GIT_TOKEN="${SCB_GIT_TOKEN:-}"
SCB_GIT_COMMIT_NAME="${SCB_GIT_COMMIT_NAME:-LND SCB Backup}"
SCB_GIT_COMMIT_EMAIL="${SCB_GIT_COMMIT_EMAIL:-lnd@$(hostname)}"
SCB_GIT_SSH_KEY_PATH="${SCB_GIT_SSH_KEY_PATH:-/root/.ssh/lnd-scb-ed25519}"
SCB_GIT_KNOWN_HOSTS_FILE="${SCB_GIT_KNOWN_HOSTS_FILE:-/root/.ssh/known_hosts}"
SCB_GIT_SSH_HOST="${SCB_GIT_SSH_HOST:-}"
SCB_GIT_SSH_GENERATED="${SCB_GIT_SSH_GENERATED:-no}"

parse_git_host() {
  local remote_url="$1"
  if [[ "$remote_url" =~ ^https?://([^/@]+@)?([^/:]+) ]]; then
    printf "%s" "${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ ^ssh://([^/@]+@)?([^/:]+) ]]; then
    printf "%s" "${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ ^[^@]+@([^:]+): ]]; then
    printf "%s" "${BASH_REMATCH[1]}"
  fi
}

collect_install_settings() {
  stop_spinner
  echo
  echo -e "${INFO}${YW} Collecting LND configuration${CL}"

  read -r -p "${TAB3}LND alias [${LND_ALIAS}]: " prompt
  LND_ALIAS="${prompt:-$LND_ALIAS}"

  read -r -p "${TAB3}Bitcoin network [${BITCOIN_NETWORK}]: " prompt
  BITCOIN_NETWORK="${prompt:-$BITCOIN_NETWORK}"

  read -r -p "${TAB3}bitcoind RPC host [${BITCOIND_RPC_HOST}]: " prompt
  BITCOIND_RPC_HOST="${prompt:-$BITCOIND_RPC_HOST}"

  read -r -p "${TAB3}bitcoind RPC port [${BITCOIND_RPC_PORT}]: " prompt
  BITCOIND_RPC_PORT="${prompt:-$BITCOIND_RPC_PORT}"

  read -r -p "${TAB3}bitcoind ZMQ rawblock port [${BITCOIND_ZMQ_RAWBLOCK_PORT}]: " prompt
  BITCOIND_ZMQ_RAWBLOCK_PORT="${prompt:-$BITCOIND_ZMQ_RAWBLOCK_PORT}"

  read -r -p "${TAB3}bitcoind ZMQ rawtx port [${BITCOIND_ZMQ_RAWTX_PORT}]: " prompt
  BITCOIND_ZMQ_RAWTX_PORT="${prompt:-$BITCOIND_ZMQ_RAWTX_PORT}"

  read -r -p "${TAB3}bitcoind RPC user [${BITCOIND_RPC_USER}]: " prompt
  BITCOIND_RPC_USER="${prompt:-$BITCOIND_RPC_USER}"

  while [[ -z "$BITCOIND_RPC_PASS" ]]; do
    read -r -s -p "${TAB3}bitcoind RPC password: " BITCOIND_RPC_PASS
    echo
  done

  read -r -p "${TAB3}Install Static Channel Backup watcher? <y/N> " prompt
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    ENABLE_SCB_BACKUP="yes"
    read -r -p "${TAB3}Backup method [1=Git remote, 2=Local directory] [1]: " prompt
    case "${prompt:-1}" in
      2 | local | Local)
        SCB_BACKUP_MODE="local"
        read -r -p "${TAB3}Backup directory [${SCB_BACKUP_DIR}]: " prompt
        SCB_BACKUP_DIR="${prompt:-$SCB_BACKUP_DIR}"
        ;;
      *)
        SCB_BACKUP_MODE="git"
        read -r -p "${TAB3}Local working directory for git backups [${SCB_BACKUP_DIR}]: " prompt
        SCB_BACKUP_DIR="${prompt:-$SCB_BACKUP_DIR}"
        read -r -p "${TAB3}Git remote URL [${SCB_GIT_REMOTE_URL}]: " prompt
        SCB_GIT_REMOTE_URL="${prompt:-$SCB_GIT_REMOTE_URL}"
        read -r -p "${TAB3}Git branch [${SCB_GIT_BRANCH}]: " prompt
        SCB_GIT_BRANCH="${prompt:-$SCB_GIT_BRANCH}"
        read -r -p "${TAB3}Git commit name [${SCB_GIT_COMMIT_NAME}]: " prompt
        SCB_GIT_COMMIT_NAME="${prompt:-$SCB_GIT_COMMIT_NAME}"
        read -r -p "${TAB3}Git commit email [${SCB_GIT_COMMIT_EMAIL}]: " prompt
        SCB_GIT_COMMIT_EMAIL="${prompt:-$SCB_GIT_COMMIT_EMAIL}"
        read -r -p "${TAB3}Git auth method [1=HTTPS token, 2=SSH] [1]: " prompt
        case "${prompt:-1}" in
          2 | ssh | SSH)
            SCB_GIT_AUTH_METHOD="ssh"
            read -r -p "${TAB3}SSH private key path [${SCB_GIT_SSH_KEY_PATH}]: " prompt
            SCB_GIT_SSH_KEY_PATH="${prompt:-$SCB_GIT_SSH_KEY_PATH}"
            read -r -p "${TAB3}SSH host for known_hosts scan [$(parse_git_host "$SCB_GIT_REMOTE_URL")]: " prompt
            SCB_GIT_SSH_HOST="${prompt:-$(parse_git_host "$SCB_GIT_REMOTE_URL")}"
            if [[ ! -f "$SCB_GIT_SSH_KEY_PATH" ]]; then
              read -r -p "${TAB3}Generate a dedicated SSH key for SCB backup now? <y/N> " prompt
              [[ "${prompt,,}" =~ ^(y|yes)$ ]] && SCB_GIT_SSH_GENERATED="yes"
            fi
            ;;
          *)
            SCB_GIT_AUTH_METHOD="https"
            read -r -p "${TAB3}Git HTTPS username [${SCB_GIT_USERNAME}]: " prompt
            SCB_GIT_USERNAME="${prompt:-$SCB_GIT_USERNAME}"
            while [[ -z "$SCB_GIT_TOKEN" ]]; do
              read -r -s -p "${TAB3}Git HTTPS token / PAT: " SCB_GIT_TOKEN
              echo
            done
            ;;
        esac
        ;;
    esac
  fi

  read -r -p "${TAB3}Install RTL web UI? <y/N> " prompt
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    ENABLE_RTL="yes"
    while true; do
      read -r -s -p "${TAB3}RTL web password: " RTL_PASSWORD
      echo
      read -r -s -p "${TAB3}Confirm RTL web password: " rtl_password_confirm
      echo
      if [[ -n "$RTL_PASSWORD" && "$RTL_PASSWORD" == "$rtl_password_confirm" ]]; then
        break
      fi
      RTL_PASSWORD=""
      msg_warn "Passwords did not match, please try again"
    done
  fi

  read -r -p "${TAB3}Install Tor support? <y/N> " prompt
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    ENABLE_TOR="yes"
  fi
}

install_dependencies() {
  if [[ "$ENABLE_TOR" != "yes" && "$ENABLE_SCB_BACKUP" != "yes" ]]; then
    return 0
  fi
  msg_info "Installing Dependencies"
  if [[ "$ENABLE_TOR" == "yes" ]]; then
    $STD apt install -y tor
  fi
  if [[ "$ENABLE_SCB_BACKUP" == "yes" ]]; then
    $STD apt install -y \
      git \
      inotify-tools
    if [[ "$SCB_BACKUP_MODE" == "git" && "$SCB_GIT_AUTH_METHOD" == "ssh" ]]; then
      $STD apt install -y openssh-client
    fi
  fi
  msg_ok "Installed Dependencies"
}

install_lnd() {
  fetch_and_deploy_gh_release "lnd-app" "lightningnetwork/lnd" "prebuild" "latest" "${LND_DIR}" "lnd-linux-amd64-*.tar.gz"
  install -m 755 "${LND_DIR}/lnd" /usr/local/bin/lnd
  install -m 755 "${LND_DIR}/lncli" /usr/local/bin/lncli
}

configure_lnd_cli_access() {
  if [[ -f /root/.lnd && ! -L /root/.lnd ]]; then
    rm -f /root/.lnd
  fi
  ln -sfn "$LND_DIR" /root/.lnd
}

write_lnd_config() {
  local tor_block=""

  case "$BITCOIN_NETWORK" in
    mainnet | testnet | signet | regtest) ;;
    *)
      msg_error "Unsupported Bitcoin network: $BITCOIN_NETWORK"
      exit 1
      ;;
  esac

  mkdir -p "$LND_DATA_DIR" "$SCB_BACKUP_DIR"

  if [[ "$ENABLE_TOR" == "yes" ]]; then
    tor_block='
[tor]
tor.active=true
tor.v3=true
tor.streamisolation=true
tor.socks=127.0.0.1:9050
tor.control=127.0.0.1:9051'
  fi

  msg_info "Configuring LND"
  cat <<EOF >"$LND_CONF"
# community-scripts: lnd configuration

[Application Options]
alias=${LND_ALIAS}
debuglevel=info
listen=0.0.0.0:9735
rpclisten=127.0.0.1:10009
restlisten=127.0.0.1:8080
tlsextradomain=${LOCAL_IP}
tlsautorefresh=true

[Bitcoin]
bitcoin.active=true
bitcoin.${BITCOIN_NETWORK}=true
bitcoin.node=bitcoind

[Bitcoind]
bitcoind.rpchost=${BITCOIND_RPC_HOST}:${BITCOIND_RPC_PORT}
bitcoind.rpcuser=${BITCOIND_RPC_USER}
bitcoind.rpcpass=${BITCOIND_RPC_PASS}
bitcoind.zmqpubrawblock=tcp://${BITCOIND_RPC_HOST}:${BITCOIND_ZMQ_RAWBLOCK_PORT}
bitcoind.zmqpubrawtx=tcp://${BITCOIND_RPC_HOST}:${BITCOIND_ZMQ_RAWTX_PORT}
${tor_block}
EOF
  chmod 600 "$LND_CONF"
  msg_ok "Configured LND"
}

create_lnd_service() {
  local tor_unit_block=""

  if [[ "$ENABLE_TOR" == "yes" ]]; then
    tor_unit_block='After=network-online.target tor.service
Wants=network-online.target tor.service'
  else
    tor_unit_block='After=network-online.target
Wants=network-online.target'
  fi

  msg_info "Creating Service"
  cat <<EOF >/etc/systemd/system/lnd.service
[Unit]
Description=LND Lightning Network Daemon
${tor_unit_block}

[Service]
Type=simple
User=root
WorkingDirectory=${LND_DIR}
ExecStart=/usr/local/bin/lnd --configfile=${LND_CONF}
Restart=on-failure
RestartSec=5
TimeoutStopSec=60
LimitNOFILE=128000

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now lnd
  msg_ok "Created Service"
}

install_rtl() {
  [[ "$ENABLE_RTL" == "yes" ]] || return 0

  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "rtl" "Ride-The-Lightning/RTL" "tarball" "latest" "$RTL_DIR"

  msg_info "Building RTL"
  cd "$RTL_DIR"
  $STD npm ci --omit=dev --legacy-peer-deps
  msg_ok "Built RTL"

  msg_info "Configuring RTL"
  jq -n \
    --arg multiPass "$RTL_PASSWORD" \
    --arg macaroonPath "${LND_DATA_DIR}/chain/bitcoin/${BITCOIN_NETWORK}" \
    --arg configPath "$LND_CONF" \
    --arg channelBackupPath "$SCB_BACKUP_DIR" \
    '{
      multiPass: $multiPass,
      port: "3000",
      defaultNodeIndex: 1,
      dbDirectoryPath: "/opt/rtl",
      SSO: {
        rtlSSO: 0,
        rtlCookiePath: "",
        logoutRedirectLink: ""
      },
      nodes: [
        {
          index: 1,
          lnNode: "LND",
          lnImplementation: "LND",
          authentication: {
            macaroonPath: $macaroonPath,
            configPath: $configPath
          },
          settings: {
            userPersona: "OPERATOR",
            themeMode: "NIGHT",
            channelBackupPath: $channelBackupPath,
            logLevel: "ERROR",
            lnServerUrl: "https://127.0.0.1:8080",
            fiatConversion: false,
            unannouncedChannels: false,
            blockExplorerUrl: "https://mempool.space"
          }
        }
      ]
    }' >"$RTL_CONFIG"
  chmod 600 "$RTL_CONFIG"
  msg_ok "Configured RTL"

  msg_info "Creating RTL Service"
  cat <<EOF >/etc/systemd/system/rtl.service
[Unit]
Description=Ride The Lightning
After=lnd.service network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${RTL_DIR}
Environment=RTL_CONFIG_PATH=${RTL_DIR}
ExecStart=/usr/bin/node rtl
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q rtl
  msg_ok "Created RTL Service"
}

install_scb_backup() {
  [[ "$ENABLE_SCB_BACKUP" == "yes" ]] || return 0

  msg_info "Configuring SCB Backup"
  mkdir -p "$SCB_BACKUP_DIR"

  cat <<EOF >"$SCB_ENV_FILE"
SCB_BACKUP_MODE=${SCB_BACKUP_MODE@Q}
SCB_BACKUP_DIR=${SCB_BACKUP_DIR@Q}
SCB_GIT_REMOTE_URL=${SCB_GIT_REMOTE_URL@Q}
SCB_GIT_BRANCH=${SCB_GIT_BRANCH@Q}
SCB_GIT_AUTH_METHOD=${SCB_GIT_AUTH_METHOD@Q}
SCB_GIT_USERNAME=${SCB_GIT_USERNAME@Q}
SCB_GIT_TOKEN=${SCB_GIT_TOKEN@Q}
SCB_GIT_COMMIT_NAME=${SCB_GIT_COMMIT_NAME@Q}
SCB_GIT_COMMIT_EMAIL=${SCB_GIT_COMMIT_EMAIL@Q}
SCB_GIT_SSH_KEY_PATH=${SCB_GIT_SSH_KEY_PATH@Q}
SCB_GIT_KNOWN_HOSTS_FILE=${SCB_GIT_KNOWN_HOSTS_FILE@Q}
SCB_GIT_SSH_HOST=${SCB_GIT_SSH_HOST@Q}
SCB_GIT_ASKPASS=${SCB_GIT_ASKPASS@Q}
EOF
  chmod 600 "$SCB_ENV_FILE"

  if [[ "$SCB_BACKUP_MODE" == "git" && "$SCB_GIT_AUTH_METHOD" == "https" ]]; then
    cat <<'ASKPASS_EOF' >"$SCB_GIT_ASKPASS"
#!/usr/bin/env bash
case "$1" in
  *sername*) printf '%s\n' "${GIT_USERNAME:-x-access-token}" ;;
  *assword*) printf '%s\n' "${GIT_PASSWORD:-}" ;;
  *) printf '\n' ;;
esac
ASKPASS_EOF
    chmod 755 "$SCB_GIT_ASKPASS"
  fi

  if [[ "$SCB_BACKUP_MODE" == "git" && "$SCB_GIT_AUTH_METHOD" == "ssh" ]]; then
    local scb_ssh_dir
    scb_ssh_dir="$(dirname "$SCB_GIT_SSH_KEY_PATH")"
    msg_info "Preparing SCB Backup SSH Access"
    mkdir -p "$scb_ssh_dir"
    chmod 700 "$scb_ssh_dir"
    touch "$SCB_GIT_KNOWN_HOSTS_FILE"
    chmod 644 "$SCB_GIT_KNOWN_HOSTS_FILE"
    if [[ "$SCB_GIT_SSH_GENERATED" == "yes" && ! -f "$SCB_GIT_SSH_KEY_PATH" ]]; then
      ssh-keygen -q -t ed25519 -N "" -f "$SCB_GIT_SSH_KEY_PATH"
    fi
    if [[ -n "$SCB_GIT_SSH_HOST" ]]; then
      ssh-keyscan -H "$SCB_GIT_SSH_HOST" >>"$SCB_GIT_KNOWN_HOSTS_FILE" 2>/dev/null || true
    fi
    [[ -f "$SCB_GIT_SSH_KEY_PATH" ]] && chmod 600 "$SCB_GIT_SSH_KEY_PATH"
    chmod 644 "$SCB_GIT_KNOWN_HOSTS_FILE"
    msg_ok "Prepared SCB Backup SSH Access"
  fi

  cat <<SCB_SCRIPT_EOF >"$SCB_SCRIPT"
#!/usr/bin/env bash
set -euo pipefail

SCB_SOURCE_FILE="${LND_DATA_DIR}/chain/bitcoin/${BITCOIN_NETWORK}/channel.backup"
SCB_SOURCE_DIR="\$(dirname "\$SCB_SOURCE_FILE")"
LOCAL_BACKUP_DIR="${SCB_BACKUP_DIR}"
STATE_FILE="\${LOCAL_BACKUP_DIR}/.channel.backup.sha256"
SOURCE_MIRROR_DIR="\${LOCAL_BACKUP_DIR}/current"
SOURCE_MANIFEST_FILE="\${LOCAL_BACKUP_DIR}/.scb-source-manifest"
ENV_FILE="${SCB_ENV_FILE}"
SCB_EXPORT_FILE="${LND_DATA_DIR}/chain/bitcoin/${BITCOIN_NETWORK}/channel-all.bak"

[[ -f "\$ENV_FILE" ]] && source "\$ENV_FILE"

mkdir -p "\$LOCAL_BACKUP_DIR"

list_source_backup_files() {
  find "\$SCB_SOURCE_DIR" -maxdepth 1 -type f \( -name 'channel.backup' -o -name 'channel-all.bak' -o -name '*.backup' \) -print0 | sort -z
}

has_source_backup_files() {
  find "\$SCB_SOURCE_DIR" -maxdepth 1 -type f \( -name 'channel.backup' -o -name 'channel-all.bak' -o -name '*.backup' \) -print -quit | grep -q .
}

write_source_manifest() {
  : >"\$SOURCE_MANIFEST_FILE"
  while IFS= read -r -d '' source_file; do
    printf '%s %s\n' "\$(basename "\$source_file")" "\$(sha256sum "\$source_file" | awk '{print \$1}')" >>"\$SOURCE_MANIFEST_FILE"
  done < <(list_source_backup_files)
}

sync_source_backup_files() {
  mkdir -p "\$SOURCE_MIRROR_DIR"
  find "\$SOURCE_MIRROR_DIR" -maxdepth 1 -type f \( -name 'channel.backup' -o -name 'channel-all.bak' -o -name '*.backup' \) -delete
  while IFS= read -r -d '' source_file; do
    cp "\$source_file" "\$SOURCE_MIRROR_DIR/\$(basename "\$source_file")"
  done < <(list_source_backup_files)
}

init_git_repo() {
  [[ "\${SCB_BACKUP_MODE:-local}" == "git" ]] || return 0

  if ! git -C "\$LOCAL_BACKUP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "\$LOCAL_BACKUP_DIR" init -b "\${SCB_GIT_BRANCH}" >/dev/null 2>&1
  fi

  if git -C "\$LOCAL_BACKUP_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "\$LOCAL_BACKUP_DIR" remote set-url origin "\${SCB_GIT_REMOTE_URL}"
  else
    git -C "\$LOCAL_BACKUP_DIR" remote add origin "\${SCB_GIT_REMOTE_URL}"
  fi

  git -C "\$LOCAL_BACKUP_DIR" config user.name "\${SCB_GIT_COMMIT_NAME}"
  git -C "\$LOCAL_BACKUP_DIR" config user.email "\${SCB_GIT_COMMIT_EMAIL}"
  cat <<GITIGNORE_EOF >"\$LOCAL_BACKUP_DIR/.gitignore"
.channel.backup.sha256
.scb-source-manifest
GITIGNORE_EOF

  if [[ "\${SCB_GIT_AUTH_METHOD:-https}" == "ssh" ]]; then
    GIT_SSH_COMMAND="ssh -i \${SCB_GIT_SSH_KEY_PATH} -o IdentitiesOnly=yes -o UserKnownHostsFile=\${SCB_GIT_KNOWN_HOSTS_FILE} -o StrictHostKeyChecking=yes" \
      git -C "\$LOCAL_BACKUP_DIR" fetch --quiet origin "\${SCB_GIT_BRANCH}" >/dev/null 2>&1 || true
  else
    GIT_TERMINAL_PROMPT=0 \
      GIT_USERNAME="\${SCB_GIT_USERNAME:-x-access-token}" \
      GIT_PASSWORD="\${SCB_GIT_TOKEN:-}" \
      git -C "\$LOCAL_BACKUP_DIR" -c credential.helper= -c core.askPass="\${SCB_GIT_ASKPASS}" fetch --quiet origin "\${SCB_GIT_BRANCH}" >/dev/null 2>&1 || true
  fi

  if git -C "\$LOCAL_BACKUP_DIR" show-ref --verify --quiet "refs/remotes/origin/\${SCB_GIT_BRANCH}"; then
    git -C "\$LOCAL_BACKUP_DIR" checkout -B "\${SCB_GIT_BRANCH}" "origin/\${SCB_GIT_BRANCH}" >/dev/null 2>&1
  else
    git -C "\$LOCAL_BACKUP_DIR" checkout -B "\${SCB_GIT_BRANCH}" >/dev/null 2>&1
  fi
}

push_git_backup() {
  [[ "\${SCB_BACKUP_MODE:-local}" == "git" ]] || return 0

  init_git_repo
  git -C "\$LOCAL_BACKUP_DIR" add -A . >/dev/null 2>&1
  if git -C "\$LOCAL_BACKUP_DIR" diff --cached --quiet >/dev/null 2>&1; then
    return 0
  fi

  git -C "\$LOCAL_BACKUP_DIR" commit -m "SCB backup \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null

  if [[ "\${SCB_GIT_AUTH_METHOD:-https}" == "ssh" ]]; then
    GIT_SSH_COMMAND="ssh -i \${SCB_GIT_SSH_KEY_PATH} -o IdentitiesOnly=yes -o UserKnownHostsFile=\${SCB_GIT_KNOWN_HOSTS_FILE} -o StrictHostKeyChecking=yes" \
      git -C "\$LOCAL_BACKUP_DIR" push -u origin "\${SCB_GIT_BRANCH}" >/dev/null
  else
    GIT_TERMINAL_PROMPT=0 \
      GIT_USERNAME="\${SCB_GIT_USERNAME:-x-access-token}" \
      GIT_PASSWORD="\${SCB_GIT_TOKEN:-}" \
      git -C "\$LOCAL_BACKUP_DIR" -c credential.helper= -c core.askPass="\${SCB_GIT_ASKPASS}" push -u origin "\${SCB_GIT_BRANCH}" >/dev/null
  fi
}

backup_if_changed() {
  local current_hash previous_hash force_run="\${1:-no}"

  write_source_manifest
  current_hash=\$(sha256sum "\$SOURCE_MANIFEST_FILE" | awk '{print \$1}')
  previous_hash=\$(cat "\$STATE_FILE" 2>/dev/null || true)

  if [[ "\$force_run" == "yes" || "\$current_hash" != "\$previous_hash" ]]; then
    sync_source_backup_files
    if [[ -f "\$SCB_SOURCE_FILE" ]]; then
      cp "\$SCB_SOURCE_FILE" "\$LOCAL_BACKUP_DIR/channel.backup"
      cp "\$SCB_SOURCE_FILE" "\$LOCAL_BACKUP_DIR/channel-\$(date +%Y%m%d-%H%M%S).backup"
    else
      rm -f "\$LOCAL_BACKUP_DIR/channel.backup"
    fi
    if [[ -f "\$SCB_EXPORT_FILE" ]]; then
      cp "\$SCB_EXPORT_FILE" "\$LOCAL_BACKUP_DIR/channel-all.bak"
    else
      rm -f "\$LOCAL_BACKUP_DIR/channel-all.bak"
    fi
    printf '%s\n' "\$current_hash" >"\$STATE_FILE"
    push_git_backup
  fi
}

run_self_test() {
  if ! has_source_backup_files; then
    echo "SCB self-test failed: no backup-like files found in \$SCB_SOURCE_DIR" >&2
    exit 1
  fi

  init_git_repo
  backup_if_changed yes
  echo "SCB self-test completed: forced backup sync created from \$SCB_SOURCE_DIR"
}

if [[ "\${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

init_git_repo
backup_if_changed

while true; do
  mkdir -p "\$SCB_SOURCE_DIR"
  inotifywait -q -e close_write,create,move,delete "\$SCB_SOURCE_DIR" >/dev/null 2>&1 || {
    sleep 2
    continue
  }
  backup_if_changed
done
SCB_SCRIPT_EOF
  chmod 755 "$SCB_SCRIPT"

  cat <<EOF >/etc/systemd/system/scb-backup.service
[Unit]
Description=SCB Backup daemon
After=lnd.service
Requires=lnd.service

[Service]
ExecStart=${SCB_SCRIPT}
Restart=always
RestartSec=2
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now scb-backup.service
  msg_ok "Configured SCB Backup"
}

configure_tor() {
  [[ "$ENABLE_TOR" == "yes" ]] || return 0

  msg_info "Configuring Tor"
  grep -q '^ControlPort 9051$' /etc/tor/torrc 2>/dev/null || cat <<EOF >>/etc/tor/torrc

# community-scripts: lnd tor control
ControlPort 9051
CookieAuthentication 1
CookieAuthFileGroupReadable 1
EOF
  mkdir -p /etc/systemd/system/tor@default.service.d
  cat <<EOF >/etc/systemd/system/tor@default.service.d/override.conf
[Service]
AppArmorProfile=
EOF
  systemctl daemon-reload
  systemctl enable -q tor.service
  systemctl restart tor.service
  for _ in {1..30}; do
    if ss -ltn '( sport = :9051 )' 2>/dev/null | grep -q 9051; then
      msg_ok "Configured Tor"
      return 0
    fi
    sleep 1
  done
  systemctl status tor@default.service --no-pager || true
  journalctl -u tor@default.service -n 50 --no-pager || true
  msg_error "Tor control port 9051 did not become ready"
  exit 1
}

show_post_install_notes() {
  echo
  echo -e "${INFO}${YW} Next steps:${CL}"
  echo -e "${TAB}1. Run ${BGN}lncli create${CL} to create the wallet."
  echo -e "${TAB}2. LND config: ${BGN}${LND_CONF}${CL}"
  if [[ "$ENABLE_RTL" == "yes" ]]; then
    echo -e "${TAB}3. RTL URL: ${BGN}http://${LOCAL_IP}:3000${CL}"
    echo -e "${TAB}4. Start RTL after the wallet and macaroon exist: ${BGN}systemctl start rtl${CL}"
  fi
  if [[ "$ENABLE_SCB_BACKUP" == "yes" ]]; then
    if [[ "$SCB_BACKUP_MODE" == "git" ]]; then
      echo -e "${TAB}5. Static channel backups are versioned in ${BGN}${SCB_BACKUP_DIR}${CL} and pushed to ${BGN}${SCB_GIT_REMOTE_URL}${CL}."
      if [[ "$SCB_GIT_AUTH_METHOD" == "ssh" && "$SCB_GIT_SSH_GENERATED" == "yes" ]]; then
        echo -e "${TAB}6. Register the generated public key before the first SSH push: ${BGN}${SCB_GIT_SSH_KEY_PATH}.pub${CL}"
      fi
    else
      echo -e "${TAB}5. Static channel backups are copied to ${BGN}${SCB_BACKUP_DIR}${CL}."
    fi
  fi
}

collect_install_settings
install_dependencies
install_lnd
configure_lnd_cli_access
write_lnd_config
configure_tor
create_lnd_service
install_scb_backup
install_rtl
show_post_install_notes

motd_ssh
customize
cleanup_lxc

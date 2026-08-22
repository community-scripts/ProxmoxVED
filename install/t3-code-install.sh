#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: lukdz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://t3.codes/ | Github: https://github.com/pingdotgg/t3code

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

t3_user="t3"
t3_home="/home/${t3_user}"
var_t3_providers="${var_t3_providers:-}"
var_t3_providers="${var_t3_providers//[[:space:]]/}"
var_t3_version_control="${var_t3_version_control:-git}"
var_t3_version_control="${var_t3_version_control//[[:space:]]/}"
var_t3_source_control="${var_t3_source_control:-none}"
var_t3_source_control="${var_t3_source_control//[[:space:]]/}"

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  python3 \
  dbus \
  dbus-user-session \
  libpam-systemd
msg_ok "Installed Dependencies"

if [[ ",${var_t3_version_control,,}," == *,git,* ]]; then
  msg_info "Installing Git"
  $STD apt-get install -y git
  msg_ok "Installed Git"
fi

NODE_VERSION="24" setup_nodejs

msg_info "Creating T3 User"
if ! id "$t3_user" >/dev/null 2>&1; then
  $STD useradd --create-home --user-group --home-dir "$t3_home" --shell /bin/bash "$t3_user"
fi
# T3 can execute provider agent commands, so keep its server and project work non-root.
$STD passwd --lock "$t3_user"
$STD chmod 750 "$t3_home"
if ! grep -q '^export XDG_RUNTIME_DIR=' "$t3_home/.profile" 2>/dev/null; then
  cat <<'EOF' >>"$t3_home/.profile"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
EOF
fi
if ! grep -q '^export PATH=' "$t3_home/.profile" 2>/dev/null; then
  cat <<'EOF' >>"$t3_home/.profile"
export PATH="$HOME/.local/bin:$PATH"
EOF
fi
if ! grep -q '^export NPM_CONFIG_PREFIX=' "$t3_home/.profile" 2>/dev/null; then
  cat <<'EOF' >>"$t3_home/.profile"
export NPM_CONFIG_PREFIX="$HOME/.local"
EOF
fi
chown "$t3_user:$t3_user" "$t3_home/.profile"
chmod 640 "$t3_home/.profile"
msg_ok "Created T3 User"

t3_uid="$(id -u "$t3_user")"

msg_info "Preparing T3 User Service"
$STD systemctl start systemd-logind.service
$STD loginctl enable-linger "$t3_user"
$STD systemctl start "user-runtime-dir@${t3_uid}.service" "user@${t3_uid}.service"
for _ in {1..30}; do
  [[ -S "/run/user/${t3_uid}/bus" ]] && break
  sleep 1
done
if [[ ! -S "/run/user/${t3_uid}/bus" ]]; then
  msg_error "The T3 user service bus is unavailable. Ensure systemd user services are supported by this LXC."
  exit 1
fi
msg_ok "Prepared T3 User Service"

t3_exec() {
  $STD runuser --user "$t3_user" -- env \
    HOME="$t3_home" \
    USER="$t3_user" \
    LOGNAME="$t3_user" \
    SHELL=/bin/bash \
    PATH="$t3_home/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    XDG_RUNTIME_DIR="/run/user/${t3_uid}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${t3_uid}/bus" \
    NPM_CONFIG_PREFIX="$t3_home/.local" \
    NPM_CONFIG_CACHE="$t3_home/.cache/npm" \
    "$@"
}

fix_resource_monitor_permissions() {
  local monitor
  t3_resource_monitor_repaired=0
  for monitor in "$t3_home"/.t3/runtime/versions/*/node_modules/t3/dist/resource-monitor/linux-*/t3-resource-monitor; do
    [[ -f "$monitor" ]] || continue
    if [[ ! -x "$monitor" ]]; then
      chmod 755 "$monitor"
      t3_resource_monitor_repaired=1
    fi
  done
}

provider_selected() {
  local provider="${1,,}"
  local selected=",${var_t3_providers,,},"
  [[ "$selected" == *",${provider},"* ]]
}

install_npm_provider() {
  local label="$1"
  local package="$2"
  msg_info "Installing ${label}"
  t3_exec /usr/bin/npm install --global --prefix "$t3_home/.local" \
    --allow-scripts="$package" "${package}@latest"
  msg_ok "Installed ${label}"
}

install_selected_providers() {
  t3_providers_installed=0
  [[ -n "${var_t3_providers:-}" && "${var_t3_providers,,}" != "none" ]] || return 0

  if provider_selected codex; then
    install_npm_provider "Codex CLI" "@openai/codex"
    t3_providers_installed=1
  fi

  if provider_selected claude; then
    setup_deb822_repo "claude-code" \
      "https://downloads.claude.ai/keys/claude-code.asc" \
      "https://downloads.claude.ai/claude-code/apt/stable" \
      "stable" "main"
    msg_info "Installing Claude Code CLI"
    $STD apt-get install -y claude-code
    msg_ok "Installed Claude Code CLI"
    t3_providers_installed=1
  fi

  if provider_selected cursor; then
    msg_info "Installing Cursor Agent CLI"
    t3_exec /bin/bash -c 'set -o pipefail; curl -fsSL https://cursor.com/install | bash'
    msg_ok "Installed Cursor Agent CLI"
    t3_providers_installed=1
  fi

  if provider_selected grok; then
    install_npm_provider "Grok Build CLI" "@xai-official/grok"
    t3_providers_installed=1
  fi
  if provider_selected opencode; then
    install_npm_provider "OpenCode CLI" "opencode-ai"
    t3_providers_installed=1
  fi
}

source_control_selected() {
  local provider="${1,,}"
  local selected=",${var_t3_source_control,,},"
  [[ "$selected" == *",${provider},"* ]]
}

install_gitlab_cli() {
  local arch="$(dpkg --print-architecture)"
  local release_url="https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest"
  local package_url
  package_url=$(curl -fsSL --retry 3 --retry-connrefused --connect-timeout 10 --max-time 30 "$release_url" |
    jq -r --arg arch "$arch" '
      (.tag_name | ltrimstr("v")) as $version |
      .assets.links[] |
      select(.name == ("glab_" + $version + "_linux_" + $arch + ".deb")) |
      .url' | head -n 1)
  [[ -n "$package_url" && "$package_url" != "null" ]] || {
    msg_error "Could not find a GitLab CLI package for ${arch}."
    return 1
  }

  local package_file
  package_file=$(mktemp --suffix=.deb)
  msg_info "Installing GitLab CLI"
  if ! curl -fsSL --retry 3 --retry-connrefused --connect-timeout 10 --max-time 120 "$package_url" -o "$package_file"; then
    rm -f "$package_file"
    msg_error "Failed to download GitLab CLI."
    return 1
  fi
  if ! $STD dpkg -i "$package_file"; then
    $STD apt-get install -f -y
  fi
  rm -f "$package_file"
  command -v glab >/dev/null 2>&1 || {
    msg_error "GitLab CLI installation did not provide glab."
    return 1
  }
  msg_ok "Installed GitLab CLI"
}

configure_bitbucket_environment() {
  local env_dir="/etc/t3-code"
  local env_file="${env_dir}/source-control.env"
  mkdir -p "$env_dir"
  if [[ ! -f "$env_file" ]]; then
    cat <<'EOF' >"$env_file"
# Bitbucket credentials for T3 Code. Set either the access token, or the
# email/API-token pair, then restart the T3 Code user service.
# T3CODE_BITBUCKET_ACCESS_TOKEN=
# T3CODE_BITBUCKET_EMAIL=
# T3CODE_BITBUCKET_API_TOKEN=
EOF
  fi
  chown root:"$t3_user" "$env_file"
  chmod 640 "$env_file"

  mkdir -p "$t3_home/.config/systemd/user/t3code.service.d"
  cat <<EOF >"$t3_home/.config/systemd/user/t3code.service.d/20-source-control.conf"
[Service]
EnvironmentFile=-${env_file}
EOF
  chown "$t3_user:$t3_user" \
    "$t3_home/.config/systemd/user/t3code.service.d" \
    "$t3_home/.config/systemd/user/t3code.service.d/20-source-control.conf"
}

install_source_control_tools() {
  t3_source_control_configured=0
  [[ -n "${var_t3_source_control:-}" && "${var_t3_source_control,,}" != "none" ]] || return 0

  if source_control_selected github; then
    setup_deb822_repo "github-cli" \
      "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
      "https://cli.github.com/packages" \
      "stable" "main" "$(dpkg --print-architecture)"
    msg_info "Installing GitHub CLI"
    $STD apt-get install -y gh
    msg_ok "Installed GitHub CLI"
    t3_source_control_configured=1
  fi

  if source_control_selected gitlab; then
    install_gitlab_cli
    t3_source_control_configured=1
  fi

  if source_control_selected azure; then
    setup_deb822_repo "azure-cli" \
      "https://packages.microsoft.com/keys/microsoft.asc" \
      "https://packages.microsoft.com/repos/azure-cli/" \
      "bookworm" "main" "$(dpkg --print-architecture)"
    msg_info "Installing Azure CLI"
    $STD apt-get install -y azure-cli
    msg_ok "Installed Azure CLI"
    msg_info "Installing Azure DevOps extension"
    t3_exec /usr/bin/az extension add --name azure-devops
    msg_ok "Installed Azure DevOps extension"
    t3_source_control_configured=1
  fi

  if source_control_selected bitbucket; then
    configure_bitbucket_environment
    msg_ok "Prepared Bitbucket environment configuration"
    t3_source_control_configured=1
  fi
}

show_provider_login_commands() {
  [[ "${t3_providers_installed:-0}" -eq 1 ]] || return 0

  stop_spinner
  echo
  echo -e "${INFO}${BOLD}${DGN}Provider Authentication${CL}"
  echo
  echo -e "${TAB}${YW}Selected provider CLIs are installed but not authenticated. Run these commands from the Proxmox host:${CL}"
  echo -e "${TAB}${YW}After authentication, enable Cursor, Grok and OpenCode in T3 Code Settings if you selected them.${CL}"
  echo -e "${TAB}${YW}Authentication commands may open a browser or require terminal input.${CL}"
  provider_selected codex && echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'codex login'${CL}"
  provider_selected claude && echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'claude auth login'${CL}"
  provider_selected cursor && echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'agent login'${CL}"
  provider_selected grok && echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'grok login'${CL}"
  provider_selected opencode && echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'opencode auth login'${CL}"
  msg_ok "Provider Authentication Instructions"
}

show_source_control_login_commands() {
  [[ "${t3_source_control_configured:-0}" -eq 1 ]] || return 0

  stop_spinner
  echo
  echo -e "${INFO}${BOLD}${DGN}Source Control Authentication${CL}"
  echo
  echo -e "${TAB}${YW}Selected source-control integrations are installed or prepared but not authenticated. Run these commands from the Proxmox host:${CL}"
  echo -e "${TAB}${YW}Authentication is performed as the t3 user and is never done automatically.${CL}"
  source_control_selected github && echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'gh auth login'${CL}"
  source_control_selected gitlab && echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'glab auth login'${CL}"
  source_control_selected azure && echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'az login'${CL}"
  if source_control_selected bitbucket; then
    echo -e "${TAB}${YW}Edit /etc/t3-code/source-control.env in CT ${CTID} and set either:${CL}"
    echo -e "${TAB}${YW}T3CODE_BITBUCKET_ACCESS_TOKEN=your-access-token${CL}"
    echo -e "${TAB}${YW}or T3CODE_BITBUCKET_EMAIL and T3CODE_BITBUCKET_API_TOKEN.${CL}"
    echo -e "${TAB}${YW}Then restart T3 Code:${CL}"
    echo -e "${TAB}${BGN}pct exec ${CTID} -- su - t3 -c 'systemctl --user restart t3code.service'${CL}"
  fi
  msg_ok "Source Control Authentication Instructions"
}

finish_t3_service_setup() {
  local expected_version="${1:-}"
  local installed_version

  $STD loginctl enable-linger "$t3_user"
  if [[ ! -f "$t3_home/.config/systemd/user/t3code.service" ||
    ! -f "$t3_home/.t3/runtime/service-launcher.mjs" ||
    ! -f "$t3_home/.t3/runtime/service-state.json" ]]; then
    return 1
  fi

  installed_version=$(jq -r '.activeVersion // empty' "$t3_home/.t3/runtime/service-state.json" 2>/dev/null || true)
  [[ "$installed_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ -z "$expected_version" || "$installed_version" == "$expected_version" ]] || return 1
  [[ -f "$t3_home/.t3/runtime/versions/${installed_version}/node_modules/t3/dist/bin.mjs" ]] || return 1
  [[ -f "$t3_home/.t3/runtime/versions/${installed_version}/.install-complete" ]] || return 1

  t3_exec /usr/bin/systemctl --user daemon-reload
  t3_exec /usr/bin/systemctl --user enable t3code.service
}

msg_info "Installing T3 Code"
if ! t3_exec /usr/bin/npx --yes t3@latest service install; then
  msg_warn "T3 could not enable lingering from the unprivileged user; completing service setup as root."
  if ! finish_t3_service_setup; then
    msg_error "T3 Code service installation failed"
    exit 1
  fi
fi
msg_ok "Installed T3 Code"
fix_resource_monitor_permissions
if [[ "$t3_resource_monitor_repaired" -eq 1 ]]; then
  msg_ok "Repaired T3 resource monitor permissions"
fi

msg_info "Configuring Network Access"
mkdir -p "$t3_home/.config/systemd/user/t3code.service.d"
cat <<EOF >"$t3_home/.config/systemd/user/t3code.service.d/10-network.conf"
[Service]
Environment=HOME=${t3_home}
Environment=PATH=${t3_home}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=NPM_CONFIG_PREFIX=${t3_home}/.local
Environment=T3CODE_HOST=0.0.0.0
Environment=T3CODE_PORT=3773
EOF
chown "$t3_user:$t3_user" \
  "$t3_home/.config/systemd/user/t3code.service.d" \
  "$t3_home/.config/systemd/user/t3code.service.d/10-network.conf"
t3_exec /usr/bin/systemctl --user daemon-reload
t3_exec /usr/bin/systemctl --user restart t3code.service
if ! t3_exec /usr/bin/systemctl --user is-active --quiet t3code.service; then
  msg_error "T3 Code service failed to start"
  exit 1
fi
msg_ok "Configured Network Access"

install_selected_providers
install_source_control_tools
if [[ "${t3_providers_installed:-0}" -eq 1 || "${t3_source_control_configured:-0}" -eq 1 ]]; then
  msg_info "Refreshing T3 Integration Status"
  t3_exec /usr/bin/systemctl --user restart t3code.service
  msg_ok "Refreshed T3 Integration Status"
fi

t3_version=$(jq -r '.activeVersion // empty' "$t3_home/.t3/runtime/service-state.json" 2>/dev/null || true)
if [[ ! "$t3_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  msg_error "Unable to determine the installed T3 Code version."
  exit 1
fi
cat <<EOF >/root/.t3-code
${t3_version}
EOF

msg_info "Generating Pairing URL"
t3_pair_output=""
for _ in {1..30}; do
  if t3_pair_output=$(STD="" t3_exec /usr/bin/npx --yes "t3@${t3_version}" pair --base-dir "$t3_home/.t3" --ttl 1h 2>/dev/null); then
    stop_spinner
    clear_line
    echo -e "${INFO}${YW}Generating Pairing URL${CL}"
    printf '%s\n' "$t3_pair_output"
    break
  fi
  sleep 1
done
if [[ -z "$t3_pair_output" ]]; then
  msg_warn "Could not generate a pairing URL automatically. Run this inside the container as the t3 user: npx --yes t3@${t3_version} pair --base-dir ${t3_home}/.t3 --ttl 1h"
fi

show_provider_login_commands
show_source_control_login_commands

motd_ssh
customize
cleanup_lxc

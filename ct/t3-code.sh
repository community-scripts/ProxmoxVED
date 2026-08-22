#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: lukdz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://t3.codes/ | Github: https://github.com/pingdotgg/t3code

APP="T3-Code"
var_tags="${var_tags:-ai;coding}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

t3_user="t3"
t3_home="/home/${t3_user}"

header_info "$APP"
variables
color
catch_errors

t3_provider_menu() {
  if [[ "${PHS_SILENT:-0}" == "1" || -n "${var_t3_providers:-}" ]]; then
    var_t3_providers="${var_t3_providers//[[:space:]]/}"
    export var_t3_providers
    return
  fi

  if command -v pveversion >/dev/null 2>&1; then
    ensure_whiptail
    var_t3_providers=$(whiptail \
      --backtitle "Proxmox VE Helper Scripts" \
      --title "T3 Code Providers" \
      --ok-button "Continue" \
      --cancel-button "Skip Providers" \
      --separate-output \
      --checklist "\nSelect provider CLIs to install for the t3 user.\n\nUse Space to toggle and Enter to continue.\nNo providers are selected by default. Authentication is not performed." \
      20 86 5 \
      codex "OpenAI Codex CLI" off \
      claude "Claude Code CLI" off \
      cursor "Cursor Agent CLI" off \
      grok "Grok Build CLI" off \
      opencode "OpenCode CLI" off \
      3>&1 1>&2 2>&3) || var_t3_providers=""
  fi

  var_t3_providers="${var_t3_providers//$'\n'/,}"
  var_t3_providers="${var_t3_providers//[[:space:]]/}"
  var_t3_providers="${var_t3_providers%,}"
  export var_t3_providers
}

t3_version_control_menu() {
  if [[ "${PHS_SILENT:-0}" == "1" || -n "${var_t3_version_control+x}" ]]; then
    var_t3_version_control="${var_t3_version_control:-git}"
    var_t3_version_control="${var_t3_version_control//[[:space:]]/}"
    export var_t3_version_control
    return
  fi

  if command -v pveversion >/dev/null 2>&1; then
    ensure_whiptail
    var_t3_version_control=$(whiptail \
      --backtitle "Proxmox VE Helper Scripts" \
      --title "T3 Code Version Control" \
      --ok-button "Continue" \
      --cancel-button "Skip Version Control" \
      --separate-output \
      --checklist "\nSelect version-control tools to install for the t3 user.\n\nUse Space to toggle and Enter to continue.\nGit is selected by default.\n\nJujutsu: Coming Soon" \
      16 86 1 \
      git "Git" on \
      3>&1 1>&2 2>&3) || var_t3_version_control=""
  fi

  var_t3_version_control="${var_t3_version_control//$'\n'/,}"
  var_t3_version_control="${var_t3_version_control//[[:space:]]/}"
  var_t3_version_control="${var_t3_version_control%,}"
  [[ -z "$var_t3_version_control" ]] && var_t3_version_control="none"
  export var_t3_version_control
}

t3_source_control_menu() {
  if [[ "${PHS_SILENT:-0}" == "1" || -n "${var_t3_source_control+x}" ]]; then
    var_t3_source_control="${var_t3_source_control:-none}"
    var_t3_source_control="${var_t3_source_control//[[:space:]]/}"
    export var_t3_source_control
    return
  fi

  if command -v pveversion >/dev/null 2>&1; then
    ensure_whiptail
    var_t3_source_control=$(whiptail \
      --backtitle "Proxmox VE Helper Scripts" \
      --title "T3 Code Source Control Providers" \
      --ok-button "Continue" \
      --cancel-button "Skip Source Control" \
      --separate-output \
      --checklist "\nSelect source-control integrations to install or configure for the t3 user.\n\nUse Space to toggle and Enter to continue.\nNo integrations are selected by default.\n\nGitHub: installs the gh CLI.\nGitLab: installs the glab CLI.\nAzure DevOps: installs az and its DevOps extension.\nBitbucket: uses API-token environment variables, not a CLI." \
      20 86 4 \
      github "Not available - install gh CLI" off \
      gitlab "Not available - install glab CLI" off \
      azure "Not available - install az + DevOps extension" off \
      bitbucket "Not authenticated - configure API token" off \
      3>&1 1>&2 2>&3) || var_t3_source_control=""
  fi

  var_t3_source_control="${var_t3_source_control//$'\n'/,}"
  var_t3_source_control="${var_t3_source_control//[[:space:]]/}"
  var_t3_source_control="${var_t3_source_control%,}"
  [[ -z "$var_t3_source_control" ]] && var_t3_source_control="none"
  export var_t3_source_control
}

t3_summary_list() {
  local raw="${1:-}"
  [[ -z "$raw" || "$raw" == "none" ]] && {
    printf 'none'
    return
  }

  local -a items=()
  local item label separator=""
  IFS=',' read -r -a items <<<"$raw"
  for item in "${items[@]}"; do
    case "$item" in
    git) label="Git" ;;
    github) label="GitHub" ;;
    gitlab) label="GitLab" ;;
    azure) label="Azure DevOps" ;;
    bitbucket) label="Bitbucket" ;;
    codex) label="Codex" ;;
    claude) label="Claude" ;;
    cursor) label="Cursor" ;;
    grok) label="Grok" ;;
    opencode) label="OpenCode" ;;
    *) label="$item" ;;
    esac
    printf '%s%s' "$separator" "$label"
    separator=', '
  done
}

t3_append_summary() {
  local t3_summary_version_control
  local t3_summary_source_control
  local t3_summary_providers

  t3_summary_version_control="$(t3_summary_list "${var_t3_version_control:-none}")"
  t3_summary_source_control="$(t3_summary_list "${var_t3_source_control:-none}")"
  t3_summary_providers="$(t3_summary_list "${var_t3_providers:-none}")"
  summary="${summary}

Dependencies:
  Version Control: ${t3_summary_version_control}
  Source Control: ${t3_summary_source_control}
  Agent CLIs: ${t3_summary_providers}"
}

# The shared engine owns the Advanced wizard. Insert the app-specific prompt
# after the final settings step, before its confirmation dialog.
eval "$(declare -f advanced_settings |
  sed 's/^advanced_settings ()/_t3_advanced_settings ()/' |
  sed '/^[[:space:]]*local ct_type_desc=/i\
      t3_version_control_menu\
      t3_source_control_menu\
      t3_provider_menu' |
  sed '/^[[:space:]]*if whiptail .*CONFIRM SETTINGS/i\
      t3_append_summary\
')"
advanced_settings() {
  _t3_advanced_settings "$@"
}

t3_exec() {
  $STD runuser --user "$t3_user" -- env \
    HOME="$t3_home" \
    USER="$t3_user" \
    LOGNAME="$t3_user" \
    SHELL=/bin/bash \
    PATH="$t3_home/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    XDG_RUNTIME_DIR="/run/user/${t3_uid}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${t3_uid}/bus" \
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

sync_t3_version() {
  local version
  version=$(jq -r '.activeVersion // empty' "$t3_home/.t3/runtime/service-state.json" 2>/dev/null || true)
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    msg_error "Unable to determine the installed T3 Code version."
    exit 1
  fi
  cat <<EOF >/root/.t3-code
${version}
EOF
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! id "$t3_user" >/dev/null 2>&1 || [[ ! -f "$t3_home/.config/systemd/user/t3code.service" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  t3_uid="$(id -u "$t3_user")"
  fix_resource_monitor_permissions

  if check_for_gh_release "t3-code" "pingdotgg/t3code"; then
    NODE_VERSION="24" setup_nodejs

    msg_info "Updating ${APP}"
    if ! t3_exec /usr/bin/npx --yes "t3@${CHECK_UPDATE_RELEASE#v}" service update; then
      msg_warn "T3 could not enable lingering from the unprivileged user; completing service setup as root."
      if ! finish_t3_service_setup "${CHECK_UPDATE_RELEASE#v}"; then
        msg_error "T3 Code service update failed"
        exit 1
      fi
    fi
    fix_resource_monitor_permissions
    t3_exec /usr/bin/systemctl --user restart t3code.service
    sync_t3_version
    msg_ok "Updated ${APP}"

    if ! t3_exec /usr/bin/systemctl --user is-active --quiet t3code.service; then
      msg_error "${APP} service failed to start"
      exit 1
    fi
    msg_ok "Updated successfully!"
  elif [[ "$t3_resource_monitor_repaired" -eq 1 ]]; then
    msg_info "Restarting ${APP} after resource monitor repair"
    t3_exec /usr/bin/systemctl --user restart t3code.service
    msg_ok "Restarted ${APP}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3773${CL}"
echo -e "${INFO}${YW}A one-time pairing URL with a one-hour lifetime is printed during installation.${CL}"
echo -e "${INFO}${YW}To generate another one inside the container as the t3 user:${CL}"
echo -e "${TAB}${BGN}npx --yes t3@latest pair --base-dir /home/t3/.t3 --ttl 1h${CL}"
echo -e "${INFO}${YW}If providers or source-control integrations were selected, use the authentication commands printed during installation.${CL}"

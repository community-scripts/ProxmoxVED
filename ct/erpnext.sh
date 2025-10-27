#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: JamesonRGrieve
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/frappe/erpnext

# App Default Values
APP="ERPNext"
var_tags="${var_tags:-erp;frappe}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-60}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

prompt_input() {
  local __result_var="$1"
  local __title="$2"
  local __prompt="$3"
  local __default="$4"
  local __allow_empty="${5:-0}"
  local __value

  while true; do
    __value=$(whiptail --title "$__title" --inputbox "$__prompt" 10 70 "$__default" 3>&1 1>&2 2>&3) || exit_script
    if [[ -n "$__value" || "$__allow_empty" -eq 1 ]]; then
      printf -v "$__result_var" '%s' "$__value"
      return 0
    fi
    whiptail --title "$APP" --msgbox "Input cannot be empty." 8 50
  done
}

prompt_password() {
  local __result_var="$1"
  local __title="$2"
  local __prompt="$3"
  local __allow_empty="${4:-0}"
  local __password

  while true; do
    __password=$(whiptail --title "$__title" --passwordbox "$__prompt" 10 70 3>&1 1>&2 2>&3) || exit_script
    if [[ -n "$__password" || "$__allow_empty" -eq 1 ]]; then
      printf -v "$__result_var" '%s' "$__password"
      return 0
    fi
    whiptail --title "$APP" --msgbox "Password cannot be empty." 8 55
  done
}

collect_lxc_ids() {
    command -v pct >/dev/null 2>&1 || return 0
    pct list 2>/dev/null | awk 'NR>1 {print $1}' | sort -n
}

verify_tcp_endpoint() {
    local __host="$1"
    local __port="$2"
    local __label="$3"
    local __attempts="${4:-1}"
    local __delay="${5:-5}"
    local __attempt
    local __logged_wait=0

    if (( __attempts > 1 )); then
        msg_info "Waiting for ${__label} at ${__host}:${__port}"
        __logged_wait=1
    fi

    for ((__attempt = 1; __attempt <= __attempts; __attempt++)); do
        if timeout 5 bash -c "</dev/tcp/${__host}/${__port}" &>/dev/null; then
            if (( __logged_wait == 1 )); then
                msg_ok "${__label} is reachable at ${__host}:${__port}"
            fi
            return 0
        fi
        if ((__attempt < __attempts)); then
            sleep "${__delay}"
        fi
    done

    if (( __logged_wait == 1 )); then
        msg_warn "${__label} is still unreachable at ${__host}:${__port}"
    fi

  if whiptail --title "$APP" --yesno "Unable to connect to ${__label} at ${__host}:${__port}.\n\nChoose <Yes> to re-enter the connection details or <No> to continue anyway." 11 70; then
    return 1
  fi

  return 0
}

configure_mariadb_remote_access() {
    local __ctid="$1"
    local __allow_host="$2"
    local __admin_user="$3"
    local __admin_password="$4"

    [[ -n "${__ctid}" ]] || return 0

    if ! command -v pct >/dev/null 2>&1; then
        msg_warn "pct command not available; skipping MariaDB remote access adjustments."
        return 0
    fi

    msg_info "Configuring MariaDB CT ${__ctid} for remote access (${__admin_user}@${__allow_host})"

    if ! pct exec "${__ctid}" -- env SQL_USER="${__admin_user}" SQL_PASS="${__admin_password}" SQL_ALLOW="${__allow_host}" bash -s <<'EOF'
set -e
CONFIG_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [ -f "$CONFIG_FILE" ]; then
  if grep -qE '^[[:space:]]*bind-address' "$CONFIG_FILE"; then
    sed -i 's/^[[:space:]]*bind-address.*/bind-address = 0.0.0.0/' "$CONFIG_FILE"
  else
    cat <<'EOCFG' >>"$CONFIG_FILE"

# Added by ERPNext installer
bind-address = 0.0.0.0
EOCFG
  fi

  if grep -qE '^[[:space:]]*skip-networking' "$CONFIG_FILE"; then
    sed -i 's/^[[:space:]]*skip-networking/# &/' "$CONFIG_FILE"
  fi
fi

restart_service() {
  local svc="$1"
  if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
    systemctl restart "$svc"
    return 0
  fi
  if service "$svc" status >/dev/null 2>&1; then
    service "$svc" restart
    return 0
  fi
  return 1
}

if ! restart_service mariadb; then
  restart_service mysql || true
fi

SQL_ESCAPED_PASS=${SQL_PASS//\'/\'\'}
SQL_QUERY="CREATE USER IF NOT EXISTS '$SQL_USER'@'$SQL_ALLOW' IDENTIFIED BY '$SQL_ESCAPED_PASS'; GRANT ALL PRIVILEGES ON *.* TO '$SQL_USER'@'$SQL_ALLOW' WITH GRANT OPTION; FLUSH PRIVILEGES;"

SQL_OPTS=(-u"$SQL_USER")
if [ -n "$SQL_PASS" ]; then
  SQL_OPTS+=(-p"$SQL_PASS")
fi

mysql "${SQL_OPTS[@]}" -e "$SQL_QUERY" || mysql "${SQL_OPTS[@]}" -e "GRANT ALL PRIVILEGES ON *.* TO '$SQL_USER'@'$SQL_ALLOW' WITH GRANT OPTION; FLUSH PRIVILEGES;"
EOF
    then
        msg_warn "Failed to configure remote access on MariaDB CT ${__ctid}"
        return 1
    fi

    msg_ok "MariaDB CT ${__ctid} now accepts remote connections"
    return 0
}

configure_site_settings() {
  local site_name
  local db_name
  local admin_email
  local admin_password
  local default_site="${ERPNEXT_SITE_NAME:-erpnext.local}"
  local generated_password

  prompt_input site_name "${APP} Site" "Enter the ERPNext site name" "$default_site"

  local sanitized_default
  sanitized_default=$(printf '%s' "$site_name" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '_')
  sanitized_default="${sanitized_default##_}"
  sanitized_default="${sanitized_default%%_}"
  sanitized_default="${sanitized_default:-erpnext}"
  prompt_input db_name "${APP} Database" "Enter the MariaDB database name" "${ERPNEXT_DB_NAME:-${sanitized_default}}"

  prompt_input admin_email "${APP} Administrator" "Enter the ERPNext administrator email" "${ERPNEXT_ADMIN_EMAIL:-administrator@example.com}"

  generated_password=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c18)
  prompt_password admin_password "${APP} Administrator" "Enter the ERPNext administrator password (leave blank to autogenerate)" 1
  if [[ -z "$admin_password" ]]; then
    admin_password="$generated_password"
    msg_info "Generated administrator password: ${admin_password}"
  fi

  export ERPNEXT_SITE_NAME="$site_name"
  export ERPNEXT_DB_NAME="$db_name"
  export ERPNEXT_ADMIN_EMAIL="$admin_email"
  export ERPNEXT_ADMIN_PASSWORD="$admin_password"
}

run_remote_installer() {
  local __url="$1"
  local __label="$2"

  msg_info "Launching ${__label} installer"
  if bash -c "$(curl -fsSL "${__url}")"; then
    msg_ok "${__label} installer finished"
  else
    msg_error "${__label} installer failed"
    exit 1
  fi
}

configure_mariadb() {
    local choice
    local host
    local port
    local admin_user
    local admin_password
    local allow_host
    local detected_ctid=""
    local mariadb_ctid=""
    local asked_ctid=0
    local -a before_ctids=()
    local -a after_ctids=()
    local -a new_ctids=()

    choice=$(whiptail --title "${APP} MariaDB" --menu "Select how to provide MariaDB for ${APP}" 15 70 2 \
        create "Create a new MariaDB LXC now" \
        existing "Use an existing MariaDB instance" 3>&1 1>&2 2>&3) || exit_script

    case "$choice" in
        create)
            if command -v pct >/dev/null 2>&1; then
                mapfile -t before_ctids < <(collect_lxc_ids)
            fi
            run_remote_installer "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/mariadb.sh" "MariaDB LXC"
            if command -v pct >/dev/null 2>&1; then
                mapfile -t after_ctids < <(collect_lxc_ids)
                mapfile -t new_ctids < <(comm -13 <(printf '%s\n' "${before_ctids[@]}") <(printf '%s\n' "${after_ctids[@]}"))
                if [[ ${#new_ctids[@]} -eq 1 ]]; then
                    detected_ctid="${new_ctids[0]}"
                fi
            fi
            ;;&
        create|existing)
            mariadb_ctid="${detected_ctid}"
            while true; do
                prompt_input host "${APP} MariaDB" "Enter the MariaDB host or IP" "${ERPNEXT_DB_HOST:-}"
                if ! [[ "${host}" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
                    whiptail --title "$APP" --msgbox "MariaDB host must be an IP address or hostname." 8 70
                    continue
                fi

                prompt_input port "${APP} MariaDB" "Enter the MariaDB port" "${ERPNEXT_DB_PORT:-3306}"
                if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
                    whiptail --title "$APP" --msgbox "MariaDB port must be numeric." 8 60
                    continue
                fi

                prompt_input admin_user "${APP} MariaDB" "Enter the MariaDB administrative user" "${ERPNEXT_DB_ROOT_USER:-root}"
                if ! [[ "${admin_user}" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
                    whiptail --title "$APP" --msgbox "MariaDB administrative user contains invalid characters." 8 70
                    continue
                fi

                prompt_password admin_password "${APP} MariaDB" "Enter the MariaDB administrative password (leave blank for none)" 1

                prompt_input allow_host "${APP} MariaDB" "Enter the host pattern allowed to connect (e.g. %, 192.168.0.% )" "${ERPNEXT_DB_ALLOWED_HOST:-%}"
                if ! [[ "${allow_host}" =~ ^[%A-Za-z0-9_.:-]+$ ]]; then
                    whiptail --title "$APP" --msgbox "MariaDB allowed host may only contain letters, numbers, dots, colons, dashes, underscores, or % wildcards." 9 75
                    continue
                fi

                if command -v pct >/dev/null 2>&1; then
                    if (( asked_ctid == 0 )); then
                        prompt_input mariadb_ctid "${APP} MariaDB" "Enter the MariaDB LXC ID to adjust remote access (leave blank to skip)" "${mariadb_ctid}" 1
                        asked_ctid=1
                    fi

                    if [[ -n "${mariadb_ctid}" && ! "${mariadb_ctid}" =~ ^[0-9]+$ ]]; then
                        whiptail --title "$APP" --msgbox "MariaDB LXC ID must be numeric." 8 60
                        mariadb_ctid=""
                        asked_ctid=0
                        continue
                    fi
                fi

                if [[ -n "${mariadb_ctid}" ]]; then
                    if ! configure_mariadb_remote_access "${mariadb_ctid}" "${allow_host}" "${admin_user}" "${admin_password}"; then
                        asked_ctid=0
                        continue
                    fi
                fi

                if verify_tcp_endpoint "${host}" "${port}" "MariaDB" 12 5; then
                    break
                fi
                asked_ctid=0
            done
            ;;
    esac

    export ERPNEXT_DB_HOST="${host}"
    export ERPNEXT_DB_PORT="${port}"
    export ERPNEXT_DB_ROOT_USER="${admin_user}"
    export ERPNEXT_DB_ROOT_PASSWORD="${admin_password}"
}

prompt_redis_endpoint() {
  local __label="$1"
  local __default_port="$2"
  local __host
  local __port
  local __password

  while true; do
    prompt_input __host "${APP} Redis (${__label})" "Enter the Redis host or IP for ${__label}" "127.0.0.1"
    prompt_input __port "${APP} Redis (${__label})" "Enter the Redis port for ${__label}" "${__default_port}"
    prompt_password __password "${APP} Redis (${__label})" "Enter the Redis password for ${__label} (leave blank for none)" 1

    if verify_tcp_endpoint "$__host" "$__port" "Redis (${__label})"; then
      break
    fi
  done

  if [[ -n "$__password" ]]; then
    printf 'redis://:%s@%s:%s' "$__password" "$__host" "$__port"
  else
    printf 'redis://%s:%s' "$__host" "$__port"
  fi
}

configure_redis_instance() {
  local __label="$1"
  local __env_var="$2"
  local __default_port="$3"
  local __choice
  local __url

  __choice=$(whiptail --title "${APP} Redis (${__label})" --menu "Select how to provide Redis for ${__label}" 16 72 3 \
    create "Create a new dedicated Redis LXC now" \
    existing "Use an existing Redis instance" \
    internal "Use Redis inside the ERPNext container" 3>&1 1>&2 2>&3) || exit_script

  case "$__choice" in
    create)
      run_remote_installer "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/redis.sh" "Redis LXC (${__label})"
      __url=$(prompt_redis_endpoint "$__label" "$__default_port")
      ;;
    existing)
      __url=$(prompt_redis_endpoint "$__label" "$__default_port")
      ;;
    internal)
      __url="redis://127.0.0.1:${__default_port}"
      export ERPNEXT_ENABLE_INTERNAL_REDIS="yes"
      ;;
  esac

  export "$__env_var"="$__url"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /home/frappe/frappe-bench ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_error "Update automation for ${APP} is not available yet."
  msg_info "Please run 'bench update' inside the container to apply updates."
  exit
}

start

configure_mariadb
configure_site_settings
export ERPNEXT_ROLE="combined"
export ERPNEXT_ENABLE_INTERNAL_REDIS="no"
configure_redis_instance "Cache" "ERPNEXT_REDIS_CACHE" "6379"
configure_redis_instance "Queue" "ERPNEXT_REDIS_QUEUE" "6379"
configure_redis_instance "Socket.IO" "ERPNEXT_REDIS_SOCKETIO" "6379"

build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"

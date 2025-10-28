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

# Runtime state for remote services
declare -A REDIS_CTIDS=()
declare -A REDIS_SOURCES=()
declare -A REDIS_HOSTS=()
declare -A REDIS_PORTS=()
declare -A REDIS_PASSWORDS=()
declare -A REDIS_URLS=()

MARIADB_CTID=""
MARIADB_SOURCE=""
MARIADB_ALLOW_PATTERN="%"

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

ensure_container_running() {
    local __ctid="$1"
    local __status

    if ! command -v pct >/dev/null 2>&1; then
        return 1
    fi

    __status=$(pct status "$__ctid" 2>/dev/null | awk '{print $2}')
    if [[ -z "$__status" ]]; then
        return 1
    fi

    if [[ "$__status" != "running" ]]; then
        if whiptail --title "$APP" --yesno "Container ${__ctid} is not running.\n\nChoose <Yes> to start it now." 10 65; then
            if ! pct start "$__ctid" >/dev/null 2>&1; then
                return 1
            fi
            local __attempt
            for __attempt in {1..10}; do
                sleep 1
                __status=$(pct status "$__ctid" 2>/dev/null | awk '{print $2}')
                if [[ "$__status" == "running" ]]; then
                    return 0
                fi
            done
            return 1
        else
            return 1
        fi
    fi

    return 0
}

get_container_ipv4() {
    local __ctid="$1"
    local __ip

    __ip=$(pct exec "$__ctid" -- bash -lc "hostname -I 2>/dev/null" 2>/dev/null | awk '{for (i = 1; i <= NF; i++) { if ($i != "127.0.0.1") { print $i; exit } }}')
    printf '%s' "$__ip"
}

detect_mariadb_port() {
    local __ctid="$1"
    local __port

    __port=$(pct exec "$__ctid" -- bash -lc "ss -ltnp 2>/dev/null | awk '/mysqld|mariadbd/ {split(\$4, a, ":"); port=a[length(a)]; if (port ~ /^[0-9]+$/) {print port; exit}}'" 2>/dev/null | tr -d '\r')
    if [[ -z "$__port" ]]; then
        __port="3306"
    fi

    printf '%s' "$__port"
}

verify_tcp_endpoint() {
    local __host="$1"
    local __port="$2"
    local __label="$3"
    local __attempts="${4:-1}"
    local __delay="${5:-5}"
    local __attempt
    local __logged_wait=0

    if ((__attempts > 1)); then
        msg_info "Waiting for ${__label} at ${__host}:${__port}"
        __logged_wait=1
    fi

    for ((__attempt = 1; __attempt <= __attempts; __attempt++)); do
        if timeout 5 bash -c "</dev/tcp/${__host}/${__port}" &>/dev/null; then
            if ((__logged_wait == 1)); then
                msg_ok "${__label} is reachable at ${__host}:${__port}"
            fi
            return 0
        fi
        if ((__attempt < __attempts)); then
            sleep "${__delay}"
        fi
    done

    if ((__logged_wait == 1)); then
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

configure_mariadb_manual() {
    local host
    local port
    local admin_user
    local admin_password
    local allow_host

    while true; do
        prompt_input host "${APP} MariaDB" "Enter the MariaDB host or IP" "${ERPNEXT_DB_HOST:-}"
        if ! [[ "$host" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB host must be an IP address or hostname." 8 70
            continue
        fi

        prompt_input port "${APP} MariaDB" "Enter the MariaDB port" "${ERPNEXT_DB_PORT:-3306}"
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB port must be numeric." 8 60
            continue
        fi

        prompt_input admin_user "${APP} MariaDB" "Enter the MariaDB administrative user" "${ERPNEXT_DB_ROOT_USER:-root}"
        if ! [[ "$admin_user" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB administrative user contains invalid characters." 8 70
            continue
        fi

        prompt_password admin_password "${APP} MariaDB" "Enter the MariaDB administrative password (leave blank for none)" 1

        prompt_input allow_host "${APP} MariaDB" "Enter the host pattern allowed to connect (e.g. %, 192.168.0.% )" "${ERPNEXT_DB_ALLOWED_HOST:-%}"
        if ! [[ "$allow_host" =~ ^[%A-Za-z0-9_.:-]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB allowed host may only contain letters, numbers, dots, colons, dashes, underscores, or % wildcards." 9 75
            continue
        fi

        if verify_tcp_endpoint "$host" "$port" "MariaDB" 6 5; then
            break
        fi
    done

    MARIADB_CTID=""
    MARIADB_SOURCE="manual"
    MARIADB_ALLOW_PATTERN="$allow_host"
    export ERPNEXT_DB_HOST="$host"
    export ERPNEXT_DB_PORT="$port"
    export ERPNEXT_DB_ROOT_USER="$admin_user"
    export ERPNEXT_DB_ROOT_PASSWORD="$admin_password"
    export ERPNEXT_DB_ALLOWED_HOST="$allow_host"
}

configure_mariadb_ct() {
    local detected_ctid="$1"
    local host=""
    local port=""
    local admin_user
    local admin_password
    local allow_host
    local ctid

    while true; do
        prompt_input ctid "${APP} MariaDB" "Enter the MariaDB LXC ID" "${detected_ctid}" "0"
        if [[ -z "$ctid" ]]; then
            whiptail --title "$APP" --msgbox "MariaDB LXC ID cannot be empty." 8 55
            continue
        fi
        if ! [[ "$ctid" =~ ^[0-9]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB LXC ID must be numeric." 8 55
            continue
        fi
        if ! pct config "$ctid" >/dev/null 2>&1; then
            whiptail --title "$APP" --msgbox "No container found with ID ${ctid}." 8 55
            continue
        fi

        if ! ensure_container_running "$ctid"; then
            whiptail --title "$APP" --msgbox "Container ${ctid} must be running to continue." 8 60
            continue
        fi

        host=$(get_container_ipv4 "$ctid")
        port=$(detect_mariadb_port "$ctid")
        [[ -n "$host" ]] || host="${ERPNEXT_DB_HOST:-}"

        prompt_input host "${APP} MariaDB" "Confirm the MariaDB host" "$host"
        if ! [[ "$host" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB host must be an IP address or hostname." 8 70
            continue
        fi

        prompt_input port "${APP} MariaDB" "Confirm the MariaDB port" "$port"
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB port must be numeric." 8 60
            continue
        fi

        prompt_input admin_user "${APP} MariaDB" "Enter the MariaDB administrative user" "${ERPNEXT_DB_ROOT_USER:-root}"
        if ! [[ "$admin_user" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB administrative user contains invalid characters." 8 70
            continue
        fi

        prompt_password admin_password "${APP} MariaDB" "Enter the MariaDB administrative password (leave blank for none)" 1

        prompt_input allow_host "${APP} MariaDB" "Enter the host pattern allowed to connect (e.g. %, 192.168.0.% )" "${ERPNEXT_DB_ALLOWED_HOST:-%}"
        if ! [[ "$allow_host" =~ ^[%A-Za-z0-9_.:-]+$ ]]; then
            whiptail --title "$APP" --msgbox "MariaDB allowed host may only contain letters, numbers, dots, colons, dashes, underscores, or % wildcards." 9 75
            continue
        fi

        if ! configure_mariadb_remote_access "$ctid" "$allow_host" "$admin_user" "$admin_password"; then
            if ! whiptail --title "$APP" --yesno "Failed to configure MariaDB remote access.\n\nChoose <Yes> to try again." 10 70; then
                exit_script
            fi
            continue
        fi

        if verify_tcp_endpoint "$host" "$port" "MariaDB" 6 5; then
            break
        fi
    done

    MARIADB_CTID="$ctid"
    MARIADB_SOURCE="ctid"
    MARIADB_ALLOW_PATTERN="$allow_host"
    export ERPNEXT_DB_HOST="$host"
    export ERPNEXT_DB_PORT="$port"
    export ERPNEXT_DB_ROOT_USER="$admin_user"
    export ERPNEXT_DB_ROOT_PASSWORD="$admin_password"
    export ERPNEXT_DB_ALLOWED_HOST="$allow_host"
}

configure_mariadb() {
    local choice
    local subchoice
    local -a before_ctids=()
    local -a after_ctids=()
    local -a new_ctids=()
    local detected_ctid=""

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
            configure_mariadb_ct "$detected_ctid"
            ;;
        existing)
            subchoice=$(whiptail --title "${APP} MariaDB" --menu "Provide MariaDB connection details" 15 70 2 \
                manual "Enter MariaDB host and port manually" \
                ctid "Select an existing MariaDB container by ID" 3>&1 1>&2 2>&3) || exit_script
            case "$subchoice" in
                manual)
                    configure_mariadb_manual
                    ;;
                ctid)
                    configure_mariadb_ct ""
                    ;;
            esac
            ;;
    esac
}

parse_redis_url() {
    local __url="$1"
    local __host_var="$2"
    local __port_var="$3"
    local __password_var="$4"
    local __stripped
    local __host_port
    local __password=""
    local __host=""
    local __port=""

    __stripped="${__url#redis://}"
    if [[ "$__stripped" == :* ]]; then
        __password="${__stripped#:}"
        __password="${__password%%@*}"
        __host_port="${__stripped#*@}"
    elif [[ "$__stripped" == *@* ]]; then
        __password="${__stripped%%@*}"
        __host_port="${__stripped#*@}"
    else
        __host_port="$__stripped"
    fi

    __host="${__host_port%%:*}"
    if [[ "$__host_port" == *:* ]]; then
        __port="${__host_port##*:}"
    else
        __port="6379"
    fi

    printf -v "$__host_var" '%s' "$__host"
    printf -v "$__port_var" '%s' "$__port"
    printf -v "$__password_var" '%s' "$__password"
}
record_redis_connection() {
    local __label="$1"
    local __env_var="$2"
    local __url="$3"
    local __host
    local __port
    local __password

    parse_redis_url "$__url" __host __port __password
    REDIS_URLS["$__label"]="$__url"
    REDIS_HOSTS["$__label"]="$__host"
    REDIS_PORTS["$__label"]="$__port"
    REDIS_PASSWORDS["$__label"]="$__password"
    export "$__env_var"="$__url"
}

detect_redis_port() {
    local __ctid="$1"
    local __port=""

    __port=$(pct exec "$__ctid" -- ss -lntp 2>/dev/null | awk '/redis-server/ {split($4, a, ":"); print a[length(a)]; exit}')
    if [[ -z "$__port" ]]; then
        __port="6379"
    fi

    printf '%s' "$__port"
}

detect_redis_password() {
    local __ctid="$1"
    pct exec "$__ctid" -- bash -lc "awk '/^[[:space:]]*requirepass[[:space:]]+/ {print \$2; exit}' /etc/redis/redis.conf 2>/dev/null" 2>/dev/null | tr -d '\r' | head -n1
}

configure_redis_manual() {
    local __label="$1"
    local __env_var="$2"
    local __default_port="$3"
    local host
    local port
    local password
    local url

    while true; do
        prompt_input host "${APP} Redis (${__label})" "Enter the Redis host or IP for ${__label}" "127.0.0.1"

        prompt_input port "${APP} Redis (${__label})" "Enter the Redis port for ${__label}" "${__default_port}"
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            whiptail --title "$APP" --msgbox "Redis port must be numeric." 8 60
            continue
        fi

        prompt_password password "${APP} Redis (${__label})" "Enter the Redis password for ${__label} (leave blank for none)" 1

        if verify_tcp_endpoint "$host" "$port" "Redis (${__label})" 6 5; then
            break
        fi
    done

    if [[ -n "$password" ]]; then
        url=$(printf 'redis://:%s@%s:%s' "$password" "$host" "$port")
    else
        url=$(printf 'redis://%s:%s' "$host" "$port")
    fi

    REDIS_CTIDS["$__label"]=""
    REDIS_SOURCES["$__label"]="manual"
    record_redis_connection "$__label" "$__env_var" "$url"
}

configure_redis_ct() {
    local __label="$1"
    local __env_var="$2"
    local __default_port="$3"
    local __detected_ctid="$4"
    local ctid
    local host
    local port
    local password
    local detected_password
    local url

    while true; do
        prompt_input ctid "${APP} Redis (${__label})" "Enter the Redis LXC ID" "${__detected_ctid}" "0"
        if [[ -z "$ctid" ]]; then
            whiptail --title "$APP" --msgbox "Redis LXC ID cannot be empty." 8 55
            continue
        fi
        if ! [[ "$ctid" =~ ^[0-9]+$ ]]; then
            whiptail --title "$APP" --msgbox "Redis LXC ID must be numeric." 8 55
            continue
        fi
        if ! pct config "$ctid" >/dev/null 2>&1; then
            whiptail --title "$APP" --msgbox "No container found with ID ${ctid}." 8 55
            continue
        fi

        if ! ensure_container_running "$ctid"; then
            whiptail --title "$APP" --msgbox "Container ${ctid} must be running to continue." 8 60
            continue
        fi

        host=$(get_container_ipv4 "$ctid")
        [[ -n "$host" ]] || host="127.0.0.1"
        port=$(detect_redis_port "$ctid")
        [[ -n "$port" ]] || port="$__default_port"

        prompt_input host "${APP} Redis (${__label})" "Confirm the Redis host" "$host"
        prompt_input port "${APP} Redis (${__label})" "Confirm the Redis port" "$port"
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            whiptail --title "$APP" --msgbox "Redis port must be numeric." 8 60
            continue
        fi

        detected_password=$(detect_redis_password "$ctid")
        local password_prompt
        if [[ -n "$detected_password" ]]; then
            whiptail --title "${APP} Redis (${__label})" --msgbox "A Redis password appears to be configured. Enter it in the next prompt to use it." 9 70
            password_prompt="Enter the Redis password for ${__label} (leave blank to use the detected password)"
        else
            password_prompt="Enter the Redis password for ${__label} (leave blank for none)"
        fi
        prompt_password password "${APP} Redis (${__label})" "$password_prompt" 1
        if [[ -z "$password" ]]; then
            password="$detected_password"
        fi

        if verify_tcp_endpoint "$host" "$port" "Redis (${__label})" 6 5; then
            break
        fi
    done

    if [[ -n "$password" ]]; then
        url=$(printf 'redis://:%s@%s:%s' "$password" "$host" "$port")
    else
        url=$(printf 'redis://%s:%s' "$host" "$port")
    fi

    REDIS_CTIDS["$__label"]="$ctid"
    REDIS_SOURCES["$__label"]="ctid"
    record_redis_connection "$__label" "$__env_var" "$url"
}

configure_redis_instance() {
    local __label="$1"
    local __env_var="$2"
    local __default_port="$3"
    local __choice
    local __subchoice
    local -a before_ctids=()
    local -a after_ctids=()
    local -a new_ctids=()
    local detected_ctid=""

    __choice=$(whiptail --title "${APP} Redis (${__label})" --menu "Select how to provide Redis for ${__label}" 16 72 3 \
        create "Create a new dedicated Redis LXC now" \
        existing "Use an existing Redis instance" \
        internal "Use Redis inside the ERPNext container" 3>&1 1>&2 2>&3) || exit_script

    case "$__choice" in
        create)
            if command -v pct >/dev/null 2>&1; then
                mapfile -t before_ctids < <(collect_lxc_ids)
            fi
            run_remote_installer "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/redis.sh" "Redis LXC (${__label})"
            if command -v pct >/dev/null 2>&1; then
                mapfile -t after_ctids < <(collect_lxc_ids)
                mapfile -t new_ctids < <(comm -13 <(printf '%s\n' "${before_ctids[@]}") <(printf '%s\n' "${after_ctids[@]}"))
                if [[ ${#new_ctids[@]} -eq 1 ]]; then
                    detected_ctid="${new_ctids[0]}"
                fi
            fi
            configure_redis_ct "$__label" "$__env_var" "$__default_port" "$detected_ctid"
            ;;
        existing)
            __subchoice=$(whiptail --title "${APP} Redis (${__label})" --menu "Provide Redis connection details" 15 70 2 \
                manual "Enter Redis host and port manually" \
                ctid "Select an existing Redis container by ID" 3>&1 1>&2 2>&3) || exit_script
            case "$__subchoice" in
                manual)
                    configure_redis_manual "$__label" "$__env_var" "$__default_port"
                    ;;
                ctid)
                    configure_redis_ct "$__label" "$__env_var" "$__default_port" ""
                    ;;
            esac
            ;;
        internal)
            REDIS_CTIDS["$__label"]=""
            REDIS_SOURCES["$__label"]="internal"
            record_redis_connection "$__label" "$__env_var" "redis://127.0.0.1:${__default_port}"
            export ERPNEXT_ENABLE_INTERNAL_REDIS="yes"
            ;;
    esac
}
configure_site_settings() {
    local site_name
    local db_name
    local admin_email
    local admin_password
    local default_site="${ERPNEXT_SITE_NAME:-erpnext.local}"
    local generated_password
    local sanitized_default

    prompt_input site_name "${APP} Site" "Enter the ERPNext site name" "$default_site"

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

post_install_validate_mariadb() {
    if [[ -z "$ERPNEXT_DB_HOST" ]]; then
        return
    fi

    msg_info "Validating MariaDB connectivity"
    if ! pct exec "$CT_ID" -- bash -lc "timeout 10 bash -c '</dev/tcp/${ERPNEXT_DB_HOST}/${ERPNEXT_DB_PORT}>'" >/dev/null 2>&1; then
        msg_error "Unable to reach MariaDB at ${ERPNEXT_DB_HOST}:${ERPNEXT_DB_PORT} from container ${CT_ID}"
        exit 1
    fi

    if [[ -n "$ERPNEXT_DB_ROOT_PASSWORD" ]]; then
        if ! pct exec "$CT_ID" -- env MYSQL_PWD="$ERPNEXT_DB_ROOT_PASSWORD" mysql -u "$ERPNEXT_DB_ROOT_USER" -h "$ERPNEXT_DB_HOST" -P "$ERPNEXT_DB_PORT" --protocol=TCP -e "SELECT 1" >/dev/null 2>&1; then
            msg_error "Failed to authenticate with MariaDB using the provided credentials."
            exit 1
        fi
    else
        if ! pct exec "$CT_ID" -- mysql -u "$ERPNEXT_DB_ROOT_USER" -h "$ERPNEXT_DB_HOST" -P "$ERPNEXT_DB_PORT" --protocol=TCP -e "SELECT 1" >/dev/null 2>&1; then
            msg_error "Failed to authenticate with MariaDB using the provided credentials."
            exit 1
        fi
    fi
    msg_ok "MariaDB connectivity verified"

    if [[ -n "$MARIADB_CTID" && -n "$IP" ]]; then
        configure_mariadb_remote_access "$MARIADB_CTID" "$IP" "$ERPNEXT_DB_ROOT_USER" "$ERPNEXT_DB_ROOT_PASSWORD" || msg_warn "Unable to adjust MariaDB container permissions for ${IP}"

        local check_query="SELECT COUNT(*) FROM mysql.user WHERE user='${ERPNEXT_DB_ROOT_USER}' AND host='${IP}';"
        local count="0"
        if [[ -n "$ERPNEXT_DB_ROOT_PASSWORD" ]]; then
            count=$(pct exec "$MARIADB_CTID" -- env MYSQL_PWD="$ERPNEXT_DB_ROOT_PASSWORD" mysql -u "$ERPNEXT_DB_ROOT_USER" -NBe "$check_query" 2>/dev/null | tail -n1)
        else
            count=$(pct exec "$MARIADB_CTID" -- mysql -u "$ERPNEXT_DB_ROOT_USER" -NBe "$check_query" 2>/dev/null | tail -n1)
        fi
        count="${count:-0}"

        if [[ "$count" -lt 1 ]]; then
            if [[ -n "$ERPNEXT_DB_ROOT_PASSWORD" ]]; then
                pct exec "$MARIADB_CTID" -- env MYSQL_PWD="$ERPNEXT_DB_ROOT_PASSWORD" SQL_USER="$ERPNEXT_DB_ROOT_USER" ERP_IP="$IP" bash -s <<'EOSQL'
set -e
ESCAPED_PASS=$(printf "%s" "$MYSQL_PWD" | sed "s/'/''/g")
mysql -u "$SQL_USER" -e "CREATE USER IF NOT EXISTS '$SQL_USER'@'$ERP_IP' IDENTIFIED BY '$ESCAPED_PASS'; GRANT ALL PRIVILEGES ON *.* TO '$SQL_USER'@'$ERP_IP' WITH GRANT OPTION; FLUSH PRIVILEGES;"
EOSQL
            else
                pct exec "$MARIADB_CTID" -- env SQL_USER="$ERPNEXT_DB_ROOT_USER" ERP_IP="$IP" bash -s <<'EOSQL'
set -e
mysql -u "$SQL_USER" -e "CREATE USER IF NOT EXISTS '$SQL_USER'@'$ERP_IP' IDENTIFIED BY ''; GRANT ALL PRIVILEGES ON *.* TO '$SQL_USER'@'$ERP_IP' WITH GRANT OPTION; FLUSH PRIVILEGES;"
EOSQL
            fi
        fi
    fi
}

post_install_validate_redis() {
    local __label="$1"
    local __url="$2"
    local __host
    local __port
    local __password

    parse_redis_url "$__url" __host __port __password

    msg_info "Validating Redis (${__label}) connectivity"
    if ! pct exec "$CT_ID" -- bash -lc "timeout 10 bash -c '</dev/tcp/${__host}/${__port}>'" >/dev/null 2>&1; then
        msg_error "Unable to reach Redis (${__label}) at ${__host}:${__port} from container ${CT_ID}"
        exit 1
    fi

    if ! pct exec "$CT_ID" -- env REDIS_URL="$__url" bash -lc 'redis-cli -u "$REDIS_URL" PING' >/dev/null 2>&1; then
        msg_error "Redis (${__label}) did not respond to PING at ${__host}:${__port}"
        exit 1
    fi

    msg_ok "Redis (${__label}) connectivity verified"
}

post_install_validation() {
    post_install_validate_mariadb
    local label
    for label in "${!REDIS_URLS[@]}"; do
        post_install_validate_redis "$label" "${REDIS_URLS[$label]}"
    done
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
post_install_validation
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"

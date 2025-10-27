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
    local __value

    while true; do
        __value=$(whiptail --title "$__title" --inputbox "$__prompt" 10 70 "$__default" 3>&1 1>&2 2>&3) || exit_script
        if [[ -n "${__value}" ]]; then
            printf -v "$__result_var" '%s' "${__value}"
            return 0
        fi
        whiptail --title "$APP" --msgbox "Input cannot be empty." 8 50
    done
}

prompt_password() {
    local __result_var="$1"
    local __title="$2"
    local __prompt="$3"
    local __password

    __password=$(whiptail --title "$__title" --passwordbox "$__prompt" 10 70 3>&1 1>&2 2>&3) || exit_script
    printf -v "$__result_var" '%s' "${__password}"
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

    choice=$(whiptail --title "${APP} MariaDB" --menu "Select how to provide MariaDB for ${APP}" 15 70 2 \
        create "Create a new MariaDB LXC now" \
        existing "Use an existing MariaDB instance" 3>&1 1>&2 2>&3) || exit_script

    case "$choice" in
        create)
            run_remote_installer "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/mariadb.sh" "MariaDB LXC"
            ;;&
        create|existing)
            prompt_input host "${APP} MariaDB" "Enter the MariaDB host or IP" ""
            prompt_input port "${APP} MariaDB" "Enter the MariaDB port" "3306"
            prompt_input admin_user "${APP} MariaDB" "Enter the MariaDB administrative user" "root"
            prompt_password admin_password "${APP} MariaDB" "Enter the MariaDB administrative password (leave blank for none)"
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

    prompt_input __host "${APP} Redis (${__label})" "Enter the Redis host or IP for ${__label}" "127.0.0.1"
    prompt_input __port "${APP} Redis (${__label})" "Enter the Redis port for ${__label}" "${__default_port}"
    prompt_password __password "${APP} Redis (${__label})" "Enter the Redis password for ${__label} (leave blank for none)"

    if [[ -n "${__password}" ]]; then
        printf 'redis://:%s@%s:%s' "${__password}" "${__host}" "${__port}"
    else
        printf 'redis://%s:%s' "${__host}" "${__port}"
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

    export "$__env_var"="${__url}"
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
configure_redis_instance "Cache" "ERPNEXT_REDIS_CACHE" "6379"
configure_redis_instance "Queue" "ERPNEXT_REDIS_QUEUE" "6379"
configure_redis_instance "Socket.IO" "ERPNEXT_REDIS_SOCKETIO" "6379"

build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"

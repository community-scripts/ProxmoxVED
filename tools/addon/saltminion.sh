#!/usr/bin/env bash

# community-scripts ORG | saltminion Installer
# Author: bdvberg01
# License: MIT

function header_info {
    clear
    cat <<"EOF"
    ____  __          __  ___      ___       __          _
   / __ \/ /_  ____  /  |/  /_  __/   | ____/ /___ ___  (_)___
  / /_/ / __ \/ __ \/ /|_/ / / / / /| |/ __  / __ `__ \/ / __ \
 / ____/ / / / /_/ / /  / / /_/ / ___ / /_/ / / / / / / / / / /
/_/   /_/ /_/ .___/_/  /_/\__, /_/  |_\__,_/_/ /_/ /_/_/_/ /_/
           /_/           /____/
EOF
}

YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"

APP="saltminion"

IFACE=$(ip -4 route | awk '/default/ {print $5; exit}')
IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)
[[ -z "$IP" ]] && IP=$(hostname -I | awk '{print $1}')
[[ -z "$IP" ]] && IP="127.0.0.1"

# Detect OS
if [[ -f "/etc/alpine-release" ]]; then
    OS="Alpine"
    PKG_MANAGER_INSTALL="apk add --no-cache"
    PKG_QUERY="apk info -e"
elif [[ -f "/etc/debian_version" ]]; then
    OS="Debian"
    PKG_MANAGER_INSTALL="apt-get install -y"
    PKG_QUERY="dpkg -l"
else
    echo -e "${CROSS} Unsupported OS detected. Exiting."
    exit 1
fi

header_info

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }

function check_internet() {
    msg_info "Checking Internet connectivity to GitHub"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://github.com)
    if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 400 ]]; then
        msg_ok "Internet connectivity OK"
    else
        msg_error "Internet connectivity or GitHub unreachable (Status $HTTP_CODE). Exiting."
        exit 1
    fi
}

function is_saltminion_installed() {
    if [[ "$OS" == "Debian" ]]; then
        [[ -f "/etc/salt/minion" ]]
    else
        [[ -d "$INSTALL_DIR_ALPINE" ]] && rc-service lighttpd status &>/dev/null
    fi
}

function install_saltminion() {
    msg_info "Installing Dependencies"
    $STD apt-get install -y \
      jq
    msg_ok "Installed Dependencies"
    
    msg_info "Setup Salt repo"
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public -o /etc/apt/keyrings/salt-archive-keyring.pgp
    curl -fsSL https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.sources -o /etc/apt/sources.list.d/salt.sources
    $STD apt-get update
    msg_ok "Setup Salt repo"
    
    msg_info "Installing Salt Master"
    RELEASE=$(curl -fsSL https://api.github.com/repos/saltstack/salt/releases/latest | jq -r .tag_name | sed 's/^v//')
    cat <<EOF >/etc/apt/preferences.d/salt-pin-1001
    Package: salt-*
    Pin: version ${RELEASE}
    Pin-Priority: 1001
    EOF
    $STD apt-get install -y salt-master
    echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
    msg_ok "Installed Salt Master"
}

function uninstall_saltminion() {
    msg_info "Stopping service"
    if [[ "$OS" == "Debian" ]]; then
        apt-get purge salt-minion
    fi
    msg_ok "Uninstalled Salt Minion"
}

function update_saltminion() {
    RELEASE=$(curl -fsSL https://api.github.com/repos/saltstack/salt/releases/latest | jq -r .tag_name | sed 's/^v//')
    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
      msg_info "Updating $APP to ${RELEASE}"
      sed -i "s/^\(Pin: version \).*/\1${RELEASE}/" /etc/apt/preferences.d/salt-pin-1001
      $STD apt-get update
      $STD apt-get upgrade -y
      echo "${RELEASE}" >/opt/${APP}_version.txt
      msg_ok "Updated ${APP} to ${RELEASE}"
    else
      msg_ok "${APP} is already up to date (${RELEASE})"
    fi
}

if is_saltminion_installed; then
    echo -e "${YW}⚠️ ${APP} is already installed at ${INSTALL_DIR}.${CL}"
    read -r -p "Would you like to Update (1), Uninstall (2) or Cancel (3)? [1/2/3]: " action
    action="${action//[[:space:]]/}" # Eingabe bereinigen
    case "$action" in
    1)
        check_internet
        update_saltminion
        ;;
    2)
        uninstall_saltminion
        ;;
    3)
        echo -e "${YW}⚠️ Action cancelled. Exiting.${CL}"
        exit 0
        ;;
    *)
        echo -e "${YW}⚠️ Invalid input. Exiting.${CL}"
        exit 1
        ;;
    esac
else
    read -r -p "Would you like to install ${APP}? (y/n): " install_prompt
    install_prompt="${install_prompt//[[:space:]]/}"
    if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
        check_internet
        install_saltminion
        echo -e "${CM} ${GN}${APP} Salt Minion is installed: ${BL}http://${IP}/${CL}"
    else
        echo -e "${YW}⚠️ Installation skipped. Exiting.${CL}"
        exit 0
    fi
fi

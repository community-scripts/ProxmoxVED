#!/usr/bin/env bash

# community-scripts ORG | phpMyAdmin Installer
# Author: MickLesk
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

APP="phpMyAdmin"
INSTALL_DIR="/usr/share/phpmyadmin"
SERVICE_PATH_DEBIAN="/etc/systemd/system/phpmyadmin.service"
SERVICE_PATH_ALPINE="/etc/init.d/phpmyadmin"
DEFAULT_PORT=8081

IFACE=$(ip -4 route | awk '/default/ {print $5; exit}')
IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)
[[ -z "$IP" ]] && IP=$(hostname -I | awk '{print $1}')
[[ -z "$IP" ]] && IP="127.0.0.1"

# Detect OS
if [[ -f "/etc/alpine-release" ]]; then
    OS="Alpine"
    PKG_MANAGER="apk add --no-cache"
    SERVICE_PATH="$SERVICE_PATH_ALPINE"
elif [[ -f "/etc/debian_version" ]]; then
    OS="Debian"
    PKG_MANAGER="apt-get install -y"
    SERVICE_PATH="$SERVICE_PATH_DEBIAN"
else
    echo -e "${CROSS} Unsupported OS detected. Exiting."
    exit 1
fi

header_info

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }

# Check for existing installation
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${YW}⚠️ ${APP} is already installed.${CL}"
    read -r -p "Would you like to uninstall ${APP}? (y/N): " uninstall_prompt
    if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
        msg_info "Uninstalling ${APP}"
        if [[ "$OS" == "Debian" ]]; then
            systemctl disable --now phpmyadmin.service &>/dev/null
            rm -f "$SERVICE_PATH"
        else
            rc-service phpmyadmin stop &>/dev/null
            rc-update del phpmyadmin &>/dev/null
            rm -f "$SERVICE_PATH"
        fi
        rm -rf "$INSTALL_DIR"
        msg_ok "${APP} has been uninstalled."
        exit 0
    fi

    read -r -p "Would you like to update ${APP}? (y/N): " update_prompt
    if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
        msg_info "Updating ${APP}"
        curl -fsSL "https://www.phpmyadmin.net/home_page/version.txt" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | while read -r LATEST_VERSION; do
            curl -fsSL "https://files.phpmyadmin.net/phpMyAdmin/${LATEST_VERSION}/phpMyAdmin-${LATEST_VERSION}-all-languages.tar.gz" | tar -xz --strip-components=1 -C "$INSTALL_DIR"
        done
        msg_ok "Updated ${APP}"
        exit 0
    else
        echo -e "${YW}⚠️ Update skipped. Exiting.${CL}"
        exit 0
    fi
fi

echo -e "${YW}⚠️ ${APP} is not installed.${CL}"
read -r -p "Enter port number (Default: ${DEFAULT_PORT}): " PORT
PORT=${PORT:-$DEFAULT_PORT}

read -r -p "Would you like to install ${APP}? (y/n): " install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Installing ${APP} on ${OS}"
    $PKG_MANAGER nginx php-fpm php-mysqli php-json php-session curl tar &>/dev/null

    mkdir -p "$INSTALL_DIR"
    curl -fsSL "https://www.phpmyadmin.net/home_page/version.txt" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | while read -r LATEST_VERSION; do
        curl -fsSL "https://files.phpmyadmin.net/phpMyAdmin/${LATEST_VERSION}/phpMyAdmin-${LATEST_VERSION}-all-languages.tar.gz" | tar -xz --strip-components=1 -C "$INSTALL_DIR"
    done
    chown -R root:root "$INSTALL_DIR"
    msg_ok "Installed ${APP}"

    msg_info "Configuring Nginx"
    mkdir -p /etc/nginx/conf.d
    cat <<EOF >/etc/nginx/conf.d/phpmyadmin.conf
server {
    listen ${PORT};
    server_name _;

    root ${INSTALL_DIR};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
    nginx -s reload || systemctl reload nginx || rc-service nginx reload
    msg_ok "Nginx configured"

    msg_info "Creating phpMyAdmin service"
    if [[ "$OS" == "Debian" ]]; then
        cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=phpMyAdmin Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/nginx -g "daemon off;"
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable --now phpmyadmin
    else
        cat <<EOF >"$SERVICE_PATH"
#!/sbin/openrc-run

command="/usr/sbin/nginx"
command_args="-g 'daemon off;'"
command_background=true

depend() {
    need net
}
EOF
        chmod +x "$SERVICE_PATH"
        rc-update add phpmyadmin default
        rc-service phpmyadmin start
    fi
    msg_ok "Service created successfully"

    echo -e "${CM} ${GN}${APP} is reachable at: ${BL}http://${IP}:${PORT}${CL}"
else
    echo -e "${YW}⚠️ Installation skipped. Exiting.${CL}"
    exit 0
fi

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
INSTALL_DIR_DEBIAN="/var/www/html/phpMyAdmin"
INSTALL_DIR_ALPINE="/usr/share/phpmyadmin"
DEFAULT_PORT=8081

IFACE=$(ip -4 route | awk '/default/ {print $5; exit}')
IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)
[[ -z "$IP" ]] && IP=$(hostname -I | awk '{print $1}')
[[ -z "$IP" ]] && IP="127.0.0.1"

# Detect OS
if [[ -f "/etc/alpine-release" ]]; then
    OS="Alpine"
    PKG_MANAGER_INSTALL="apk add --no-cache"
    PKG_QUERY="apk info -e"
    INSTALL_DIR="$INSTALL_DIR_ALPINE"
elif [[ -f "/etc/debian_version" ]]; then
    OS="Debian"
    PKG_MANAGER_INSTALL="apt-get install -y"
    PKG_QUERY="dpkg -l"
    INSTALL_DIR="$INSTALL_DIR_DEBIAN"
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

function install_php_and_modules() {
    msg_info "Checking existing PHP installation"
    if command -v php >/dev/null 2>&1; then
        PHP_VERSION=$(php -r 'echo PHP_VERSION;')
        msg_ok "Found PHP version $PHP_VERSION"
    else
        msg_info "PHP not found, will install PHP core"
    fi

    if [[ "$OS" == "Debian" ]]; then
        PHP_MODULES=("php" "php-mysqli" "php-mbstring" "php-zip" "php-gd" "php-json" "php-curl")
        MISSING_PACKAGES=()
        for pkg in "${PHP_MODULES[@]}"; do
            if ! dpkg -l | grep -qw "$pkg"; then
                MISSING_PACKAGES+=("$pkg")
            fi
        done
        if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
            msg_info "Installing missing PHP packages: ${MISSING_PACKAGES[*]}"
            if ! apt-get update &>/dev/null || ! apt-get install -y "${MISSING_PACKAGES[@]}" &>/dev/null; then
                msg_error "Failed to install required PHP modules. Exiting."
                exit 1
            fi
            msg_ok "Installed missing PHP packages"
        else
            msg_ok "All required PHP modules are already installed"
        fi
    else
        $PKG_MANAGER_INSTALL nginx php-fpm php-mysqli php-json php-session curl tar openssl &>/dev/null
    fi
}

function install_phpmyadmin() {
    msg_info "Fetching latest phpMyAdmin release from GitHub"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/phpmyadmin/phpmyadmin/releases/latest | grep tag_name | cut -d '"' -f4)
    if [[ -z "$LATEST_VERSION" ]]; then
        msg_error "Could not determine latest phpMyAdmin version from GitHub – falling back to 5.2.2"
        LATEST_VERSION="RELEASE_5_2_2"
    fi
    msg_ok "Latest version: $LATEST_VERSION"

    TARBALL_URL="https://files.phpmyadmin.net/phpMyAdmin/${LATEST_VERSION}/phpMyAdmin-${LATEST_VERSION}-all-languages.tar.gz"
    msg_info "Downloading ${TARBALL_URL}"
    if ! curl -fsSL "$TARBALL_URL" -o /tmp/phpmyadmin.tar.gz; then
        msg_error "Download failed: $TARBALL_URL"
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"
    tar xf /tmp/phpmyadmin.tar.gz --strip-components=1 -C "$INSTALL_DIR"
}

function configure_phpmyadmin() {
    if [[ "$OS" == "Debian" ]]; then
        cp "$INSTALL_DIR/config.sample.inc.php" "$INSTALL_DIR/config.inc.php"
        SECRET=$(openssl rand -base64 24)
        sed -i "s#\$cfg\['blowfish_secret'\] = '';#\$cfg['blowfish_secret'] = '${SECRET}';#" "$INSTALL_DIR/config.inc.php"
        chmod 660 "$INSTALL_DIR/config.inc.php"
        chown -R www-data:www-data "$INSTALL_DIR"
        systemctl restart apache2
        msg_ok "Configured phpMyAdmin with Apache"
    else
        msg_info "Configuring Nginx for phpMyAdmin"
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
        msg_ok "Configured phpMyAdmin with Nginx"
    fi
}

echo -e "${YW}⚠️ ${APP} will now be installed.${CL}"
read -r -p "Enter port number (Default: ${DEFAULT_PORT}): " PORT
PORT=${PORT:-$DEFAULT_PORT}

read -r -p "Would you like to install ${APP}? (y/n): " install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
    check_internet
    install_php_and_modules
    install_phpmyadmin
    configure_phpmyadmin
    echo -e "${CM} ${GN}${APP} is reachable at: ${BL}http://${IP}:${PORT}${CL}"
else
    echo -e "${YW}⚠️ Installation skipped. Exiting.${CL}"
    exit 0
fi

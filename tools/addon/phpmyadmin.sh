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
PORT=8081
WEBROOT="/usr/share/phpmyadmin"

IFACE=$(ip -4 route | awk '/default/ {print $5; exit}')
IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)
[[ -z "$IP" ]] && IP="127.0.0.1"

if [[ -f "/etc/alpine-release" ]]; then
    OS="Alpine"
    SERVICE_PATH="/etc/init.d/phpmyadmin"
    PKG_MANAGER="apk add --no-cache"
    PHP_SERVICE="php81"
elif [[ -f "/etc/debian_version" ]]; then
    OS="Debian"
    SERVICE_PATH="/etc/systemd/system/phpmyadmin.service"
    PKG_MANAGER="apt-get install -y"
    PHP_SERVICE="php"
else
    echo -e "${CROSS} Unsupported OS"
    exit 1
fi

header_info

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }

read -r -p "Install ${APP}? (y/n): " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Installing dependencies"
    $PKG_MANAGER lighttpd ${PHP_SERVICE} ${PHP_SERVICE}-session ${PHP_SERVICE}-mysqli ${PHP_SERVICE}-mbstring ${PHP_SERVICE}-gettext curl unzip &>/dev/null
    msg_ok "Dependencies installed"

    msg_info "Fetching latest phpMyAdmin"
    mkdir -p "$WEBROOT"
    curl -fsSL https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip -o /tmp/pma.zip
    unzip -q /tmp/pma.zip -d /usr/share/
    mv /usr/share/phpMyAdmin-* "$WEBROOT"
    rm -f /tmp/pma.zip
    msg_ok "phpMyAdmin installed to $WEBROOT"

    msg_info "Creating Lighttpd config"
    cat <<EOF >/etc/lighttpd/lighttpd.conf
server.modules = ("mod_access", "mod_alias", "mod_redirect")
server.document-root = "$WEBROOT"
server.port = $PORT
index-file.names = ( "index.php", "index.html" )
alias.url = ( "/phpmyadmin/" => "$WEBROOT/" )
mimetype.assign = ( ".html" => "text/html", ".php" => "text/html" )
server.modules += ( "mod_fastcgi" )
fastcgi.server = ( ".php" => ((
  "bin-path" => "/usr/bin/${PHP_SERVICE}-cgi",
  "socket" => "/tmp/php-fastcgi.socket"
)))
EOF
    msg_ok "Config created"

    msg_info "Creating service"
    if [[ "$OS" == "Debian" ]]; then
        cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=phpMyAdmin Lighttpd
After=network.target

[Service]
ExecStart=/usr/sbin/lighttpd -D -f /etc/lighttpd/lighttpd.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable --now phpmyadmin &>/dev/null
    else
        cat <<EOF >"$SERVICE_PATH"
#!/sbin/openrc-run

command="/usr/sbin/lighttpd"
command_args="-D -f /etc/lighttpd/lighttpd.conf"
command_background=true

depend() {
    need net
}
EOF
        chmod +x "$SERVICE_PATH"
        rc-update add phpmyadmin default &>/dev/null
        rc-service phpmyadmin start &>/dev/null
    fi
    msg_ok "Service ready"
    echo -e "${CM} ${GN}${APP} is reachable at: ${BL}http://$IP:$PORT${CL}"
else
    echo -e "${YW}⚠️ Installation skipped. Exiting.${CL}"
    exit 0
fi

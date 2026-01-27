#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: chrnie
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://icinga.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

source /etc/os-release
FQDN=$(hostname -f)

msg_info "Setting up Icinga Repository"
setup_deb822_repo \
  "icinga-stable" \
  "https://packages.icinga.com/icinga.key" \
  "https://packages.icinga.com/debian/" \
  "icinga-${VERSION_CODENAME}" \
  "main"
msg_ok "Set up Icinga Repository"

msg_info "Adding Netways extras and plugins repository"
setup_deb822_repo \
  "netways-extras" \
  "https://packages.netways.de/netways-repo.asc" \
  "https://packages.netways.de/extras/debian/" \
  "${VERSION_CODENAME}" \
  "main"
setup_deb822_repo \
  "netways-plugins" \
  "https://packages.netways.de/netways-repo.asc" \
  "https://packages.netways.de/plugins/debian/" \
  "${VERSION_CODENAME}" \
  "main"
msg_ok "Set up Netways Repositories"

msg_info "Adding Linuxfabrik plugins repository"
setup_deb822_repo \
  "linuxfabrik-monitoring-plugins" \
  "https://repo.linuxfabrik.ch/linuxfabrik.key" \
  "https://repo.linuxfabrik.ch/monitoring-plugins/debian/" \
  "${VERSION_CODENAME}-release" \
  "main"
msg_ok "Set up Linuxfabrik plugins repository"


pkg_update
setup_mariadb
setup_apache
msg_info "Installing Icinga"
pkg_install \
  icinga2 icingaweb2 icingadb icingadb-redis imagemagick php-imagick openssh-server \
  icingadb-web icinga-director icinga-businessprocess icinga-cube icinga-notifications-web icinga-notifications icinga-x509 icingaweb2-module-reporting \
  icingaweb2-module-perfdatagraphs-influxdbv1 icingaweb2-module-perfdatagraphs-influxdbv2 icingaweb2-module-perfdatagraphs \
  linuxfabrik-monitoring-plugins vim git redis-tools pwgen || { msg_error "Failed to install Icinga packages"; exit 1; }
msg_ok "Installed Icinga"

msg_info "Disable Apache default site and redirect / to /icingaweb2"
$STD a2dissite 000-default.conf || msg_error "Warning: Failed to disable default Apache site"
cat <<EOF >/etc/apache2/sites-available/icingaweb2-redirect.conf || { msg_error "Failed to create Apache configuration"; exit 1; }
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /usr/share/icingaweb2/public
    RedirectMatch ^/$ /icingaweb2/
</VirtualHost>
EOF
$STD a2ensite icingaweb2-redirect.conf || { msg_error "Failed to enable Apache site"; exit 1; }
msg_ok "Installed Apache and configured Icinga Web 2 redirect"
systemctl reload apache2 || { msg_error "Failed to reload Apache"; exit 1; }

# Enable and start services
systemctl enable icinga2 apache2 mariadb --now &>/dev/null || { msg_error "Failed to enable and start services"; exit 1; }
msg_info "Started and enabled Services"


msg_info "Create Local Databases and Users for Icinga"
# Generate random passwords if not preset
ICINGA_DB_PW="${ICINGA_DB_PW:-$(pwgen -s 20 1)}"
ICINGAWEB_DB_PW="${ICINGAWEB_DB_PW:-$(pwgen -s 20 1)}"
NOTIFICATIONS_DB_PW="${NOTIFICATIONS_DB_PW:-$(pwgen -s 20 1)}"
DIRECTOR_DB_PW="${DIRECTOR_DB_PW:-$(pwgen -s 20 1)}"
X509_DB_PW="${X509_DB_PW:-$(pwgen -s 20 1)}"
REPORTING_DB_PW="${REPORTING_DB_PW:-$(pwgen -s 20 1)}"
ICINGAWEB_ADMIN_PW="${ICINGAWEB_ADMIN_PW:-$(pwgen -s 12 1)}"

cat <<EOF | mysql || { msg_error "Failed to create databases"; exit 1; }
CREATE DATABASE IF NOT EXISTS icingadb;
CREATE DATABASE IF NOT EXISTS icingaweb;
CREATE DATABASE IF NOT EXISTS notifications;
CREATE DATABASE IF NOT EXISTS director CHARACTER SET 'utf8';
CREATE DATABASE IF NOT EXISTS x509;
CREATE DATABASE IF NOT EXISTS reporting;
CREATE USER IF NOT EXISTS 'icingadb'@'localhost' IDENTIFIED BY '${ICINGA_DB_PW}';
CREATE USER IF NOT EXISTS 'icingaweb'@'localhost' IDENTIFIED BY '${ICINGAWEB_DB_PW}';
CREATE USER IF NOT EXISTS 'notifications'@'localhost' IDENTIFIED BY '${NOTIFICATIONS_DB_PW}';
CREATE USER IF NOT EXISTS 'director'@'localhost' IDENTIFIED BY '${DIRECTOR_DB_PW}';
CREATE USER IF NOT EXISTS 'x509'@'localhost' IDENTIFIED BY '${X509_DB_PW}';
CREATE USER IF NOT EXISTS 'reporting'@'localhost' IDENTIFIED BY '${REPORTING_DB_PW}';
GRANT ALL PRIVILEGES ON icingadb.* TO 'icingadb'@'localhost';
GRANT ALL PRIVILEGES ON icingaweb.* TO 'icingaweb'@'localhost';
GRANT ALL PRIVILEGES ON notifications.* TO 'notifications'@'localhost';
GRANT ALL PRIVILEGES ON director.* TO 'director'@'localhost';
GRANT ALL PRIVILEGES ON x509.* TO 'x509'@'localhost';
GRANT ALL PRIVILEGES ON reporting.* TO 'reporting'@'localhost';
FLUSH PRIVILEGES;
EOF
msg_ok "Configured MariaDB databases and users"
mysql icingadb </usr/share/icingadb/schema/mysql/schema.sql || { msg_error "Failed to import IcingaDB schema"; exit 1; }
msg_ok "Imported IcingaDB schema"

sed -i "s/password: CHANGEME/password: ${ICINGA_DB_PW}/g" /etc/icingadb/config.yml || { msg_error "Failed to configure IcingaDB password"; exit 1; }
systemctl enable icingadb-redis icingadb --now || { msg_error "Failed to enable IcingaDB services"; exit 1; }
msg_ok "Configured IcingaDB daemon connection to mysql database"

icinga2 node setup --master --disable-confd > /dev/null || { msg_error "Failed to setup Icinga2 node"; exit 1; }
icinga2 feature enable icingadb > /dev/null || { msg_error "Failed to enable Icinga2 IcingaDB feature"; exit 1; }
ICINGA_API_ROOT_PW=$(grep 'password' /etc/icinga2/conf.d/api-users.conf | sed 's/.*password = \"//;s/"$//') || { msg_error "Failed to retrieve Icinga API password"; exit 1; }
usermod -aG icingaweb2 nagios || { msg_error "Failed to add nagios user to icingaweb2 group"; exit 1; }
systemctl restart icingadb icinga2 || { msg_error "Failed to restart Icinga2 or IcingaDB"; exit 1; }
msg_ok "Configured Icinga2 API"

msg_info "Configuring Icinga Web 2"
cat <<EOF >/etc/icingaweb2/config.ini || { msg_error "Failed to create Icinga Web 2 config.ini"; exit 1; }
[global]
show_stacktraces = "1"
show_application_state_messages = "1"
config_resource = "icingaweb_db"

[security]
use_strict_csp = "0"

[logging]
log = "syslog"
level = "ERROR"
application = "icingaweb2"
facility = "user"
EOF
cat <<EOF >/etc/icingaweb2/authentication.ini || { msg_error "Failed to create Icinga Web 2 authentication.ini"; exit 1; }
[icingaweb2]
backend = "db"
resource = "icingaweb_db"
EOF
cat <<EOF >/etc/icingaweb2/groups.ini || { msg_error "Failed to create Icinga Web 2 groups.ini"; exit 1; }
[icingaweb2]
backend = "db"
resource = "icingaweb_db"
EOF
cat <<EOF >/etc/icingaweb2/roles.ini
[Administrators]
users = "icingaadmin"
permissions = "*"
groups = "Administrators"
EOF

cat <<EOF >/etc/icingaweb2/resources.ini || { msg_error "Failed to create Icinga Web 2 resources.ini"; exit 1; }
[icingaweb_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "icingaweb"
username = "icingaweb"
password = "$ICINGAWEB_DB_PW"
use_ssl = "0"

[icingadb]
type = "db"
skip_validation = "0"
db = "mysql"
host = "localhost"
dbname = "icingadb"
username = "icingadb"
password = "$ICINGA_DB_PW"
charset = "utf8mb4"
use_ssl = "0"

[director_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "director"
username = "director"
password = "$DIRECTOR_DB_PW"
charset = "utf8"
use_ssl = "0"

[notifications]
type = "db"
db = "mysql"
host = "localhost"
dbname = "notifications"
username = "notifications"
password = "$NOTIFICATIONS_DB_PW"
use_ssl = "0"

[reporting_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "reporting"
username = "reporting"
password = "$REPORTING_DB_PW"
use_ssl = "0"

[x509_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "x509"
username = "x509"
password = "$X509_DB_PW"
use_ssl = "0"
EOF
chown www-data:icingaweb2 /etc/icingaweb2/*.ini || { msg_error "Failed to set permissions on Icinga Web 2 config files"; exit 1; }
chmod 660 /etc/icingaweb2/*.ini || { msg_error "Failed to set permissions on Icinga Web 2 config files"; exit 1; }
msg_ok "Created Icinga Web 2 config, resources, authentication, groups, and roles ini files"

msg_info "Configuring Icinga Director module"
icingacli module enable director || { msg_error "Failed to enable director module"; exit 1; }
mkdir -p /etc/icingaweb2/modules/director || { msg_error "Failed to create director module directory"; exit 1; }
cat <<EOF >/etc/icingaweb2/modules/director/config.ini || { msg_error "Failed to create director config.ini"; exit 1; }
[db]
resource = "director_db"
EOF
cat <<EOF >>/etc/icingaweb2/modules/director/kickstart.ini || { msg_error "Failed to create director kickstart.ini"; exit 1; }
[config]
endpoint = $FQDN
host = 127.0.0.1
port = 5665
username = root
password = $ICINGA_API_ROOT_PW
EOF
chown -R root:icingaweb2 /etc/icingaweb2/modules/director || { msg_error "Failed to set director permissions"; exit 1; }
chmod 660 /etc/icingaweb2/modules/director/*.ini || { msg_error "Failed to set director file permissions"; exit 1; }
icingacli director migration run || { msg_error "Failed to run director migration"; exit 1; }
icingacli director kickstart run || { msg_error "Failed to run director kickstart"; exit 1; }
systemctl reload icinga-director.service || { msg_error "Failed to reload Icinga Director"; exit 1; }
msg_ok "Configured Icinga Director module and kickstarted it"

msg_info "Configuring IcingaDB module"
icingacli module enable icingadb || { msg_error "Failed to enable icingadb module"; exit 1; }
mkdir -p /etc/icingaweb2/modules/icingadb || { msg_error "Failed to create icingadb module directory"; exit 1; }
cat <<EOF >>/etc/icingaweb2/modules/icingadb/commandtransports.ini || { msg_error "Failed to create commandtransports.ini"; exit 1; }
[icinga2]
skip_validation = "0"
transport = "api"
host = "localhost"
port = "5665"
username = "root"
password = "$ICINGA_API_ROOT_PW"
EOF
cat <<EOF >/etc/icingaweb2/modules/icingadb/config.ini || { msg_error "Failed to create icingadb config.ini"; exit 1; }
[icingadb]
resource = "icingadb"

[redis]
tls = "0"
EOF
cat <<EOF >/etc/icingaweb2/modules/icingadb/redis.ini || { msg_error "Failed to create icingadb redis.ini"; exit 1; }
[redis1]
host = "localhost"
EOF
chown -R root:icingaweb2 /etc/icingaweb2/modules/icingadb || { msg_error "Failed to set icingadb permissions"; exit 1; }
chmod 660 /etc/icingaweb2/modules/icingadb/*.ini || { msg_error "Failed to set icingadb file permissions"; exit 1; }
msg_ok "Configured IcingaDB module"

msg_info "Configuring Reporting module"
mkdir -p /etc/icingaweb2/modules/reporting || { msg_error "Failed to create reporting module directory"; exit 1; }
cat <<EOF > /etc/icingaweb2/modules/reporting/config.ini || { msg_error "Failed to create reporting config"; exit 1; }
[backend]
resource = "reporting_db"
EOF
chown -R root:icingaweb2 /etc/icingaweb2/modules/reporting || { msg_error "Failed to set reporting permissions"; exit 1; }
chmod 660 /etc/icingaweb2/modules/reporting/config.ini || { msg_error "Failed to set reporting file permissions"; exit 1; }
mysql reporting < /usr/share/icingaweb2/modules/reporting/schema/mysql.schema.sql || { msg_error "Failed to import reporting schema"; exit 1; }
msg_ok "Configured Reporting module"

msg_info "Configuring x509 module"
mysql x509 < /usr/share/icingaweb2/modules/x509/schema/mysql.schema.sql || { msg_error "Failed to import x509 schema"; exit 1; }
mkdir -p /etc/icingaweb2/modules/x509 || { msg_error "Failed to create x509 module directory"; exit 1; }
cat <<EOF > /etc/icingaweb2/modules/x509/config.ini || { msg_error "Failed to create x509 config"; exit 1; }
[backend]
resource = "x509_db"
EOF
chown -R root:icingaweb2 /etc/icingaweb2/modules/x509 || { msg_error "Failed to set x509 permissions"; exit 1; }
chmod 660 /etc/icingaweb2/modules/x509/config.ini || { msg_error "Failed to set x509 file permissions"; exit 1; }
icingacli module enable x509 || { msg_error "Failed to enable x509 module"; exit 1; }
msg_ok "Configured x509 module"

while true; do
    echo
    read -rp "Add a network to the x509 certificate module[Y/n]: " X509_LAN_CIDR
    X509_LAN_CIDR=${X509_LAN_CIDR:-y}
    if [[ "$X509_LAN_CIDR" == "y" ]]; then
        SUGGESTED_CIDR=$(ip r|grep link|grep -Po "^[\S]*"| head -n1)
        while true; do
            read -rp "Network cidr [$SUGGESTED_CIDR]: " X509_LAN_CIDR
            X509_LAN_CIDR=${X509_LAN_CIDR:-$SUGGESTED_CIDR}
            if [[ "$X509_LAN_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                break
            else
                echo "Error: '$X509_LAN_CIDR' is not a valid CIDR format."
                echo "Error: aaa.bbb.ccc.ddd/xy expected."
            fi
            break
        done

        X509_START_SCHEDULE=$(TZ="Europe/Paris" date -d "+1 minutes" +"%Y-%m-%dT%H:%M:%S.000000") || { msg_error "Failed to calculate X509 start schedule"; exit 1; }
        cat <<EOF > /etc/icingaweb2/modules/x509/jobs.ini || { msg_error "Failed to create x509 jobs.ini"; exit 1; }
[LAN]
cidrs = "$X509_LAN_CIDR"
ports = "443"
schedule = "{\"rrule\":\"FREQ=DAILY\",\"frequency\":\"DAILY\",\"start\":\"${X509_START_SCHEDULE}Europe\\/Paris\"}"
frequencyType = "ipl\\Scheduler\\RRule"
EOF
        chmod 660 /etc/icingaweb2/modules/x509/config.ini || { msg_error "Failed to set x509 jobs.ini permissions"; exit 1; }
        icingacli x509 migrate --author "proxmox init" || { msg_error "Failed to migrate x509 module"; exit 1; }
        systemctl restart icinga-x509.service || { msg_error "Failed to restart icinga-x509 service"; exit 1; }
        icingacli x509 import --file /etc/ssl/certs/ca-certificates.crt > /dev/null || { msg_error "Failed to import CA certificates"; exit 1; }
        icingacli x509 scan --job LAN --full || { msg_error "Failed to start x509 scan job"; exit 1; }
        break
    elif [[ "$X509_LAN_CIDR" == "n" ]]; then
        break
    fi
done
msg_ok "Set up x509 scan job"

msg_info "Configuring Notifications module"
mysql notifications < /usr/share/icinga-notifications/schema/mysql/schema.sql || { msg_error "Failed to import notifications schema"; exit 1; }
mkdir -p /etc/icingaweb2/modules/notifications || { msg_error "Failed to create notifications module directory"; exit 1; }
cat <<EOF >/etc/icingaweb2/modules/notifications/config.ini || { msg_error "Failed to create notifications config"; exit 1; }
[database]
resource = "notifications"
EOF
chown -R root:icingaweb2 /etc/icingaweb2/modules/notifications || { msg_error "Failed to set notifications permissions"; exit 1; }
chmod 660 /etc/icingaweb2/modules/notifications/config.ini || { msg_error "Failed to set notifications file permissions"; exit 1; }
sed -i "s/password: CHANGEME/password: ${NOTIFICATIONS_DB_PW}/g" /etc/icinga-notifications/config.yml || { msg_error "Failed to configure notifications password"; exit 1; }
sed -i "s/^icingaweb2-url: http.*/icingaweb2-url: http:\/\/${FQDN}\/icingaweb2/g" /etc/icinga-notifications/config.yml || { msg_error "Failed to configure notifications URL"; exit 1; }
systemctl restart icinga-desktop-notifications.service || msg_error "Warning: Failed to restart notifications service"
msg_ok "Configured notifications modules"

msg_info "Creating Icinga Web 2 initial admin user"
ICINGAWEB_ADMIN_PW_HASH=$(php -r "echo password_hash('$ICINGAWEB_ADMIN_PW', PASSWORD_DEFAULT);") || { msg_error "Failed to generate password hash"; exit 1; }
mysql -D icingaweb < /usr/share/icingaweb2/schema/mysql.schema.sql || { msg_error "Failed to import Icinga Web schema"; exit 1; }
mysql icingaweb -e "INSERT INTO icingaweb_user (name, active, password_hash)
          VALUES ('icingaadmin', 1, '$ICINGAWEB_ADMIN_PW_HASH');" || { msg_error "Failed to create Icinga Web admin user"; exit 1; }
msg_ok "Configured Icingaweb initial user"

msg_info "Importing Icinga Director Linuxfabrik monitoring basket"
$STD git clone https://github.com/Linuxfabrik/monitoring-plugins.git /opt/monitoring-plugins || { msg_error "Failed to clone Linuxfabrik monitoring plugins"; exit 1; }
cd /opt/monitoring-plugins || { msg_error "Failed to change to monitoring plugins directory"; exit 1; }
#git checkout v2.2.1 || { msg_error "Failed to checkout monitoring plugins version"; exit 1; }
tools/basket-join > /dev/null || { msg_error "Failed to join basket"; exit 1; }
icingacli director basket restore < icingaweb2-module-director-basket.json > /dev/null || { msg_error "Failed to restore director basket"; exit 1; }
msg_ok "Imported Icinga Director Linuxfabrik monitoring basket"

icingacli director host create "$FQDN" --json "{
    \"address\": \"127.0.0.1\",
    \"imports\": [
        \"tpl-host-linux\"
    ],
    \"object_type\": \"object\",
    \"vars\": {
        \"_override_servicevars\": {
            \"Icinga Top Flapping Services\": {
                \"icinga_topflap_services_password\": \"$ICINGAWEB_ADMIN_PW\",
                \"icinga_topflap_services_url\": \"http://localhost/icingaweb2/icingadb/history?limit=250\",
                \"icinga_topflap_services_username\": \"icingaadmin\"
            },
            \"Redis Status\": {
                \"redis_status_port\": \"6380\"
            },
            \"Systemd Unit - redis.service\": {
                \"systemd_unit_unit\": \"icingadb-redis\"
            }
        },
        \"tags\": [
            \"icinga2\",
            \"mariadb\",
            \"icingadb\",
            \"redis\",
            \"debian13\"
        ]
    }
}" > /dev/null || { msg_error "Failed to create Icinga Director host"; exit 1; }
msg_ok "Created Icinga Director host for local container"
msg_info "Importing Icinga Director x509 monitoring basket"
base64 -d <<'EOF' | gunzip -c | icingacli director basket restore > /dev/null || { msg_error "Failed to restore x509 basket"; exit 1; }
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
K9+8ev4Ps1OGN+0bAAA=
EOF
msg_ok "Imported Icinga Director x509 monitoring basket"

msg_info "Running Icinga Director import and sync"
icingacli director importsource run --id 1 > /dev/null || { msg_error "Failed to run import source"; exit 1; }
icingacli director syncrule run --id 1 > /dev/null || { msg_error "Failed to run sync rule"; exit 1; }
icingacli director config deploy > /dev/null || { msg_error "Failed to deploy Icinga Director configuration"; exit 1; }
msg_ok "Deployed Icinga Director configuration"

msg_info "Installing Icinga Proxmox VE tools"
$STD git clone https://github.com/nbuchwitz/icingaweb2-module-pve /usr/share/icingaweb2/modules/pve || { msg_error "Failed to clone Proxmox VE module"; exit 1; }
$STD wget  https://raw.githubusercontent.com/nbuchwitz/check_pve/refs/heads/main/check_pve.py -O /usr/lib64/nagios/plugins/check_pve.py || { msg_error "Failed to download check_pve.py"; exit 1; }
chmod +x /usr/lib64/nagios/plugins/check_pve.py || { msg_error "Failed to set check_pve.py executable"; exit 1; }
mkdir -p /etc/icinga2/zones.d/global-templates || { msg_error "Failed to create Icinga2 templates directory"; exit 1; }
$STD wget https://raw.githubusercontent.com/nbuchwitz/check_pve/refs/heads/main/icinga2/command.conf -O /etc/icinga2/zones.d/global-templates/commands-pve.conf || { msg_error "Failed to download Proxmox VE commands"; exit 1; }
icingacli module enable pve > /dev/null || { msg_error "Failed to enable PVE module"; exit 1; }
systemctl reload icinga2 || { msg_error "Failed to reload Icinga2"; exit 1; }
icingacli director kickstart run || { msg_error "Failed to run director kickstart"; exit 1; }
msg_ok "Installed and enabled nbuchwitz's Proxmox VE module and plugin"

msg_info "Installing Icinga Web 2 map module"
$STD git clone https://github.com/nbuchwitz/icingaweb2-module-map.git /usr/share/icingaweb2/modules/map || { msg_error "Failed to clone Maps module"; exit 1; }
icingacli module enable map || { msg_error "Failed to enable maps module"; exit 1; }
msg_ok "Installed and enabled nbuchwitz's map module"

msg_info "Enabling additional Icinga Web 2 modules"
icingacli module enable businessprocess > /dev/null || msg_error "Warning: Failed to enable businessprocess module"
icingacli module enable cube > /dev/null || msg_error "Warning: Failed to enable cube module"
icingacli module enable incubator > /dev/null || msg_error "Warning: Failed to enable incubator module"
icingacli module enable director > /dev/null || msg_error "Warning: Failed to enable director module"
icingacli module disable setup > /dev/null || msg_error "Warning: Failed to disable setup module"
msg_ok "Enabled additional Icinga Web 2 modules"
echo "--- InfluxDB connection for PerfData ---"
while true; do
    read -rp "Use remote InfluxDB server? (y/n): " INFLUX_REMOTE
    if [[ "$INFLUX_REMOTE" == "y" || "$INFLUX_REMOTE" == "n" ]]; then break; fi
done
if [[ "$INFLUX_REMOTE" == "y" ]]; then

    while true; do
        read -rp "Which InfluxDB version to use? (1/[2]): " INFLUX_VER
        INFLUX_VER=${INFLUX_VER:-2}
        if [[ "$INFLUX_VER" == "1" || "$INFLUX_VER" == "2" ]]; then break; fi
    done

    while true; do
        read -rp "Remote InfluxDB http procotcol (http/[https]): " INFLUX_PROTO
        INFLUX_PROTO=${INFLUX_PROTO:-https}
        if [[ "$INFLUX_PROTO" == "http" || "$INFLUX_PROTO" == "https" ]]; then break; fi
    done
    if [[ "$INFLUX_PROTO" == "https" ]]; then
        echo "Ensure that your InfluxDB server has a valid SSL certificate!"
        while true; do
            read -rp "Allow insecure SSL connection? (y/N): " INFLUX_SSL_INSECURE
            INFLUX_SSL_INSECURE=${INFLUX_SSL_INSECURE:-n}
            if [[ "$INFLUX_SSL_INSECURE" == "y" || "$INFLUX_SSL_INSECURE" == "n" ]]; then break; fi
        done
        if [[ "$INFLUX_SSL_INSECURE" == "y" ]]; then
            INFLUX_SSL_INSECURE_BOOL="true"
            INFLUX_SSL_INSECURE_NUM="1"
        fi
        INFLUX_SSL_ENABLE="true"
    fi
    read -rp "Remote InfluxDB hostname (e.g. [influxdb]): " INFLUX_HOST
    INFLUX_HOST=${INFLUX_HOST:-influxdb}
    read -rp "Remote InfluxDB port (e.g. [8086]): " INFLUX_PORT
    INFLUX_PORT=${INFLUX_PORT:-8086}
    read -rp "Bucket or database name for Icinga (e.g. [icinga]): " INFLUX_BUCKET
    INFLUX_BUCKET=${INFLUX_BUCKET:-icinga}

    if [[ "$INFLUX_VER" == "1" ]]; then
        echo "Configuring InfluxDB v1 connection"
        read -rp "InfluxDB username: " INFLUX_USER
        read -rsp "InfluxDB password: " INFLUX_PW;
        cat <<EOF >/etc/icinga2/features-available/influxdb.conf || { msg_error "Failed to create InfluxDB v1 config"; exit 1; }
object InfluxdbWriter "influxdb" {
host = "$INFLUX_HOST"
port = $INFLUX_PORT
database = "$INFLUX_BUCKET"
username = "$INFLUX_USER"
password = "$INFLUX_PW"
ssl_enable = ${INFLUX_SSL_ENABLE:-false}
ssl_insecure_noverify = ${INFLUX_SSL_INSECURE_BOOL:-false}
flush_threshold = 1024
flush_interval = 10s
host_template = {
    measurement = "\$host.check_command\$"
    tags = {
    hostname = "\$host.name\$"
    }
}
service_template = {
    measurement = "\$service.check_command\$"
    tags = {
    hostname = "\$host.name\$"
    }
}
}
EOF
        mkdir -p /etc/icingaweb2/modules/perfdatagraphsinfluxdbv1 || { msg_error "Failed to create InfluxDB v1 module directory"; exit 1; }
        cat <<EOF >/etc/icingaweb2/modules/perfdatagraphsinfluxdbv1/config.ini || { msg_error "Failed to create InfluxDB v1 config.ini"; exit 1; }
[influx]
api_url = "$INFLUX_PROTO://$INFLUX_HOST:$INFLUX_PORT"
api_database = "$INFLUX_BUCKET"
api_username = "$INFLUX_USER"
api_password = "$INFLUX_PW"
api_tls_insecure = "${INFLUX_SSL_INSECURE_NUM:-0}"
EOF
        chown -R root:icingaweb2 /etc/icingaweb2/modules/perfdatagraphsinfluxdbv1 || { msg_error "Failed to set InfluxDB v1 module permissions"; exit 1; }
        chmod 660 /etc/icingaweb2/modules/perfdatagraphsinfluxdbv1/config.ini || { msg_error "Failed to set InfluxDB v1 config.ini permissions"; exit 1; }
        icingacli module enable perfdatagraphs > /dev/null || { msg_error "Failed to enable perfdatagraphs module"; exit 1; }
        icingacli module enable perfdatagraphsinfluxdbv1 > /dev/null || { msg_error "Failed to enable perfdatagraphsinfluxdbv1 module"; exit 1; }
        msg_ok "Configured InfluxDB v1 connection for PerfData module"
    else
        echo "Configuring InfluxDB v2 connection"
        read -rp "Organization (org) name [icinga]: " INFLUX_ORG
        INFLUX_ORG=${INFLUX_ORG:-icinga}
        read -rp "InfluxDB token: " INFLUX_TOKEN

        mkdir -p /etc/icingaweb2/modules/perfdatagraphsinfluxdbv2 || { msg_error "Failed to create InfluxDB v2 module directory"; exit 1; }
        cat <<EOF >/etc/icingaweb2/modules/perfdatagraphsinfluxdbv2/config.ini || { msg_error "Failed to create InfluxDB v2 config.ini"; exit 1; }
[influx]
api_url = "$INFLUX_PROTO://$INFLUX_HOST:$INFLUX_PORT"
api_org = "$INFLUX_ORG"
api_bucket = "$INFLUX_BUCKET"
api_token = "$INFLUX_TOKEN"
api_tls_insecure = "${INFLUX_SSL_INSECURE_NUM:-0}"
EOF
        chown -R root:icingaweb2 /etc/icingaweb2/modules/perfdatagraphsinfluxdbv2 || { msg_error "Failed to set InfluxDB v2 module permissions"; exit 1; }
        chmod 660 /etc/icingaweb2/modules/perfdatagraphsinfluxdbv2/config.ini || { msg_error "Failed to set InfluxDB v2 config.ini permissions"; exit 1; }
        msg_ok "Configured InfluxDB v2 connection for PerfData module"

        cat <<EOF >/etc/icinga2/features-available/influxdb2.conf || { msg_error "Failed to create InfluxDB v2 config"; exit 1; }
object Influxdb2Writer "influxdb2" {
host = "$INFLUX_HOST"
port = $INFLUX_PORT
organization = "$INFLUX_ORG"
bucket = "$INFLUX_BUCKET"
auth_token = "$INFLUX_TOKEN"
ssl_enable = ${INFLUX_SSL_ENABLE:-false}
ssl_insecure_noverify = ${INFLUX_SSL_INSECURE_BOOL:-false}
flush_threshold = 1024
flush_interval = 10s
host_template = {
    measurement = "\$host.check_command\$"
    tags = {
    hostname = "\$host.name\$"
    }
}
service_template = {
    measurement = "\$service.check_command\$"
    tags = {
    hostname = "\$host.name\$"
    }
}
}
EOF
        icingacli module enable perfdatagraphs > /dev/null || { msg_error "Failed to enable perfdatagraphs module"; exit 1; }
        icingacli module enable perfdatagraphsinfluxdbv2 > /dev/null || { msg_error "Failed to enable perfdatagraphsinfluxdbv2 module"; exit 1; }
        msg_ok "Configured InfluxDB v2 connection"
    fi
    icinga2 feature enable influxdb${INFLUX_VER} > /dev/null || { msg_error "Failed to enable InfluxDB feature in Icinga2"; exit 1; }
    systemctl restart icinga2 || { msg_error "Failed to restart Icinga2 after InfluxDB config"; exit 1; }
    msg_ok "Enabled InfluxDB connection from iciniga2 Core"
else
    msg_ok "Skipped InfluxDB configuration"
fi

msg_info "Adding some extra Icinga Web 2 themes"
$STD wget -O /usr/share/icingaweb2/public/css/themes/dark-theme.less https://raw.githubusercontent.com/lazaroblanc/icingaweb2-dark-theme/master/dark-theme.less || { msg_error "Failed to download dark theme"; exit 1; }
$STD git clone https://github.com/Al2Klimov/icingaweb2-theme-apocalypse.git /usr/share/icingaweb2/modules/apocalypse || { msg_error "Failed to clone apocalypse theme"; exit 1; }
icingacli module enable apocalypse > /dev/null || { msg_error "Failed to enable apocalypse theme"; exit 1; }
chown www-data:icingaweb2 /etc/icingaweb2/modules/* || { msg_error "Failed to set permissions on modules"; exit 1; }
msg_ok "Added some extra themes"


echo "--- Database credentials ---"
echo "IcingaDB name:    icingadb"
echo "IcingaDB user:     icingadb"
echo "IcingaDB password: $ICINGA_DB_PW"
echo "IcingaWeb2 DB name:    icingaweb"
echo "IcingaWeb2 user:   icingaweb"
echo "IcingaWeb2 password: $ICINGAWEB_DB_PW"
echo "Notifications DB name:    notifications"
echo "Notifications user: notifications"
echo "Notifications password: $NOTIFICATIONS_DB_PW"
echo "Director DB name:    director"
echo "Director user: director"
echo "Director password: $DIRECTOR_DB_PW"
echo "x509 DB name:    x509"
echo "x509 user: x509"
echo "x509 password: $X509_DB_PW"
echo "Reporting DB name:    reporting"
echo "Reporting user: reporting"
echo "Reporting password: $REPORTING_DB_PW"
echo "--- Web credentials ---"
echo "Icingaweb initial user: icingaadmin"
echo "Icingaweb initial password: $ICINGAWEB_ADMIN_PW"

msg_ok "Configured Icinga"

motd_ssh
customize
cleanup_lxc

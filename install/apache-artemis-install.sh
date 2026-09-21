#!/usr/bin/env bash

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os


ARTEMIS_USER=artemis
ARTEMIS_USER_HOME_BASE=/opt
ARTEMIS_USER_HOME_DIR=${ARTEMIS_USER_HOME_BASE}/${ARTEMIS_USER}
ARTEMIS_USER_LOGIN_SHELL=/bin/bash
ARTEMIS_USER_COMMENT='Apache Artemis Broker'
ARTEMIS_MIN_JAVA_VERSION=17
ARTEMIS_BINARY_DOWNLOAD_URL_PREFIX=https://dlcdn.apache.org/artemis/artemis
ARTEMIS_VERSION=2.57.0
ARTEMIS_BINARY_FILE_NAME=apache-artemis-${ARTEMIS_VERSION}-bin.tar.gz
ARTEMIS_BINARY_DOWNLOAD_URL=${ARTEMIS_BINARY_DOWNLOAD_URL_PREFIX}/${ARTEMIS_VERSION}/${ARTEMIS_BINARY_FILE_NAME}

ARTEMIS_BINARY_CHECSUM_DOWNLOAD_URL_PREFIX=https://downloads.apache.org/artemis/artemis
ARTEMIS_BINARY_CHECKSUM_FILE_NAME=${ARTEMIS_BINARY_FILE_NAME}.sha512
ARTEMIS_BINARY_CHECKSUM_DOWNLOAD_URL=${ARTEMIS_BINARY_CHECSUM_DOWNLOAD_URL_PREFIX}/${ARTEMIS_VERSION}/${ARTEMIS_BINARY_CHECKSUM_FILE_NAME}

ARTEMIS_DOWNLOAD_PATH=/tmp
ARTEMIS_HOME=${ARTEMIS_USER_HOME_DIR}/apache-artemis-${ARTEMIS_VERSION}
ARTEMIS_BIN=${ARTEMIS_HOME}/bin

BROKER_NAME=test_broker
BROKER_DIR=${ARTEMIS_USER_HOME_DIR}/${BROKER_NAME}
BROKER_BIN=${BROKER_DIR}/bin
BROKER_USER=artemis
BROKER_PASSWORD=$(openssl rand 600 | tr -dc 'a-zA-Z0-9#^-_+=' | cut -c1-16)

BROKER_SERVICE_UNIT_FILE=${BROKER_NAME}.service
BROKER_SERVICE_UNIT_FILE_PATH=/etc/systemd/system



setup_java
java -version
msg_ok "Java installation completed"



# Download artemis binary
[ -f ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_FILE_NAME} ] || curl ${ARTEMIS_BINARY_DOWNLOAD_URL} --output ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_FILE_NAME}
msg_ok "Apache Artemis downloaded"
[ -f ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_CHECKSUM_FILE_NAME} ] || curl ${ARTEMIS_BINARY_CHECKSUM_DOWNLOAD_URL} --output ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_CHECKSUM_FILE_NAME}
msg_ok "Apache Artemis integrity checksum downloaded"
cd ${ARTEMIS_DOWNLOAD_PATH} &&	sha512sum -c ${ARTEMIS_BINARY_CHECKSUM_FILE_NAME}
msg_ok "Checksum verified"



# Create artemis user. home dir /opt/artemis
id ${ARTEMIS_USER} || useradd -m -b ${ARTEMIS_USER_HOME_BASE} -s ${ARTEMIS_USER_LOGIN_SHELL} -c "${ARTEMIS_USER_COMMENT}" ${ARTEMIS_USER}
msg_ok "\"artemis\" user and group created"
id -a ${ARTEMIS_USER}



# explode the packaging into /opt/artemis
cd ${ARTEMIS_USER_HOME_DIR} && tar -xf ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_FILE_NAME}

rm ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_FILE_NAME}
rm ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_CHECKSUM_FILE_NAME}

msg_ok "Exploded Apache Artemis"



# Change permission of /opt/artemis
chown -R ${ARTEMIS_USER}:${ARTEMIS_USER} ${ARTEMIS_HOME}
chmod -R 000 ${ARTEMIS_HOME}
chmod -R ug+rw ${ARTEMIS_HOME}
find ${ARTEMIS_HOME} -type d -exec chmod ug+x {} \;
chmod ug+x ${ARTEMIS_HOME}/bin/artemis
msg_ok "Permissions and ownership of ${ARTEMIS_HOME} set."


${ARTEMIS_HOME}/bin/artemis create --verbose --name ${BROKER_NAME} --require-login --user ${BROKER_USER} --password ${BROKER_PASSWORD} ${BROKER_DIR} 2>&1 > /tmp/${BROKER_NAME}_broker_creation.log
msg_ok "${BROKER_NAME} broker created."



chmod -R 000 ${BROKER_DIR}
chown -R ${ARTEMIS_USER}:${ARTEMIS_USER} ${BROKER_DIR}
chmod ug+x ${BROKER_DIR}
find ${BROKER_DIR} -type d -exec chmod ug+rwx {} \;
find ${BROKER_DIR} -type f -exec chmod ug+r {} \;
find ${BROKER_DIR} -type f -exec chmod u+w {} \;
chmod u+x ${BROKER_BIN}/artemis ${BROKER_BIN}/artemis-service
msg_ok "Permissions and ownership of broker at ${BROKER_DIR} set."




echo > ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}


echo "
[Unit]
Description=Apache Artemis Broker
After=network.target

[Service]
Type=forking
User=artemis
WorkingDirectory=${BROKER_DIR}
ExecStart=${BROKER_BIN}/artemis-service start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
" >  ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}

systemctl enable ${BROKER_NAME}
msg_ok "${BROKER_NAME} service created."

apt-get install -y tmux

echo "" >> ${BROKER_DIR}/etc/artemis.profile
echo "# Embedded web server should listen on 0.0.0.0. By default it listens on localhost" >> ${BROKER_DIR}/etc/artemis.profile
echo 'JAVA_ARGS="$JAVA_ARGS -Dbroker.host=0.0.0.0"' >> ${BROKER_DIR}/etc/artemis.profile

cp ${BROKER_DIR}/etc/bootstrap.xml /tmp/
cp ${BROKER_DIR}/etc/bootstrap.xml ${BROKER_DIR}/etc/bootstrap.xml.bak
sed 's/localhost/${broker.host}/' /tmp/bootstrap.xml > ${BROKER_DIR}/etc/bootstrap.xml
rm /tmp/bootstrap.xml

# Jolokia should allow requests originating from all (*) origins.
cp ${BROKER_DIR}/etc/jolokia-access.xml /tmp/
cp ${BROKER_DIR}/etc/jolokia-access.xml ${BROKER_DIR}/etc/jolokia-access.xml.bak
sed 's/localhost//' /tmp/jolokia-access.xml > ${BROKER_DIR}/etc/jolokia-access.xml
rm /tmp/jolokia-access.xml

echo "${BROKER_PASSWORD}" > ${BROKER_DIR}/.secret
msg_ok "Broker password saved in ${BROKER_DIR}/.secret"

msg_ok "Broker user: ${BROKER_USER}"
msg_ok "Broker password: ${BROKER_PASSWORD}"


service ${BROKER_NAME} start
msg_ok "${BROKER_NAME} broker started."


motd_ssh
cleanup_lxc

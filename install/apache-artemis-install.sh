#!/usr/bin/env bash

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_variables(){
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
	  BROKER_USER=user_used_by_broker_clients
	  BROKER_PASSWORD=user_used_by_broker_clients

	  BROKER_SERVICE_UNIT_FILE=${BROKER_NAME}.service
    BROKER_SERVICE_UNIT_FILE_PATH=/etc/systemd/system
}

install_java(){
  setup_java
  java -version
  msg_ok "Java installation completed"
}

download_apache_artemis(){
  # Download artemis binary
  [ -f ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_FILE_NAME} ] || curl ${ARTEMIS_BINARY_DOWNLOAD_URL} --output ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_FILE_NAME}
  msg_ok "Apache Artemis downloaded"
  [ -f ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_CHECKSUM_FILE_NAME} ] || curl ${ARTEMIS_BINARY_CHECKSUM_DOWNLOAD_URL} --output ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_CHECKSUM_FILE_NAME}
  msg_ok "Apache Artemis integrity checksum downloaded"
  cd ${ARTEMIS_DOWNLOAD_PATH} &&	sha512sum -c ${ARTEMIS_BINARY_CHECKSUM_FILE_NAME}
  msg_ok "Checksum verified"
}

setup_artemis_user(){
  # Create artemis user. home dir /opt/artemis
  id ${ARTEMIS_USER} || useradd -m -b ${ARTEMIS_USER_HOME_BASE} -s ${ARTEMIS_USER_LOGIN_SHELL} -c "${ARTEMIS_USER_COMMENT}" ${ARTEMIS_USER}
  msg_ok "\"artemis\" user and group created"
  id -a ${ARTEMIS_USER}
}

explode_apache_artemis(){
  # explode the packaging into /opt/artemis
  cd ${ARTEMIS_USER_HOME_DIR} && tar -xf ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_FILE_NAME}

  rm ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_FILE_NAME}
  rm ${ARTEMIS_DOWNLOAD_PATH}/${ARTEMIS_BINARY_CHECKSUM_FILE_NAME}

  msg_ok "Exploded Apache Artemis"
}

setup_ownership_and_permissions_for_artemis(){
  # Change permission of /opt/artemis
  chown -R ${ARTEMIS_USER}:${ARTEMIS_USER} ${ARTEMIS_HOME}
  chmod -R 000 ${ARTEMIS_HOME}
  chmod -R ug+rw ${ARTEMIS_HOME}
  find ${ARTEMIS_HOME} -type d -exec chmod ug+x {} \;
  # find ${ARTEMIS_HOME} -type f -name '*.sh' -exec chmod ug+x {} \; # There are no shell scripts with .sh.
  chmod ug+x ${ARTEMIS_HOME}/bin/artemis
  msg_ok "Permissions and ownership of ${ARTEMIS_HOME} set."
}

create_broker(){
  ${ARTEMIS_HOME}/bin/artemis create --verbose --name ${BROKER_NAME} --require-login --user ${BROKER_USER} --password ${BROKER_PASSWORD} ${BROKER_DIR} 2>&1 > /tmp/${BROKER_NAME}_broker_creation.log
  msg_ok "${BROKER_NAME} broker created."
}

setup_ownership_and_permissions_for_broker(){
  chmod -R 000 ${BROKER_DIR}
  chown -R ${ARTEMIS_USER}:${ARTEMIS_USER} ${BROKER_DIR}
  chmod ug+x ${BROKER_DIR}
  find ${BROKER_DIR} -type d -exec chmod ug+rwx {} \;
  find ${BROKER_DIR} -type f -exec chmod ug+r {} \;
  find ${BROKER_DIR} -type f -exec chmod u+w {} \;
  chmod u+x ${BROKER_BIN}/artemis ${BROKER_BIN}/artemis-service
  msg_ok "Permissions and ownership of broker at ${BROKER_DIR} set."
}

setup_broker_service(){
  # Create a Systemd Service Unit file to start/stop/restart artemis
#  service ${BROKER_NAME} stop
#  systemctl disable ${BROKER_NAME}
#  rm ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo > ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}

	echo "[Unit]"                                               >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "Description=Apache Artemis Broker"                    >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "After=network.target"                                 >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo ""                                                     >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "[Service]"                                            >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "Type=forking"                                         >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "User=artemis"                                         >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "WorkingDirectory=${BROKER_DIR}"                       >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "EnvironmentFile="                                     >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "EnvironmentFile="                                     >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "ExecStart=${BROKER_BIN}/artemis-service start"        >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "Restart=on-failure"                                   >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "RestartSec=5"                                         >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo ""                                                     >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "[Install]"                                            >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}
 	echo "WantedBy=multi-user.target"                           >> ${BROKER_SERVICE_UNIT_FILE_PATH}/${BROKER_SERVICE_UNIT_FILE}

 	systemctl enable ${BROKER_NAME}
 	msg_ok "${BROKER_NAME} service created."
}

start_broker(){
  service ${BROKER_NAME} start
  msg_ok "${BROKER_NAME} broker started."
}

install_tmux(){
  apt-get install -y tmux
}

configure_embedded_web_server(){
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
}

setup_variables
install_java
download_apache_artemis
setup_artemis_user
explode_apache_artemis
create_broker
configure_embedded_web_server
setup_broker_service
setup_ownership_and_permissions_for_artemis
setup_ownership_and_permissions_for_broker
start_broker
install_tmux

motd_ssh
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tanansatpal
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://kafka.apache.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

JAVA_VERSION="21" setup_java

msg_info "Creating Apache kafka system user"
groupadd --system kafka
useradd --system --gid kafka --home-dir /opt/kafka \
        --shell /usr/sbin/nologin kafka
msg_ok "Created Apache kafka system user"

msg_info "Downloading Apache Kafka"
KAFKA_VERSION=$(curl -fsSL https://downloads.apache.org/kafka/ \
  | grep -oP '(?<=href=")[0-9]+\.[0-9]+\.[0-9]+(?=/")' \
  | sort -V | tail -1)
if [[ -z "${KAFKA_VERSION}" ]]; then
  msg_error "Failed to resolve latest Apache Kafka version"
  exit 1
fi
SCALA_VERSION=$(curl -fsSL "https://downloads.apache.org/kafka/${KAFKA_VERSION}/" \
  | grep -oP 'kafka_\K[0-9]+\.[0-9]+(?=-)' | sort -V | tail -1)
TARBALL="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
cd /tmp
$STD curl -fsSLO "https://downloads.apache.org/kafka/${KAFKA_VERSION}/${TARBALL}"
tar -xzf "${TARBALL}" -C /opt
mv "/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}" /opt/kafka
rm -f "/tmp/${TARBALL}"
echo "${KAFKA_VERSION}" >/opt/kafka/.version
mkdir -p /var/lib/kafka/data /var/log/kafka
chown -R kafka:kafka /opt/kafka /var/lib/kafka /var/log/kafka
msg_ok "Downloaded Apache Kafka v${KAFKA_VERSION}"

msg_info "Configuring KRaft broker"
NODE_ID=1
LISTENER_PORT=9092
CONTROLLER_PORT=9093

cat <<EOF >/opt/kafka/config/server.properties
# ---- Process roles ---------------------------------------------------------
process.roles=broker,controller
node.id=${NODE_ID}
controller.quorum.voters=${NODE_ID}@localhost:${CONTROLLER_PORT}

# ---- Listeners -------------------------------------------------------------
listeners=PLAINTEXT://0.0.0.0:${LISTENER_PORT},CONTROLLER://0.0.0.0:${CONTROLLER_PORT}
advertised.listeners=PLAINTEXT://${LOCAL_IP}:${LISTENER_PORT}
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL

# ---- Storage ---------------------------------------------------------------
log.dirs=/var/lib/kafka/data
num.partitions=3
default.replication.factor=1
min.insync.replicas=1
auto.create.topics.enable=true

# ---- Internal-topic replication (single-node safe) -------------------------
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
share.coordinator.state.topic.replication.factor=1
share.coordinator.state.topic.min.isr=1

# ---- Retention -------------------------------------------------------------
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

# ---- Threading -------------------------------------------------------------
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
num.recovery.threads.per.data.dir=1
EOF
chown kafka:kafka /opt/kafka/config/server.properties
msg_ok "Configured KRaft broker"

msg_info "Formatting Apache Kafka storage"
CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
runuser -u kafka -- /opt/kafka/bin/kafka-storage.sh format \
  --cluster-id "${CLUSTER_ID}" \
  --config /opt/kafka/config/server.properties \
  --ignore-formatted >/dev/null
msg_ok "Formatted storage (cluster-id: ${CLUSTER_ID})"

msg_info "Tuning JVM heap"
cat <<'EOF' >/opt/kafka/config/kafka-env.sh
KAFKA_HEAP_OPTS="-Xms512M -Xmx1G"
KAFKA_JVM_PERFORMANCE_OPTS="-server -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:+ExplicitGCInvokesConcurrent -XX:MaxInlineLevel=15 -Djava.awt.headless=true"
LOG_DIR=/var/log/kafka
EOF
chown kafka:kafka /opt/kafka/config/kafka-env.sh
msg_ok "Tuned JVM heap"

msg_info "Creating systemd service"
cat <<'EOF' >/etc/systemd/system/kafka.service
[Unit]
Description=Apache Kafka (KRaft mode)
Documentation=https://kafka.apache.org/documentation/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=kafka
Group=kafka
EnvironmentFile=/opt/kafka/config/kafka-env.sh
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=100000
SuccessExitStatus=143
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now kafka
msg_ok "Created systemd service"

msg_info "Linking Apache Kafka CLI tools into /usr/local/bin"
for tool in /opt/kafka/bin/*.sh; do
  ln -sf "${tool}" "/usr/local/bin/$(basename "${tool}" .sh)"
done
msg_ok "Linked CLI tools"

msg_info "Saving cluster info"
{
  echo "Apache Kafka Version:       ${KAFKA_VERSION}"
  echo "Cluster ID:          ${CLUSTER_ID}"
  echo "Node ID:             ${NODE_ID}"
  echo "Bootstrap Server:    ${LOCAL_IP}:${LISTENER_PORT}"
  echo "Controller Quorum:   ${NODE_ID}@localhost:${CONTROLLER_PORT}"
  echo "Data Directory:      /var/lib/kafka/data"
  echo "Log Directory:       /var/log/kafka"
  echo "Config:              /opt/kafka/config/server.properties"
} >/root/kafka.creds
chmod 600 /root/kafka.creds
msg_ok "Saved cluster info to /root/kafka.creds"

msg_info "Verifying Apache Kafka startup"
sleep 5
if ! systemctl is-active --quiet kafka; then
  msg_error "Apache Kafka failed to start — check 'journalctl -u kafka'"
  exit 1
fi
msg_ok "Apache Kafka is running (listening on ${LISTENER_PORT})"

motd_ssh
customize
cleanup_lxc

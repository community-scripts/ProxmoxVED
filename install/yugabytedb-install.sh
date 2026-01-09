#!/usr/bin/env bash

# Copyright (c) 2021-2026 bandogora
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.yugabyte.com/yugabytedb/

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;sudo;mc)
msg_info "Installing Dependencies"
$STD dnf install -y \
  curl \
  sudo \
  mc \
  file \
  jq \
  bind-utils \
  diffutils \
  gettext \
  glibc-all-langpacks \
  glibc-langpack-en \
  glibc-locale-source \
  iotop \
  less \
  ncurses-devel \
  net-tools \
  openssl \
  openssl-devel \
  redhat-rpm-config \
  rsync \
  procps \
  python3.11 \
  python3.11-devel \
  python3.11-pip \
  sysstat \
  tcpdump \
  which \
  binutils \
  tar \
  chrony
msg_ok "Installed Dependencies"

msg_info "Restarting chronyd in container mode"
# Start chronyd with the -x option to disable the control of the system clock
sed -i 's/^\(OPTIONS=".*\)"/\1 -x"/' /etc/sysconfig/chronyd

if systemctl restart chronyd; then
  msg_ok "chronyd running correctly"
else
  msg_error "Failed to restart chronyd"
  journalctl -xeu chronyd.service
  exit 1
fi

msg_info "Installing Python3 Dependencies"
# Make sure python 3.11 is used when calling python or python3
alternatives --install /usr/bin/python python /usr/bin/python3.11 99
alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 99
# Install required packages globally
$STD python3 -m pip install --upgrade pip --root-user-action=ignore
$STD python3 -m pip install --upgrade lxml --root-user-action=ignore
$STD python3 -m pip install --upgrade s3cmd --root-user-action=ignore
$STD python3 -m pip install --upgrade psutil --root-user-action=ignore
msg_ok "Installed Python3 Dependencies"

msg_info "Setting ENV variables"
DATA_DIR="$YB_HOME/var/data"
YB_MANAGED_DEVOPS_USE_PYTHON3=1
YB_DEVOPS_USE_PYTHON3=1
BOTO_PATH=$YB_HOME/.boto/config
AZCOPY_JOB_PLAN_LOCATION=/tmp/azcopy/jobs-plan
AZCOPY_LOG_LOCATION=/tmp/azcopy/logs

cat >/etc/environment <<EOF
YB_SERIES=$YB_SERIES
YB_HOME=$YB_HOME
DATA_DIR=$DATA_DIR
YB_MANAGED_DEVOPS_USE_PYTHON3=$YB_MANAGED_DEVOPS_USE_PYTHON3
YB_DEVOPS_USE_PYTHON3=$YB_DEVOPS_USE_PYTHON3
BOTO_PATH=$BOTO_PATH
AZCOPY_JOB_PLAN_LOCATION=$AZCOPY_JOB_PLAN_LOCATION
AZCOPY_LOG_LOCATION=$AZCOPY_LOG_LOCATION
EOF
msg_ok "Set ENV variables"

msg_info "Creating yugabyte user"
mkdir -p "$YB_HOME"
useradd --home-dir "$YB_HOME" \
  --uid 10001 \
  yugabyte
msg_ok "Created yugabyte user"

msg_info "Setup ${APP}"
# Create data dirs from ENV vars
mkdir -p "$DATA_DIR"

# Set working dir
cd "$YB_HOME" || exit

# Get latest version and build number for our series
read -r VERSION RELEASE < <(
  curl -fsSL https://github.com/yugabyte/yugabyte-db/raw/refs/heads/master/docs/data/currentVersions.json |
    jq -r ".dbVersions[] | select(.series == \"${YB_SERIES}\") | [.version, .appVersion] | @tsv"
)
curl -OfsSL "https://software.yugabyte.com/releases/${VERSION}/yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"

tar -xzf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz" --strip 1
rm -rf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"
# Run post install
./bin/post_install.sh
tar -xzf share/ybc-*.tar.gz
rm -rf ybc-*/conf/
# yugabyted expects yb-controller-server file in ybc/bin
mv ybc-* ybc

# Strip unneeded symbols from object files in $YB_HOME
for a in $(find . -exec file {} \; | grep -i elf | cut -f1 -d:); do
  strip --strip-unneeded "$a" || true
done

# Add yugabyte supported languages to localedef
languages=("en_US" "de_DE" "es_ES" "fr_FR" "it_IT" "ja_JP"
  "ko_KR" "pl_PL" "ru_RU" "sv_SE" "tr_TR" "zh_CN")
for lang in "${languages[@]}"; do
  localedef --quiet --force --inputfile="${lang}" --charmap=UTF-8 "${lang}.UTF-8"
done

# Link yugabyte bins to /usr/local/bin/
for a in ysqlsh ycqlsh yugabyted yb-admin yb-ts-cli; do
  ln -s "$YB_HOME/bin/$a" "/usr/local/bin/$a"
done

# In the normal EE flows, we expect /home/yugabyte/{master,tserver} to exist and have both links
# to all the components in the unpacked tar.gz, as well as an extra link to the log path for the
# respective server
shopt -s extglob
mkdir -p "$YB_HOME"/{master,tserver} "$DATA_DIR"/yb-data/{master,tserver}/logs
# Link all YB pieces
for dir in !(^ybc-*); do
  ln -s "$YB_HOME/$dir" "$YB_HOME/master/$dir"
  ln -s "$YB_HOME/$dir" "$YB_HOME/tserver/$dir"
done
shopt -u extglob
# Link the logs
ln -s "$DATA_DIR/yb-data/master/logs" "$YB_HOME/master/logs"
ln -s "$DATA_DIR/yb-data/tserver/logs" "$YB_HOME/tserver/logs"
# Create and link the cores.
mkdir -p "$DATA_DIR/cores"
ln -s "$DATA_DIR/cores" "$YB_HOME/cores"

mkdir -p "$YB_HOME/controller" "$DATA_DIR/ybc-data/controller/logs"
# Find ybc-* directory
YBC_DIR=$(find "$YB_HOME" -maxdepth 1 -type d -name 'ybc-*')
# Link bin directory
ln -s "${YBC_DIR}"/bin "$YB_HOME"/controller/bin
# Link the logs
ln -s "$DATA_DIR/ybc-data/controller/logs" "$YB_HOME"/controller/logs
msg_ok "Setup ${APP}"

msg_info "Copying licenses"
ghr_url=https://raw.githubusercontent.com/yugabyte/yugabyte-db/master
mkdir /licenses
curl ${ghr_url}/LICENSE.md -o /licenses/LICENSE.md
curl ${ghr_url}/licenses/APACHE-LICENSE-2.0.txt -o /licenses/APACHE-LICENSE-2.0.txt
curl ${ghr_url}/licenses/POLYFORM-FREE-TRIAL-LICENSE-1.0.0.txt \
  -o /licenses/POLYFORM-FREE-TRIAL-LICENSE-1.0.0.txt
msg_ok "Copied licenses"

# Install azcopy to support Microsoft Azure integration
msg_info "Installing azcopy"
curl -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-Microsoft https://packages.microsoft.com/keys/microsoft.asc
sudo tee -a /etc/yum.repos.d/packages-microsoft-prod.repo <<EOM
[packages-microsoft-com-prod]
name=Microsoft Production
baseurl=https://packages.microsoft.com/alma/9/prod/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Microsoft
sslverify=1
EOM
$STD dnf upgrade -y
$STD dnf install -y azcopy
mkdir -m 777 /tmp/azcopy
msg_ok "Installed azcopy"

# Install gsutil to support Google Cloud Platform wintegration
msg_info "Installing gsutil"
curl -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-Google-Cloud-SDK https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo <<EOM
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Google-Cloud-SDK
sslverify=1
EOM
ln -s "$(which gsutil)" /usr/local/gsutil
$STD dnf upgrade -y
$STD dnf install -y libxcrypt-compat.x86_64 google-cloud-cli

# Configure gsutil
mkdir "$YB_HOME"/.boto
echo -e "[GSUtil]\nstate_dir=/tmp/gsutil" >"$YB_HOME"/.boto/config
mkdir -m 777 /tmp/gsutil
msg_ok "Installed gsutil"

msg_info "Setting permissions"
mkdir -m 777 /tmp/yb-port-locks
mkdir -m 777 /tmp/yb-controller-tmp
chown -R yugabyte:yugabyte "$YB_HOME"
chown -R yugabyte:yugabyte "$DATA_DIR"
msg_ok "Permissions set"

msg_info "Setting default ulimits in /etc/security/limits.conf"
cat <<EOF >/etc/security/limits.conf
*                -       core            unlimited
*                -       data            unlimited
*                -       fsize           unlimited
*                -       sigpending      119934
*                -       memlock         64
*                -       rss             unlimited
*                -       nofile          1048576
*                -       msgqueue        819200
*                -       stack           8192
*                -       cpu             unlimited
*                -       nproc           12000
*                -       locks           unlimited
EOF
msg_ok "Set default ulimits"

tserver_flags=""
enable_ysql_conn_mgr=true
durable_wal_write=true

if [ "$enable_ysql_conn_mgr" = true ]; then
  tserver_flags+="enable_ysql_conn_mgr=true,"
fi

if [ "$enable_ysql_conn_mgr" = true ]; then
  tserver_flags+="durable_wal_write=true,"
fi

# "none, zone, region, cloud"
fault_tolerance="zone"
cloud_location="cloudprovider.region.zone"
backup_daemon=true

# Creating Service
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/"${app}.service"
[Unit]
Description=${APPLICATION} Service
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
RestartForceExitStatus=SIGPIPE
StartLimitInterval=0
ExecStart=/bin/bash -c '/usr/local/bin/yugabyted start --secure \
--backup_daemon=$backup_daemon \
--fault_tolerance=$fault_tolerance \
--advertise_address=$(hostname -I | awk '{print $1}') \
--tserver_flags="$tserver_flags" \
--data_dir=$DATA_DIR \
--cloud_location=$cloud_location \
--callhome=false'

Environment="YB_HOME=$YB_HOME"
Environment="DATA_DIR=$DATA_DIR"
Environment="YB_MANAGED_DEVOPS_USE_PYTHON3=$YB_MANAGED_DEVOPS_USE_PYTHON3"
Environment="YB_DEVOPS_USE_PYTHON3=$YB_DEVOPS_USE_PYTHON3"
Environment="BOTO_PATH=$BOTO_PATH"
Environment="AZCOPY_JOB_PLAN_LOCATION=$AZCOPY_JOB_PLAN_LOCATION"
Environment="AZCOPY_LOG_LOCATION=$AZCOPY_LOG_LOCATION"
WorkingDirectory=$YB_HOME
TimeoutStartSec=30
LimitCORE=infinity
LimitNOFILE=1048576
LimitNPROC=12000
RestartSec=5
PermissionsStartOnly=True
User=yugabyte
TimeoutStopSec=300
Restart=always

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD dnf autoremove -y
$STD dnf clean all
rm -rf \
  ~/.cache \
  "$YB_HOME/.cache" \
  /var/cache/yum \
  /var/cache/dnf
msg_ok "Cleaned"

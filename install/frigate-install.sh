#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Authors: MickLesk (CanbiZ)
# Co-Authors: remz1337
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://frigate.video/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y {jq,wget,xz-utils,python3,python3-dev,python3-distutils,gcc,pkg-config,libhdf5-dev,unzip,build-essential,automake,libtool,ccache,libusb-1.0-0-dev,apt-transport-https,python3.11,python3.11-dev,cmake,git,libgtk-3-dev,libavcodec-dev,libavformat-dev,libswscale-dev,libv4l-dev,libxvidcore-dev,libx264-dev,libjpeg-dev,libpng-dev,libtiff-dev,gfortran,openexr,libatlas-base-dev,libssl-dev,libtbbmalloc2,libtbb-dev,libdc1394-dev,libopenexr-dev,libgstreamer-plugins-base1.0-dev,libgstreamer1.0-dev,tclsh,libopenblas-dev,liblapack-dev,make,moreutils}
msg_ok "Installed Dependencies"

msg_info "Setting up environment"
cd ~ && echo "export PATH=$PATH:/usr/local/bin" >> .bashrc
source .bashrc
export TARGETARCH="amd64"
export CCACHE_DIR=/root/.ccache
export CCACHE_MAXSIZE=2G
# http://stackoverflow.com/questions/48162574/ddg#49462622
export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn
# https://askubuntu.com/questions/972516/debian-frontend-environment-variable
export DEBIAN_FRONTEND=noninteractive
# Globally set pip break-system-packages option to avoid having to specify it every time
export PIP_BREAK_SYSTEM_PACKAGES=1
# https://github.com/NVIDIA/nvidia-docker/wiki/Installation-(Native-GPU-Support)
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"
# Disable tokenizer parallelism warning
# https://stackoverflow.com/questions/62691279/how-to-disable-tokenizers-parallelism-true-false-warning/72926996#729>
export TOKENIZERS_PARALLELISM=true
# https://github.com/huggingface/transformers/issues/27214
export TRANSFORMERS_NO_ADVISORY_WARNINGS=1
# Set OpenCV ffmpeg loglevel to fatal: https://ffmpeg.org/doxygen/trunk/log_8h.html
export OPENCV_FFMPEG_LOGLEVEL=8
# Set HailoRT to disable logging
export HAILORT_LOGGER_PATH=NONE
msg_ok "Setup environment"

msg_info "Downloading Frigate source"
#fetch_and_deploy_gh_release "frigate" "blakeblackshear/frigate" "tarball" "latest" "/opt/frigate"
cd ~
RELEASE=$(curl -s https://api.github.com/repos/blakeblackshear/frigate/releases/latest | jq -r '.tag_name')
mkdir -p /opt/frigate/models
curl -fsSL "https://github.com/blakeblackshear/frigate/archive/refs/tags/${RELEASE}.tar.gz" -o "frigate.tar.gz"
$STD tar -xzf frigate.tar.gz -C /opt/frigate --strip-components 1
rm -rf frigate.tar.gz
cd /opt/frigate
msg_ok "Downloaded Frigate source"

msg_info "Building Nginx with Custom Modules"
#Overwrite version check as debian 12 LXC doesn't have the debian.list file for some reason
sed -i 's|if.*"$VERSION_ID" == "12".*|if \[\[ "$VERSION_ID" == "12" \]\] \&\ \[\[ -f /etc/apt/sources.list.d/debian.list \]\]; then|g' /opt/frigate/docker/main/build_nginx.sh
$STD  bash /opt/frigate/docker/main/build_nginx.sh
sed -e '/s6-notifyoncheck/ s/^#*/#/' -i /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run
ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx
msg_ok "Built Nginx"

msg_info "Building SQLite with Custom Modules"
sed -i 's|if.*"$VERSION_ID" == "12".*|if \[\[ "$VERSION_ID" == "12" \]\] \&\ \[\[ -f /etc/apt/sources.list.d/debian.list \]\]; then|g' /opt/frigate/docker/main/build_sqlite_vec.sh
$STD bash /opt/frigate/docker/main/build_sqlite_vec.sh
msg_ok "Built SQLite"

msg_info "Installing go2rtc"
#fetch_and_deploy_gh_release "go2rtc" "AlexxIT/go2rtc" "singlefile" "latest" "/usr/local/go2rtc/bin" "go2rtc_linux_amd64"
mkdir -p /usr/local/go2rtc/bin
cd /usr/local/go2rtc/bin
curl -fsSL "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64" -o "go2rtc"
chmod +x go2rtc
ln -sf /usr/local/go2rtc/bin/go2rtc /usr/local/bin/go2rtc
msg_ok "Installed go2rtc"

msg_info "Installing Tempio"
sed -i 's|/rootfs/usr/local|/usr/local|g' /opt/frigate/docker/main/install_tempio.sh
$STD bash /opt/frigate/docker/main/install_tempio.sh
ln -sf /usr/local/tempio/bin/tempio /usr/local/bin/tempio
msg_ok "Installed Tempio"

msg_info "Installing OpenVino Runtime and Dev library"
wget -q https://bootstrap.pypa.io/get-pip.py -O get-pip.py
sed -i 's/args.append("setuptools")/args.append("setuptools==77.0.3")/' get-pip.py
$STD python3 get-pip.py "pip"
$STD pip3 install -r /opt/frigate/docker/main/requirements-ov.txt
msg_ok "Installed OpenVino Runtime and Dev library"

msg_info "Downloading OpenVino Model"
mkdir /models
cd /models
wget -q http://download.tensorflow.org/models/object_detection/ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz
$STD tar -xvf ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz
$STD python3 /opt/frigate/docker/main/build_ov_model.py
msg_ok "Downloaded OpenVino Model"

msg_info "Building libUSB without udev"
cd /opt
wget -q https://github.com/libusb/libusb/archive/v1.0.26.zip -O v1.0.26.zip
$STD unzip v1.0.26.zip
cd libusb-1.0.26
$STD ./bootstrap.sh
$STD ./configure CC='ccache gcc' CCX='ccache g++' --disable-udev --enable-shared
$STD make -j $(nproc --all)
cd /opt/libusb-1.0.26/libusb
mkdir -p '/usr/local/lib'
$STD bash ../libtool  --mode=install /usr/bin/install -c libusb-1.0.la '/usr/local/lib'
mkdir -p '/usr/local/include/libusb-1.0'
$STD install -c -m 644 libusb.h '/usr/local/include/libusb-1.0'
mkdir -p '/usr/local/lib/pkgconfig'
cd  /opt/libusb-1.0.26/
$STD install -c -m 644 libusb-1.0.pc '/usr/local/lib/pkgconfig'
ldconfig
msg_ok "Built libUSB"

msg_info "Building Models"
cd /
# Get model and labels
wget -qO edgetpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite
wget -qO cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite
cp /opt/frigate/labelmap.txt /labelmap.txt
# Copy OpenVino model
#cp -r /opt/frigate/models/public/ssdlite_mobilenet_v2 openvino-model
mkdir /openvino-model
cp -r /models/ssdlite_mobilenet_v2.xml openvino-model/
cp -r /models/ssdlite_mobilenet_v2.bin openvino-model/
wget -q https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt -O openvino-model/coco_91cl_bkgr.txt
sed -i 's/truck/car/g' openvino-model/coco_91cl_bkgr.txt
# Get Audio Model and labels
#wget -qO - https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download | tar xvz
wget -qO - https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download -o "yamnet-tflite-classification-tflite-v1.tar.gz"
tar xzf yamnet-tflite-classification-tflite-v1.tar.gz
rm -rf yamnet-tflite-classification-tflite-v1.tar.gz
mv 1.tflite cpu_audio_model.tflite
cp /opt/frigate/audio-labelmap.txt /audio-labelmap.txt
msg_ok "Built Models"

msg_info "Building Wheels"
$STD update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
$STD pip3 install -r /opt/frigate/docker/main/requirements.txt
msg_ok "Built Wheels"

msg_info "Building pysqlite3"
sed -i 's|^SQLITE3_VERSION=.*|SQLITE3_VERSION="version-3.46.0"|g' /opt/frigate/docker/main/build_pysqlite3.sh
$STD bash /opt/frigate/docker/main/build_pysqlite3.sh
$STD pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt
msg_ok "Built pysqlite3"

msg_info "Building HailoRT"
$STD bash /opt/frigate/docker/main/install_hailort.sh
cp -a /opt/frigate/docker/main/rootfs/. /
sed -i '/^.*unset DEBIAN_FRONTEND.*$/d' /opt/frigate/docker/main/install_deps.sh
echo "libedgetpu1-max libedgetpu/accepted-eula boolean true" | debconf-set-selections
echo "libedgetpu1-max libedgetpu/install-confirm-max boolean true" | debconf-set-selections
$STD bash /opt/frigate/docker/main/install_deps.sh
$STD pip3 install -U /wheels/*.whl
ldconfig
#Run twice to fix dependency conflict
$STD pip3 install -U /wheels/*.whl
msg_ok "Built HailoRT"

msg_info "Installing NodeJS"
#NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
$STD curl -SLO https://deb.nodesource.com/nsolid_setup_deb.sh
chmod 500 nsolid_setup_deb.sh
$STD ./nsolid_setup_deb.sh 20
$STD apt-get install nodejs -y
$STD npm install -g npm@10
msg_ok "Installed NodeJS"

msg_info "Installing Frigate"
cd /opt/frigate
$STD pip3 install -r /opt/frigate/docker/main/requirements-dev.txt
$STD bash /opt/frigate/.devcontainer/initialize.sh
$STD make version
cd /opt/frigate/web
$STD npm install
$STD npm run build
cp -r /opt/frigate/web/dist/* /opt/frigate/web/
cd /opt/frigate/
sed -i '/^s6-svc -O \.$/s/^/#/' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run
cp -r /opt/frigate/config/. /config
mkdir -p /media/frigate
curl -fsSL "https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4" -o "/media/frigate/person-bicycle-car-detection.mp4"
echo "tmpfs   /tmp/cache      tmpfs   defaults        0       0" >>/etc/fstab
cat <<EOF >/etc/frigate.env
DEFAULT_FFMPEG_VERSION="7.0"
INCLUDED_FFMPEG_VERSIONS="7.0:5.0"
EOF
cat <<EOF >/config/config.yml
mqtt:
  enabled: false
cameras:
  test:
    ffmpeg:
      #hwaccel_args: preset-vaapi
      inputs:
        - path: /media/frigate/person-bicycle-car-detection.mp4
          input_args: -re -stream_loop -1 -fflags +genpts
          roles:
            - detect
            - rtmp
    detect:
      height: 1080
      width: 1920
      fps: 5
# Optional: Authentication configuration
auth:
  # Optional: Enable authentication
  enabled: false
detect:
  enabled: false
EOF
msg_ok "Installed Frigate"


msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/create_directories.service
[Unit]
Description=Create necessary directories for logs

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/bin/mkdir -p /dev/shm/logs/{frigate,go2rtc,nginx} && /bin/touch /dev/shm/logs/{frigate/current,go2rtc/current,nginx/current} && /bin/chmod -R 777 /dev/shm/logs'

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now create_directories
sleep 3
cat <<EOF >/etc/systemd/system/go2rtc.service
[Unit]
Description=go2rtc service
After=network.target
After=create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
EnvironmentFile=/etc/frigate.env
ExecStartPre=+rm /dev/shm/logs/go2rtc/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/go2rtc/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/go2rtc/current
StandardError=file:/dev/shm/logs/go2rtc/current

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now go2rtc
sleep 3
cat <<EOF >/etc/systemd/system/frigate.service
[Unit]
Description=Frigate service
After=go2rtc.service
After=create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
EnvironmentFile=/etc/frigate.env
# Environment=PLUS_API_KEY=
ExecStartPre=+rm /dev/shm/logs/frigate/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/frigate/current
StandardError=file:/dev/shm/logs/frigate/current

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now frigate
sleep 3
cat <<EOF >/etc/systemd/system/nginx.service
[Unit]
Description=Nginx service
After=frigate.service
After=create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStartPre=+rm /dev/shm/logs/nginx/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/nginx/current
StandardError=file:/dev/shm/logs/nginx/current

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nginx
msg_ok "Created Services"

motd_ssh
customize

msg_info "Cleaning up"
apt-get -y autoremove
apt-get -y autoclean
msg_ok "Cleaned"

echo -e "Don't forget to edit the Frigate config file (${GN}/config/config.yml${CL}) and reboot. Example configuration at https://docs.frigate.video/configuration/"
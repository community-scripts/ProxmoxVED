#!/usr/bin/env bash

set -e

apt update
apt install -y git curl python3 python3-pip

# Clone and install Pinchflat
git clone https://github.com/kieraneglin/pinchflat /opt/pinchflat
chmod +x /opt/pinchflat/pinchflat.sh
ln -s /opt/pinchflat/pinchflat.sh /usr/local/bin/pinchflat


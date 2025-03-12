#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts
# Author: MickLesk
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -eEuo pipefail
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")

function header_info {
    clear
    cat <<"EOF"
    ____                                      _    ____________     __           ____                                      _    ________
   / __ \_________  _  ______ ___  ____  _  _| |  / / ____/ __ \   / /_____     / __ \_________  _  ______ ___  ____  _  _| |  / / ____/
  / /_/ / ___/ __ \| |/_/ __ `__ \/ __ \| |/_/ | / / __/ / / / /  / __/ __ \   / /_/ / ___/ __ \| |/_/ __ `__ \/ __ \| |/_/ | / / __/
 / ____/ /  / /_/ />  </ / / / / / /_/ />  < | |/ / /___/ /_/ /  / /_/ /_/ /  / ____/ /  / /_/ />  </ / / / / / /_/ />  < | |/ / /___
/_/   /_/   \____/_/|_/_/ /_/ /_/\____/_/|_| |___/_____/_____/   \__/\____/  /_/   /_/   \____/_/|_/_/ /_/ /_/\____/_/|_| |___/_____/

EOF
}

function update_container() {
    container=$1
    os=$(pct config "$container" | awk '/^ostype/ {print $2}')

    if [[ "$os" == "ubuntu" || "$os" == "debian" || "$os" == "alpine" ]]; then
        echo -e "${BL}[Info]${GN} Checking /usr/bin/update in ${BL}$container${CL} (OS: ${GN}$os${CL})"

        if pct exec "$container" -- [ -e /usr/bin/update ]; then
            pct exec "$container" -- bash -c "sed -i 's/ProxmoxVED/ProxmoxVE/g' /usr/bin/update"

            if pct exec "$container" -- grep -q "ProxmoxVE" /usr/bin/update; then
                echo -e "${GN}[Success]${CL} /usr/bin/update updated in ${BL}$container${CL}.\n"
            else
                echo -e "${RD}[Error]${CL} /usr/bin/update in ${BL}$container${CL} could not be updated properly.\n"
            fi
        else
            echo -e "${RD}[Error]${CL} /usr/bin/update not found in container ${BL}$container${CL}.\n"
        fi
    else
        echo -e "${BL}[Info]${GN} Skipping ${BL}$container${CL} (not Debian/Ubuntu/Alpine)\n"
    fi
}

function update_motd() {
    container=$1
    os=$(pct config "$container" | awk '/^ostype/ {print $2}')

    if [[ "$os" == "ubuntu" || "$os" == "debian" ]]; then
        echo -e "${BL}[Info]${GN} Updating MOTD in ${BL}$container${CL} (OS: ${GN}$os${CL})"

        pct exec "$container" -- bash -c "
      YW='\033[33m'
      GN='\033[1;92m'
      CL='\033[m'
      TAB='  '
      GATEWAY='🌐'
      OS='🖥️'
      HOSTNAME='🏠'
      INFO='💡'
      PROFILE_FILE='/etc/profile.d/00_motd.sh'

      echo 'echo -e \"\"' > \"\$PROFILE_FILE\"
      echo 'echo -e \"${TAB}\$GATEWAY${TAB}\$YW Provided by: \$GN community-scripts ORG \$YW | GitHub: \$GN https://github.com/community-scripts/ProxmoxVE \$CL\"' >> \"\$PROFILE_FILE\"
      echo 'echo \"\"' >> \"\$PROFILE_FILE\"
      echo 'echo -e \"${TAB}\$OS${TAB}\$YW OS: \$GN \$(grep ^NAME /etc/os-release | cut -d= -f2 | tr -d '\"') - Version: \$(grep ^VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '\"') \$CL\"' >> \"\$PROFILE_FILE\"
      echo 'echo -e \"${TAB}\$HOSTNAME${TAB}\$YW Hostname: \$GN \$(hostname) \$CL\"' >> \"\$PROFILE_FILE\"
      echo 'echo -e \"${TAB}\$INFO${TAB}\$YW IP Address: \$GN \$(hostname -I | awk '{print \$1}') \$CL\"' >> \"\$PROFILE_FILE\"
      chmod -x /etc/update-motd.d/*
    "
    elif [[ "$os" == "alpine" ]]; then
        echo -e "${BL}[Info]${GN} Updating MOTD in ${BL}$container${CL} (OS: ${GN}$os${CL})"

        pct exec "$container" -- bash -c "
      echo \"export TERM='xterm-256color'\" >> /root/.bashrc
      IP=\$(ip -4 addr show eth0 | awk '/inet / {print \$2}' | cut -d/ -f1 | head -n 1)
      PROFILE_FILE='/etc/profile.d/00_lxc-details.sh'

      echo 'echo -e \"\"' > \"\$PROFILE_FILE\"
      echo 'echo -e \" LXC Container\"' >> \"\$PROFILE_FILE\"
      echo 'echo -e \" 🌐 Provided by: community-scripts ORG | GitHub: https://github.com/community-scripts/ProxmoxVE \"' >> \"\$PROFILE_FILE\"
      echo 'echo \"\"' >> \"\$PROFILE_FILE\"
      echo 'echo -e \" 🖥️ OS: \$(grep ^NAME /etc/os-release | cut -d= -f2 | tr -d '\"') - Version: \$(grep ^VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '\"') \"' >> \"\$PROFILE_FILE\"
      echo 'echo -e \" 🏠 Hostname: \$(hostname) \"' >> \"\$PROFILE_FILE\"
      echo 'echo -e \" 💡 IP Address: \$IP \"' >> \"\$PROFILE_FILE\"
    "
    fi
}

function remove_dev_tag() {
    container=$1
    current_tags=$(pct config "$container" | awk '/^tags/ {print $2}')

    if [[ "$current_tags" == *"dev"* ]]; then
        new_tags=$(echo "$current_tags" | sed 's/,*dev,*//g' | sed 's/^,//' | sed 's/,$//')

        if [[ -z "$new_tags" ]]; then
            pct set "$container" -delete tags
        else
            pct set "$container" -tags "$new_tags"
        fi

        echo -e "${GN}[Success]${CL} 'dev' tag removed from ${BL}$container${CL}.\n"
    fi
}

header_info
echo "Searching for containers with 'dev' tag..."
for container in $(pct list | awk '{if(NR>1) print $1}'); do
    tags=$(pct config "$container" | awk '/^tags/ {print $2}')
    if [[ "$tags" == *"dev"* ]]; then
        update_container "$container"
        update_motd "$container"
        remove_dev_tag "$container"
    fi
done

header_info
echo -e "${GN}The process is complete.${CL}\n"

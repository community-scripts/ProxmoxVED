#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

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

    if [[ "$os" == "ubuntu" || "$os" == "debian" ]]; then
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
    fi
}

function update_motd() {
    container=$1
    os=$(pct config "$container" | awk '/^ostype/ {print $2}')
    motd_file="/etc/profile.d/00_lxc-details.sh"

    echo -e "${BL}[Info]${GN} Updating MOTD in ${BL}$container${CL} (OS: ${GN}$os${CL})"

    if [ "$os" = "alpine" ]; then
        shell="ash"
    else
        shell="bash"
    fi

    pct exec "$container" -- $shell -c "
        if [ \"$os\" = \"alpine\" ]; then
            IP=\$(ip -4 addr show eth0 | awk '/inet / {print \$2}' | cut -d/ -f1 | head -n 1)
        else
            IP=\$(hostname -I | awk '{print \$1}')
        fi

        cat << EOF > $motd_file
#!/bin/sh
echo \"\"
echo \"🌐 Provided by: community-scripts ORG | GitHub: https://github.com/community-scripts/ProxmoxVE\"
echo \"🖥️ OS: \$(grep ^NAME /etc/os-release | cut -d= -f2 | tr -d '\"') - Version: \$(grep ^VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '\"')\"
echo \"🏠 Hostname: \$(hostname)\"
echo \"💡 IP Address: \$IP\"
EOF
        chmod +x $motd_file
    "

    echo -e "${GN}[Success]${CL} MOTD updated for ${BL}$container${CL}.\n"
}

function remove_dev_tag() {
    container=$1
    current_tags=$(pct config "$container" | awk '/^tags/ {print $2}')

    if [[ "$current_tags" == *"community-script-dev"* ]]; then
        new_tags=$(echo "$current_tags" | sed 's/,*community-script-dev,*//g' | sed 's/^,//' | sed 's/,$//')

        if [[ -z "$new_tags" ]]; then
            pct set "$container" -tags "community-script"
        else
            pct set "$container" -tags "$new_tags,community-script"
        fi

        echo -e "${GN}[Success]${CL} 'community-script-dev' tag removed and 'community-script' added for ${BL}$container${CL}.\n"
    fi
}

header_info
echo "Searching for containers with 'community-script-dev' tag..."

found=0
for container in $(pct list | awk '{if(NR>1) print $1}'); do
    tags=$(pct config "$container" | awk '/^tags/ {print $2}')
    if [[ "$tags" == *"community-script-dev"* ]]; then
        found=1
        update_container "$container"
        update_motd "$container"
        remove_dev_tag "$container"
    fi
done
if [[ $found -eq 0 ]]; then
    echo -e "${RD}[Error]${CL} No containers found with the tag 'community-script-dev'. Exiting script."
    exit 1
fi

header_info
echo -e "${GN}The process is complete.${CL}\n"

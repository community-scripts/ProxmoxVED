# 🤖 AI Contribution Guidelines for ProxmoxVED

> **This documentation is intended for all AI assistants (GitHub Copilot, Claude, ChatGPT, etc.) contributing to this project.**

## 🎯 Core Principles

### 1. **Maximum Use of `tools.func` Functions**
We have an extensive library of helper functions. **NEVER** implement your own solutions when a function already exists!

### 2. **No Pointless Variables**
Only create variables when they:
- Are used multiple times
- Improve readability
- Are intended for configuration

### 3. **Consistent Script Structure**
All scripts follow an identical structure. Deviations are not acceptable.

### 4. **Bare-Metal Installation**
We do **NOT use Docker** for our installation scripts. All applications are installed directly on the system.

---

## 📁 Script Types and Their Structure

### CT Script (`ct/AppName.sh`)

```bash
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: AuthorName (GitHubUsername)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://application-url.com

APP="AppName"
var_tags="${var_tags:-tag1;tag2;tag3}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/appname ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "appname" "owner/repo"; then
    msg_info "Stopping Service"
    systemctl stop appname
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/appname/data /opt/appname_data_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo"

    # Build steps...

    msg_info "Restoring Data"
    cp -r /opt/appname_data_backup/. /opt/appname/data
    rm -rf /opt/appname_data_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start appname
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:PORT${CL}"
```

### Install Script (`install/AppName-install.sh`)

```bash
#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: AuthorName (GitHubUsername)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://application-url.com

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  dependency1 \
  dependency2
msg_ok "Installed Dependencies"

# Runtime Setup (ALWAYS use our functions!)
NODE_VERSION="22" setup_nodejs
# or
PG_VERSION="16" setup_postgresql
# or
setup_uv
# etc.

fetch_and_deploy_gh_release "appname" "owner/repo"

msg_info "Setting up Application"
cd /opt/appname
# Build/Setup Schritte...
msg_ok "Set up Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/appname.service
[Unit]
Description=AppName Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/appname
ExecStart=/path/to/executable
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now appname
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
```

---

## 🔧 Available Helper Functions

### Release Management

| Function | Description | Example |
|----------|-------------|----------|
| `fetch_and_deploy_gh_release` | Fetches and installs GitHub Release | `fetch_and_deploy_gh_release "app" "owner/repo"` |
| `check_for_gh_release` | Checks for new version | `if check_for_gh_release "app" "owner/repo"; then` |

**Modes for `fetch_and_deploy_gh_release`:**
```bash
# Tarball/Source (Standard)
fetch_and_deploy_gh_release "appname" "owner/repo"

# Binary (.deb)
fetch_and_deploy_gh_release "appname" "owner/repo" "binary"

# Prebuilt Archive
fetch_and_deploy_gh_release "appname" "owner/repo" "prebuild" "latest" "/opt/appname" "filename.tar.gz"

# Single Binary
fetch_and_deploy_gh_release "appname" "owner/repo" "singlefile" "latest" "/opt/appname" "binary-linux-amd64"
```

**Clean Install Flag:**
```bash
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo"
```

### Runtime/Language Setup

| Function | Variable(s) | Example |
|----------|-------------|----------|
| `setup_nodejs` | `NODE_VERSION`, `NODE_MODULE` | `NODE_VERSION="22" setup_nodejs` |
| `setup_uv` | `UV_PYTHON` | `UV_PYTHON="3.12" setup_uv` |
| `setup_go` | `GO_VERSION` | `GO_VERSION="1.22" setup_go` |
| `setup_rust` | `RUST_VERSION`, `RUST_CRATES` | `RUST_CRATES="monolith" setup_rust` |
| `setup_ruby` | `RUBY_VERSION` | `RUBY_VERSION="3.3" setup_ruby` |
| `setup_java` | `JAVA_VERSION` | `JAVA_VERSION="21" setup_java` |
| `setup_php` | `PHP_VERSION`, `PHP_MODULES` | `PHP_VERSION="8.3" PHP_MODULES="redis,gd" setup_php` |

### Database Setup

| Function | Variable(s) | Example |
|----------|-------------|----------|
| `setup_postgresql` | `PG_VERSION`, `PG_MODULES` | `PG_VERSION="16" setup_postgresql` |
| `setup_postgresql_db` | `PG_DB_NAME`, `PG_DB_USER` | `PG_DB_NAME="mydb" PG_DB_USER="myuser" setup_postgresql_db` |
| `setup_mariadb_db` | `MARIADB_DB_NAME`, `MARIADB_DB_USER` | `MARIADB_DB_NAME="mydb" setup_mariadb_db` |
| `setup_mysql` | `MYSQL_VERSION` | `setup_mysql` |
| `setup_mongodb` | `MONGO_VERSION` | `setup_mongodb` |
| `setup_clickhouse` | - | `setup_clickhouse` |

### Tools & Utilities

| Function | Description |
|----------|-------------|
| `setup_adminer` | Installs Adminer for DB management |
| `setup_composer` | Install PHP Composer |
| `setup_ffmpeg` | Install FFmpeg |
| `setup_imagemagick` | Install ImageMagick |
| `setup_gs` | Install Ghostscript |
| `setup_hwaccel` | Configure hardware acceleration |

### Helper Utilities

| Function | Description | Example |
|----------|-------------|----------|
| `import_local_ip` | Sets `$LOCAL_IP` variable | `import_local_ip` |
| `ensure_dependencies` | Checks/installs dependencies | `ensure_dependencies curl jq` |
| `install_packages_with_retry` | APT install with retry | `install_packages_with_retry nginx redis` |

---

## ❌ Anti-Patterns (NEVER use!)

### 1. Pointless Variables
```bash
# ❌ WRONG - unnecessary variables
APP_NAME="myapp"
APP_DIR="/opt/${APP_NAME}"
APP_USER="root"
APP_PORT="3000"
cd $APP_DIR

# ✅ CORRECT - use directly
cd /opt/myapp
```

### 2. Custom Download Logic
```bash
# ❌ WRONG - custom wget/curl logic
RELEASE=$(curl -s https://api.github.com/repos/owner/repo/releases/latest | jq -r '.tag_name')
wget https://github.com/owner/repo/archive/${RELEASE}.tar.gz
tar -xzf ${RELEASE}.tar.gz
mv repo-${RELEASE} /opt/myapp

# ✅ CORRECT - use our function
fetch_and_deploy_gh_release "myapp" "owner/repo"
```

### 3. Custom Version-Check Logic
```bash
# ❌ WRONG - custom version check
CURRENT=$(cat /opt/myapp/version.txt)
LATEST=$(curl -s https://api.github.com/repos/owner/repo/releases/latest | jq -r '.tag_name')
if [[ "$CURRENT" != "$LATEST" ]]; then
  # update...
fi

# ✅ CORRECT - use our function
if check_for_gh_release "myapp" "owner/repo"; then
  # update...
fi
```

### 4. Docker-based Installation
```bash
# ❌ WRONG - using Docker
docker pull myapp/myapp:latest
docker run -d --name myapp myapp/myapp:latest

# ✅ CORRECT - Bare-Metal Installation
fetch_and_deploy_gh_release "myapp" "owner/repo"
npm install && npm run build
```

### 5. Custom Runtime Installation
```bash
# ❌ WRONG - custom Node.js installation
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs

# ✅ CORRECT - use our function
NODE_VERSION="22" setup_nodejs
```

### 6. Redundant echo Statements
```bash
# ❌ WRONG - custom logging messages
echo "Installing dependencies..."
apt install -y curl
echo "Done!"

# ✅ CORRECT - use msg_info/msg_ok
msg_info "Installing Dependencies"
$STD apt install -y curl
msg_ok "Installed Dependencies"
```

### 7. Missing $STD Usage
```bash
# ❌ WRONG - apt without $STD
apt install -y nginx

# ✅ CORRECT - with $STD for silent output
$STD apt install -y nginx
```

---

## 📝 Important Rules

### Variable Declarations (CT Script)
```bash
# Standard declarations (ALWAYS present)
APP="AppName"
var_tags="${var_tags:-tag1;tag2}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
```

### Update-Script Pattern
```bash
function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # 1. Check if installation exists
  if [[ ! -d /opt/appname ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # 2. Check for update
  if check_for_gh_release "appname" "owner/repo"; then
    # 3. Stop service
    msg_info "Stopping Service"
    systemctl stop appname
    msg_ok "Stopped Service"

    # 4. Backup data (if present)
    msg_info "Backing up Data"
    cp -r /opt/appname/data /opt/appname_data_backup
    msg_ok "Backed up Data"

    # 5. Perform clean install
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo"

    # 6. Rebuild (if needed)
    cd /opt/appname
    $STD npm install
    $STD npm run build

    # 7. Restore data
    msg_info "Restoring Data"
    cp -r /opt/appname_data_backup/. /opt/appname/data
    rm -rf /opt/appname_data_backup
    msg_ok "Restored Data"

    # 8. Start service
    msg_info "Starting Service"
    systemctl start appname
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit  # IMPORTANT: Always end with exit!
}
```

### Systemd Service Pattern
```bash
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/appname.service
[Unit]
Description=AppName Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/appname
Environment=NODE_ENV=production
ExecStart=/usr/bin/node /opt/appname/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now appname
msg_ok "Created Service"
```

### Installation Script Footer
```bash
# ALWAYS at the end of the install script:
motd_ssh
customize
cleanup_lxc
```

---

## 🔍 Checklist Before PR Creation

- [ ] No Docker installation used
- [ ] `fetch_and_deploy_gh_release` used for GitHub releases
- [ ] `check_for_gh_release` used for update checks
- [ ] `setup_*` functions used for runtimes (nodejs, postgresql, etc.)
- [ ] No redundant variables
- [ ] `$STD` before all apt/npm/build commands
- [ ] `msg_info`/`msg_ok`/`msg_error` for logging
- [ ] Correct script structure followed
- [ ] Update function present and functional
- [ ] Data backup implemented in update function
- [ ] `motd_ssh`, `customize`, `cleanup_lxc` at the end
- [ ] No custom download/version-check logic

---

## 📖 Reference: Good Example (Termix)

### CT Script: [ct/termix.sh](../ct/termix.sh)
- Uses `check_for_gh_release` for version checking
- Uses `CLEAN_INSTALL=1 fetch_and_deploy_gh_release` for clean updates
- Backup/restore of `/opt/termix/data`
- Correct structure with all required variables

### Install Script: [install/termix-install.sh](../install/termix-install.sh)
- `NODE_VERSION="22" setup_nodejs` instead of manual installation
- `fetch_and_deploy_gh_release "termix" "Termix-SSH/Termix"` instead of wget/curl
- Clean service configuration
- Correct footer with `motd_ssh`, `customize`, `cleanup_lxc`

---

## 💡 Tips for AI Assistants

1. **Search `tools.func` first** before implementing custom solutions
2. **Use existing scripts as reference** (e.g., `linkwarden-install.sh`, `homarr-install.sh`)
3. **Ask when uncertain** instead of introducing wrong patterns
4. **Consistency > Creativity** - follow established patterns
5. **Test local variables** - use `${VAR:-default}` pattern for optional values

---

## 📚 Further Documentation

- [CONTRIBUTING.md](contribution/CONTRIBUTING.md) - General contribution guidelines
- [GUIDE.md](contribution/GUIDE.md) - Detailed developer documentation
- [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md) - Technical details
- [EXIT_CODES.md](EXIT_CODES.md) - Exit code reference

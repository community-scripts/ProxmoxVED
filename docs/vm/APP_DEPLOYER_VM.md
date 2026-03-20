# App Deployer VM

Deploy LXC applications inside a full Virtual Machine instead of an LXC container.

## Overview

The App Deployer VM bridges the gap between CT install scripts (`install/*.sh`) and VM infrastructure. It leverages the existing install scripts — originally designed for LXC containers — and runs them **live during image build** via `virt-customize --run`.

### Supported Operating Systems

| OS     | Version   | Codename | Cloud-Init |
| ------ | --------- | -------- | ---------- |
| Debian | 13        | Trixie   | Optional   |
| Debian | 12        | Bookworm | Optional   |
| Ubuntu | 24.04 LTS | Noble    | Required   |
| Ubuntu | 22.04 LTS | Jammy    | Required   |

## Usage

### Create a new App VM (interactive)

```bash
bash -c "$(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/vm/app-deployer-vm.sh)"
```

### Pre-select application

```bash
APP_SELECT=yamtrack bash -c "$(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/vm/app-deployer-vm.sh)"
```

### Update the application later (inside the VM)

```bash
bash -c "$(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/ct/<app>.sh)"
```

For example, to update Yamtrack:

```bash
bash -c "$(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/ct/yamtrack.sh)"
```

## How It Works

### Installation Flow

```
┌─────────────────────────────────────┐
│  Proxmox Host                       │
│                                     │
│  1. Select app (e.g. Yamtrack)      │
│  2. Select OS (e.g. Debian 13)      │
│  3. Configure VM resources          │
│  4. Download cloud image            │
│  5. virt-customize:                 │
│     - Install base packages         │
│     - Inject install.func           │
│     - Inject tools.func             │
│     - Run install script LIVE       │
│       (virt-customize --run)        │
│     - Configure hostname & SSH      │
│  6. Create VM (qm create)          │
│  7. Import customized disk          │
│  8. Start VM                        │
│                                     │
│  → Application pre-installed!       │
└─────────────────────────────────────┘
```

### Update Flow

```
┌─────────────────────────────────────┐
│  Inside the VM (SSH or console)     │
│                                     │
│  bash -c "$(curl -fsSL             │
│    $COMMUNITY_SCRIPTS_URL/          │
│    ct/<app>.sh)"                    │
│                                     │
│  → start() detects no pveversion    │
│  → Shows update/settings menu       │
│  → Runs update_script()             │
└─────────────────────────────────────┘
```

The update mechanism reuses the existing CT script logic. Since `pveversion` is not available inside the VM, the `start()` function automatically enters the update/settings mode — exactly the same as running updates in LXC containers.

## Architecture

### Files

| File                    | Purpose                                     |
| ----------------------- | ------------------------------------------- |
| `vm/app-deployer-vm.sh` | Main user-facing script                     |
| `misc/vm-app.func`      | Core library for VM app deployment          |
| `misc/vm-core.func`     | Shared VM functions (colors, spinner, etc.) |
| `misc/cloud-init.func`  | Cloud-Init configuration (optional)         |

### Key Design Decisions

1. **Install scripts run unmodified** — The same `install/*.sh` scripts that work in LXC containers work inside VMs. The environment (`FUNCTIONS_FILE_PATH`, exports) is replicated identically.

2. **Image customization via `virt-customize`** — All dependencies are installed and the app install script runs live inside the qcow2 image during build. No SSH or guest agent required during setup.

3. **Live installation** — The install script runs during image build (not on first boot), so the application is ready immediately when the VM starts.

4. **Update via CT script URL** — Run the same `bash -c "$(curl ...ct/<app>.sh)"` command inside the VM, just like in an LXC container.

### Environment Variables (set during image build)

| Variable                | Description                        |
| ----------------------- | ---------------------------------- |
| `FUNCTIONS_FILE_PATH`   | Full contents of `install.func`    |
| `APPLICATION`           | App display name (e.g. "Yamtrack") |
| `app`                   | App identifier (e.g. "yamtrack")   |
| `VERBOSE`               | "no" (silent mode)                 |
| `SSH_ROOT`              | "yes"                              |
| `PCT_OSTYPE`            | OS type (debian/ubuntu)            |
| `PCT_OSVERSION`         | OS version (12/13/22.04/24.04)     |
| `COMMUNITY_SCRIPTS_URL` | Repository base URL                |
| `DEPLOY_TARGET`         | "vm" (distinguishes from LXC)      |

### VM Directory Structure

```
/opt/community-scripts/
├── install.func              # Function library
└── tools.func                # Helper functions
```

## Limitations

- **Alpine-based apps**: Currently only Debian/Ubuntu VMs are supported. Alpine install scripts are not compatible.
- **LXC-specific features**: Some CT features (FUSE, TUN, GPU passthrough) are configured differently in VMs.
- **`cleanup_lxc`**: This function works fine in VMs (it only cleans package caches), but the name is LXC-centric.

## Troubleshooting

### Check build log

If the installation fails during image build, check the log on the Proxmox host:

```bash
cat /tmp/vm-app-install.log
```

### Re-run installation

Re-build the VM from scratch — since the app is installed during image build, there is no in-VM reinstall mechanism. Simply delete the VM and run the deployer again.

### Verify installation worked

After the VM boots, SSH in and check if the application service is running:

```bash
systemctl status <app-service-name>
```

# Incus Host Setup (Community Scripts)

Proxmox VE and Incus share the same `ct/` and `install/` scripts. On an Incus host, `misc/build.func` detects the platform and loads the Incus backend. There is no separate `Incus/` script tree.

## Requirements

- Incus installed and usable (`incus info` works for your user)
- Network access to pull images (`images:` remote) and script sources
- Enough free space on the **Incus storage pool** (not only the host disk)

## Platform detection

| Environment | Detection |
| ----------- | --------- |
| Proxmox VE host | `pveversion` present → PVE backend |
| Incus host | `incus` CLI + daemon → Incus backend |
| Inside Incus CT | `/dev/incus/sock` or Community Scripts MOTD → update mode |

Override (debug): `export LXC_PLATFORM=incus|pve|incus-container`

## Local development

From a clone/fork, just run the CT script (origin is auto-detected):

```bash
bash ct/debian.sh
```

Optional overrides:

```bash
export COMMUNITY_SCRIPTS_DIR=/path/to/ProxmoxVED/misc
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/YOU/ProxmoxVED/your-branch
```

See [Script origin (fork/branch)](source-origin.md).

## Non-root Incus users

Defaults, diagnostics, and build logs go to a writable state directory:

| User | Directory |
| ---- | --------- |
| root (or writable `/usr/local`) | `/usr/local/community-scripts` |
| non-root | `~/.config/community-scripts` |

Override: `export COMMUNITY_SCRIPTS_STATE_DIR=/custom/path`

Logs: `<state-dir>/logs/incus-create-*.log`

## Storage pools

`incus storage info` reports **pool** free space. Default loop-backed pools are often small (~10 GiB). Grow or choose another pool:

```bash
incus storage list
incus storage set default size=50GiB
```

## Networking

- **bridge / ovn / macvlan**: IPv4/IPv6 device options (`ipv4.address`, …) are applied when set
- **physical / sriov**: IP device keys are skipped (host NIC); rely on DHCP or host-side config
- DHCP on physical/macvlan can take longer than 20 s — the installer waits up to ~90 s and continues with a warning if needed

## GPU passthrough

Uses current Incus `gpu` devices (`pci=`, `id=`, `vendorid=`), not obsolete `device=/dev/dri/...`.

```bash
incus info --resources
# After create, devices look like: gpu0 type=gpu gputype=physical pci=0000:…
```

`gid=` / `mode=` are set after container groups exist.

## Privileged / nesting / TUN / FUSE

| Need | Setting |
| ---- | ------- |
| Docker-in-LXC | `security.nesting=true` (default on) |
| TUN / FUSE / USB serial | often `security.privileged=true` (Advanced settings) |

## Update path

Inside an existing CT, run the same `ct/<app>.sh` script. Detection switches to update mode (`update_script`) without calling the Incus host CLI.

## Architecture

```
ct/*.sh → misc/build.func
            ├─ Incus  → misc/incus-build.func
            │             ├─ misc/build-ui.func
            │             └─ misc/incus-backend.func
            └─ PVE    → misc/build-ui.func + misc/pve-backend.func
```

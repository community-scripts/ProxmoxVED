# NetWatcher (Proxmox Community Script)

Native Debian LXC installer for [NetWatcher](https://github.com/andrewtryder/unifi-netwatcher) (UniFi unknown-device monitor).

## Install (after merge to ProxmoxVED)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/ct/netwatcher.sh)"
```

Final intended command after acceptance into Community Scripts:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/netwatcher.sh)"
```

## Defaults

| Setting | Value |
|---|---|
| OS | Debian 13 |
| CPU | 2 |
| RAM | 1024 MiB |
| Disk | 6 GiB |
| Privilege | Unprivileged |
| Architectures | AMD64, ARM64 |
| Port | 8080 |

## Layout

```text
/opt/netwatcher/current -> /opt/netwatcher/releases/<version>
/etc/netwatcher/netwatcher.env
/var/lib/netwatcher/{netwatcher.db,app-secret.key,backups/}
```

Service user: `netwatcher` (non-login). Application source is root-owned; only `/var/lib/netwatcher` is writable by the service.

## First boot

1. Open `http://<container-ip>:8080`
2. Sign in with `admin` / `admin` and change the password immediately
3. Edit `/etc/netwatcher/netwatcher.env` with UniFi URL/credentials
4. Set `UNIFI_MOCK_MODE=false`
5. `systemctl restart netwatcher`

`APP_SECRET_KEY` is left empty so NetWatcher generates `/var/lib/netwatcher/app-secret.key` on first start.

## Updates

Re-run the Community Script **inside** the NetWatcher LXC. The updater:

- Downloads the latest stable release into a new versioned directory
- Installs locked dependencies with `uv sync --frozen --no-dev`
- Backs up env + DB + key under `/var/lib/netwatcher/backups/<timestamp>/`
- Runs Alembic migrations
- Atomically switches `/opt/netwatcher/current`
- Polls `/readyz` and rolls back on failure

Never overwrite env/DB/key except during explicit rollback restore. Always restore the database and `app-secret.key` together.

## Operations

```bash
systemctl status netwatcher
journalctl -u netwatcher -f
systemctl restart netwatcher
```

## Security notes

- Trusted-host checks are enabled; LAN IP-literal access works initially
- Add DNS names under **Security → Trusted Hosts**
- Prefer an HTTPS reverse proxy; do not expose to the public internet
- HTTP Basic credentials are not encrypted on plain HTTP
- `MemoryDenyWriteExecute` is omitted because Python C extensions (cryptography / argon2) need executable mappings

## Known limitations / eligibility

- NetWatcher GitHub stars may be below the Community Scripts new-app threshold for upstream `ProxmoxVE` acceptance; this lives in **ProxmoxVED** for testing first
- Releases use GitHub source tarballs; built static assets (`app.css`, `js/`, `fonts/`) must remain committed in the tagged release (no Node build inside the LXC)
- No checksum assets are published yet; downloads fail closed on incomplete archives and missing static files

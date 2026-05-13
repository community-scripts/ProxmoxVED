# ruTorrent LXC

ruTorrent is a web-based front-end for the **rTorrent** BitTorrent client. It runs entirely
inside an LXC container — rTorrent handles the actual downloading while ruTorrent provides
the browser UI, plugin system, and RSS/automation features.

---

## What is ruTorrent?

ruTorrent communicates with rTorrent over a local UNIX socket using the XMLRPC protocol.
nginx handles HTTPS termination and PHP-FPM serves the UI. Everything stays inside the
container; there is no external dependency.

```
Browser → nginx (port 80) → PHP-FPM → ruTorrent
                          ↓
                    rTorrent (SCGI socket)
```

Key capabilities:
- Plugin system with 40+ official plugins (RSS feeds, ratio enforcement, labels, media info, etc.)
- Watch directory for automatic torrent loading
- Optional `/RPC2` XMLRPC endpoint for Sonarr, Radarr, and autodl-irssi

---

## Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/ct/rutorrent.sh)"
```

The installer prompts for:
- Web UI username and password (blank password = random 16-char generated)
- Which plugins to enable (checklist with sensible defaults)
- Whether to expose the `/RPC2` XMLRPC endpoint
- Maximum upload file size for the filedrop plugin

**Default resources**

| Resource | Default |
|----------|---------|
| CPU | 2 cores |
| RAM | 2048 MB |
| Disk | 8 GB |
| OS | Debian 13 |

> **Note:** The 8 GB disk covers the OS and application only. Download storage should be
> provided via a separate mount point — see [Adding Storage](#adding-storage) below.

---

## First Login

Credentials are saved inside the container at `~/rutorrent.creds`:

```bash
# From the Proxmox host shell:
pct exec <CTID> -- cat /root/rutorrent.creds
```

Then open `http://<container-ip>/` in your browser.

---

## Plugin Selection

During install a checklist lets you enable or disable each plugin. All official plugins
that work on Debian 13 / PHP 8 are pre-checked. Three plugins are **off by default**
because they are broken on the current stack:

| Plugin | Reason disabled |
|--------|-----------------|
| `throttle` | Uses removed rTorrent 0.9.x API commands |
| `xmpp` | Uses removed PHP 8 API (`$HTTP_RAW_POST_DATA`) |
| `dump` | Requires `dumptorrent` binary, not available in Debian 13 |

To change plugin state after install, edit `/var/www/rutorrent/conf/plugins.ini` inside
the container and reload the browser tab — no service restart needed:

```ini
[history]
enabled = yes

[throttle]
enabled = no
```

---

## Adding Storage

Keep the LXC on fast storage (SSD) and mount your data disk into the container as a
bind mount. You must set ownership on the host path manually before or after mounting —
see step 3 below.

### 1 — Prepare the disk on the Proxmox host

```bash
# Find your disk
lsblk

# Format if needed (skip if already formatted)
mkfs.ext4 /dev/sdX1

# Mount permanently via /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/sdX1)  /mnt/torrents  ext4  defaults,nofail  0  2" \
  >> /etc/fstab
mount -a
```

### 2 — Add the mount point to the container

```bash
# pct set <CTID> -mpN <host-path>,mp=<container-path>,size=0
pct set 100 -mp0 /mnt/torrents,mp=/data,size=0
```

For additional disks use `-mp1`, `-mp2`, etc., mapping to `/data2`, `/data3`, …

### 3 — Fix ownership

> **Unprivileged containers** shift UIDs by 100000. The `torrent` user (uid 999 inside
> the container) appears as uid **100999** on the host.

```bash
# Unprivileged container (default)
chown -R 100999:100999 /mnt/torrents

# Privileged container
chown -R 999:999 /mnt/torrents

chmod 750 /mnt/torrents
```

### 4 — Set the download directory in ruTorrent

In ruTorrent → **Settings → Downloads** → set the default directory to `/data`.

---

## Connecting Sonarr / Radarr / autodl-irssi

The `/RPC2` XMLRPC endpoint is **disabled by default**. Enable it either during install
(answer Yes to the XMLRPC prompt) or manually afterwards:

```bash
# Inside the container — add to the server {} block in nginx config
nano /etc/nginx/sites-available/rutorrent
```

Add inside the `server { }` block:

```nginx
location /RPC2 {
    include scgi_params;
    scgi_pass unix:///run/rtorrent/rtorrent.sock;
}
```

```bash
systemctl reload nginx
```

**Sonarr / Radarr client settings**

| Field | Value |
|-------|-------|
| Host | `<container-ip>` |
| Port | `80` |
| URL Path | `/RPC2` |
| Username | your ruTorrent username |
| Password | your ruTorrent password |

---

## Key File Locations

| Purpose | Path (inside container) |
|---------|------------------------|
| ruTorrent web root | `/var/www/rutorrent/` |
| ruTorrent config | `/var/www/rutorrent/conf/config.php` |
| Plugin enable/disable | `/var/www/rutorrent/conf/plugins.ini` |
| rTorrent config | `/var/lib/rtorrent/.rtorrent.rc` |
| Downloads (default) | `/var/lib/rtorrent/downloads/` |
| Session data | `/var/lib/rtorrent/session/` |
| Watch directory | `/var/lib/rtorrent/.watch/` |
| nginx site config | `/etc/nginx/sites-available/rutorrent` |
| HTTP auth file | `/etc/nginx/.rutorrent_htpasswd` |
| Saved credentials | `/root/rutorrent.creds` |

---

## Service Management

```bash
# Status
systemctl status rtorrent
systemctl status nginx
systemctl status php8.4-fpm   # php8.4 is the Debian 13 default; confirm with: systemctl list-units 'php*-fpm'

# Restart after config changes
systemctl restart rtorrent
systemctl restart nginx
systemctl restart php8.4-fpm

# Attach to the live rTorrent session
screen -r rtorrent
# Detach without stopping: Ctrl+A then D
```

### Change web UI password

```bash
htpasswd /etc/nginx/.rutorrent_htpasswd <username>
systemctl reload nginx
```

---

## Updating

Re-run the installer script from the Proxmox host shell and select **Update** when
prompted. This fetches the latest ruTorrent release tag via git — your configuration,
credentials, and session data are preserved.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/ct/rutorrent.sh)"
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| 502 Bad Gateway on all pages | PHP-FPM socket not created | `systemctl restart php8.4-fpm` |
| nginx shows default welcome page | nginx not reloaded after config write | `systemctl restart nginx` |
| rTorrent socket missing after install | rTorrent failed to start | `systemctl status rtorrent` then check `/var/lib/rtorrent/.rtorrent.rc` |
| Plugin shows “will not work” error | Missing dependency plugin | Check `plugins.ini` — `_task`, `ratio`, `rss` must be `enabled = yes` |
| Downloads owned by wrong user | Mount point uid mismatch | Re-run `chown -R 100999:100999 <host-path>` (unprivileged) or `999:999` (privileged) |
| `_cloudflare` plugin fails | Python dependencies missing | `apt install python3 python3-cloudscraper python-is-python3` inside the container |

### Check logs

```bash
# nginx errors (PHP, plugin, and proxy errors appear here)
tail -f /var/log/nginx/error.log

# rTorrent journal
journalctl -u rtorrent -f

# PHP-FPM journal
journalctl -u php8.4-fpm -f
```

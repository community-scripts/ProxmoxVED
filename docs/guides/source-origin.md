# Script Origin (Fork / Branch / Local)

Community Scripts resolve `misc/` and `install/` from a **dynamic origin** so forks and feature branches can be tested without editing hundreds of URL lines.

## How it works

Each `ct/*.sh` keeps a **single** source line:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
```

1. Local checkout → relative `misc/build.func` (no network).
2. Remote / `curl|bash` → curl, honouring `COMMUNITY_SCRIPTS_URL` or upstream `main`.
3. [`misc/build.func`](../../misc/build.func) sets `COMMUNITY_SCRIPTS_DIR` / git-based `COMMUNITY_SCRIPTS_URL` (via [`misc/source-origin.func`](../../misc/source-origin.func)) and prefers local files for follow-up fetches.

Explicit env vars always win.

## Local testing (recommended)

From any clone or fork checkout — no env needed:

```bash
bash ct/debian.sh
```

Uncommitted changes under `misc/` and `install/` are used automatically via `COMMUNITY_SCRIPTS_DIR`.

`COMMUNITY_SCRIPTS_URL` is derived from `origin` + branch so in-container curls (and `/usr/bin/update`) follow your fork once the branch is pushed.

## Remote fork / PR testing

`bash <(curl …/ct/app.sh)` cannot see the fetch URL (Bash only gets `/dev/fd/…`). Use the runner with **one** base URL:

```bash
BASE=https://raw.githubusercontent.com/YOU/ProxmoxVED/your-branch
curl -fsSL "$BASE/misc/run.sh" | bash -s -- "$BASE" ct/debian.sh
```

Or set the env yourself:

```bash
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/YOU/ProxmoxVED/your-branch
bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/debian.sh")"
```

Gitea example:

```bash
BASE=https://git.community-scripts.org/YOU/ProxmoxVED/raw/branch/your-branch
curl -fsSL "$BASE/misc/run.sh" | bash -s -- "$BASE" ct/debian.sh
```

## Normal end users

No change: without a local checkout or env, scripts use

`https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main`.

## Related

- Incus host notes: [incus.md](incus.md)
- Override state dir (defaults/logs): `COMMUNITY_SCRIPTS_STATE_DIR`

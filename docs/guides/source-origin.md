# Script Origin (Fork / Branch / Local)

A script has to find two things, and they now live in two repositories: the
**engine** (`community-scripts/core`) and the **scripts** (this repo). Each is
resolved independently, so a fork of one can be tested against upstream of the
other without editing a URL in 89 files.

| What | Directory override | URL override |
| ---- | ------------------ | ------------ |
| Engine (`shared/`, `pve/`, `incus/`) | `COMMUNITY_SCRIPTS_CORE_DIR` | `COMMUNITY_SCRIPTS_CORE_URL` |
| Scripts (`ct/`, `install/`, `vm/`) | `COMMUNITY_SCRIPTS_ROOT` | `COMMUNITY_SCRIPTS_URL` |

## How it works

Each `ct/*.sh` keeps a single bootstrap block:

```bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
```

1. A checkout of core sitting next to this repo (`../core`) is used first, with
   no network. `COMMUNITY_SCRIPTS_CORE_DIR` overrides where to look.
2. Otherwise the engine comes from `COMMUNITY_SCRIPTS_CORE_URL`, defaulting to
   upstream `core@main`.
3. `shared/build.func` then finds the **scripts** root by walking up from the
   running script to the first directory holding both `ct/` and `install/`, and
   derives `COMMUNITY_SCRIPTS_URL` from that checkout's git remote and branch —
   so in-container fetches and `/usr/bin/update` follow your fork once the
   branch is pushed.

Explicit environment variables always win over both.

## Local testing (recommended)

Clone both repositories side by side:

```
somewhere/
├── core/
└── ProxmoxVED/
```

Then, from the ProxmoxVED checkout, with no environment at all:

```bash
bash ct/debian.sh
```

Uncommitted changes in either checkout are picked up. To try a core branch
against unmodified scripts, move only the engine:

```bash
COMMUNITY_SCRIPTS_CORE_DIR=~/work/core-experiment bash ct/debian.sh
```

## Remote fork / PR testing

`bash <(curl …/ct/app.sh)` cannot see the URL it was fetched from — Bash only
gets `/dev/fd/…` — so the script cannot infer your fork. Set the roots yourself:

```bash
# A fork of the scripts, upstream engine
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/YOU/ProxmoxVED/your-branch
bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/debian.sh")"
```

```bash
# A branch of the engine, upstream scripts
export COMMUNITY_SCRIPTS_CORE_URL=https://raw.githubusercontent.com/YOU/core/your-branch
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/ct/debian.sh)"
```

Both can be set at once. Gitea and any other raw-file host work the same way —
these are plain base URLs:

```bash
export COMMUNITY_SCRIPTS_URL=https://git.community-scripts.org/YOU/ProxmoxVED/raw/branch/your-branch
```

## Normal end users

No change: without a checkout or environment, scripts take the engine from
`community-scripts/core@main` and everything else from
`community-scripts/ProxmoxVED@main`.

## Related

- Incus host notes: [incus.md](incus.md)
- Override state dir (defaults/logs): `COMMUNITY_SCRIPTS_STATE_DIR`

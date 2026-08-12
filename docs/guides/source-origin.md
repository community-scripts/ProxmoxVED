# Script Origin (Fork / Branch / Local)

A script has to find two things, and they live in two repositories: the
**engine** (`community-scripts/core`) and the **scripts** (this repo). Each is
resolved independently, so a fork of one can be tested against upstream of the
other without editing a URL in 104 files.

| What | Directory override | URL override |
| ---- | ------------------ | ------------ |
| Engine (`core/`, `ui/`, `lib/`, `lxc/`, `host/`, `api/`, `vm/`, `pve/`, `incus/`) | `COMMUNITY_SCRIPTS_CORE_DIR` | `COMMUNITY_SCRIPTS_CORE_URL` |
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
3. `core/build.func` then finds the **scripts** root by walking up from the
   running script to the first directory holding both `ct/` and `install/`, and
   derives `COMMUNITY_SCRIPTS_URL` from that checkout's git remote and branch —
   so in-container fetches and `/usr/bin/update` follow your fork once the
   branch is pushed.

Explicit environment variables always win over both.

---

## Adding a script

A script is two files. The install filename is not a convention, it is derived:
`variables()` lowercases `APP` and strips spaces to get `NSAPP`, then appends
`-install`. `APP="MyApp"` therefore requires exactly:

```
ct/myapp.sh
install/myapp-install.sh
```

Get that name wrong and the build fails with exit 22 when the host cannot fetch
the install script. `json/` is website metadata and plays no part at run time.

The **host** reads `install/<app>-install.sh` and pipes its contents into
`lxc-attach`. The container never fetches it — which is why a local checkout is
enough, and why nothing on the scripts side has to be reachable from inside the
container.

## Testing it — variant 1: public fork

Push your branch, then point the scripts root at it. This is the closest thing
to what a user will actually run.

```bash
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/YOU/ProxmoxVED/your-branch
bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/myapp.sh")"
```

**`COMMUNITY_SCRIPTS_URL` is not optional here.** Fetching the ct script from
your fork does not tell the engine where that fork is: with `bash -c "$(curl …)"`
there is no file on disk, so the walk-up that normally finds the scripts root
has nothing to walk, and `COMMUNITY_SCRIPTS_URL` falls back to upstream
`ProxmoxVED@main`. Your ct script would run and then look for your install
script in upstream main, where it does not exist. Setting it explicitly is what
keeps both halves on your fork.

`tools/run.sh` in core does exactly this and sets both bases for you:

```bash
curl -fsSL https://raw.githubusercontent.com/community-scripts/core/main/tools/run.sh |
  bash -s -- https://raw.githubusercontent.com/YOU/ProxmoxVED/your-branch ct/myapp.sh
```

Add a third argument to move the engine too:

```bash
curl -fsSL https://raw.githubusercontent.com/community-scripts/core/main/tools/run.sh |
  bash -s -- https://raw.githubusercontent.com/YOU/ProxmoxVED/your-branch ct/myapp.sh \
             https://raw.githubusercontent.com/YOU/core/your-branch
```

Every run needs a push, so this variant is for verifying a finished script
rather than for iterating on one.

## Testing it — variant 2: local checkout

No push, no network on the scripts side, and the only variant that works with a
**private** fork. Clone both repositories side by side on the Proxmox host:

```
somewhere/
├── core/
└── ProxmoxVED/
```

```bash
cd /opt
git clone https://github.com/YOU/ProxmoxVED
git clone https://github.com/community-scripts/core
cd ProxmoxVED && bash ct/myapp.sh
```

No environment variables needed. Edit, re-run, repeat — uncommitted changes in
either checkout are picked up immediately. Clone your own fork of core only if
you are changing the engine; otherwise upstream core is fine.

To try a core branch against unmodified scripts, move only the engine:

```bash
COMMUNITY_SCRIPTS_CORE_DIR=~/work/core-experiment bash ct/myapp.sh
```

### Why a private fork cannot use variant 1

`_cs_download` calls plain `curl -fsSL` with no authentication header, so
`raw.githubusercontent.com` answers 404 for a private repository. There is no
token support on this path — `var_github_token` covers the GitHub API in
`lib/forge.func`, not script fetching.

## Two things that surprise people

**`/usr/bin/update` inside the container** is written with whatever
`COMMUNITY_SCRIPTS_URL` was set to at install time. On a private fork the
install itself succeeds, but running `update` in the container later hits a 404.

**No banner.** The header generator in core walks ProxmoxVE, ProxmoxVED and
Incus — not your fork. `header_info()` prints nothing when a header is missing
rather than failing, so this is cosmetic.

## Useful while testing

```bash
dev_mode=keep,net,timing bash ct/myapp.sh
```

`keep` stops a failed build from deleting the container along with the evidence.
`net` logs every engine fetch with status and duration, which is the quickest
way to confirm you are running your checkout and not production. The full list
of flags is in [core's dev-mode documentation](https://github.com/community-scripts/core/blob/main/docs/dev-mode.md).

## Other hosts

Gitea and any other raw-file host work the same way — these are plain base URLs:

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

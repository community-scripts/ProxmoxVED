<div align="center">
  <a href="#">
    <img src="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/images/logo.png" height="100px" />
 </a>
</div>
<h1 align="center"></h1>

<h3 align="center">All notable changes to this project will be documented in this file.</h3>

## 2025-05-13

### 🆕 New Scripts

  - Alpine-Traefik [@MickLesk](https://github.com/MickLesk) ([#4412](https://github.com/community-scripts/ProxmoxVE/pull/4412))
- alpine-transmission ([#4277](https://github.com/community-scripts/ProxmoxVE/pull/4277))
- streamlink-webui ([#4262](https://github.com/community-scripts/ProxmoxVE/pull/4262))

### 🚀 Updated Scripts

  - update some improvements from dev (tools.func) [@MickLesk](https://github.com/MickLesk) ([#4430](https://github.com/community-scripts/ProxmoxVE/pull/4430))
- Alpine: Use onliner for updates [@tremor021](https://github.com/tremor021) ([#4414](https://github.com/community-scripts/ProxmoxVE/pull/4414))
- Alpine scripts: Set minimum disk space to 0.5GB [@tremor021](https://github.com/tremor021) ([#4288](https://github.com/community-scripts/ProxmoxVE/pull/4288))

  - #### 🐞 Bug Fixes

    - openhab: use zulu17-jdk [@moodyblue](https://github.com/moodyblue) ([#4438](https://github.com/community-scripts/ProxmoxVE/pull/4438))
    - homarr: fetch versions dynamically from source repo [@CrazyWolf13](https://github.com/CrazyWolf13) ([#4409](https://github.com/community-scripts/ProxmoxVE/pull/4409))
    - Zammad: Enable ElasticSearch service [@tremor021](https://github.com/tremor021) ([#4391](https://github.com/community-scripts/ProxmoxVE/pull/4391))
    - (fix) Documenso: fix build failures [@vhsdream](https://github.com/vhsdream) ([#4382](https://github.com/community-scripts/ProxmoxVE/pull/4382))
    - Jellyseerr: better handling of node and pnpm [@MickLesk](https://github.com/MickLesk) ([#4365](https://github.com/community-scripts/ProxmoxVE/pull/4365))
    - Authentik: change install to UV & increase resources to 10GB RAM [@MickLesk](https://github.com/MickLesk) ([#4364](https://github.com/community-scripts/ProxmoxVE/pull/4364))
    - SearXNG: fix to resolve yaml dependency error [@Biendeo](https://github.com/Biendeo) ([#4322](https://github.com/community-scripts/ProxmoxVE/pull/4322))
    - Bugfix: Mikrotik & Pimox HAOS VM (NEXTID) [@MickLesk](https://github.com/MickLesk) ([#4313](https://github.com/community-scripts/ProxmoxVE/pull/4313))
    - SuwayomiServer: Bump Java to v21, code formating [@tremor021](https://github.com/tremor021) ([#3987](https://github.com/community-scripts/ProxmoxVE/pull/3987))

  - #### ✨ New Features

    - Feature: LXC-Delete (pve helper): add "all items" [@MickLesk](https://github.com/MickLesk) ([#4296](https://github.com/community-scripts/ProxmoxVE/pull/4296))
    - HomeAssistant-Core: update script for 2025.5+ [@MickLesk](https://github.com/MickLesk) ([#4363](https://github.com/community-scripts/ProxmoxVE/pull/4363))
    - Feature: autologin for Alpine [@MickLesk](https://github.com/MickLesk) ([#4344](https://github.com/community-scripts/ProxmoxVE/pull/4344))
    - Feature: get correct next VMID [@MickLesk](https://github.com/MickLesk) ([#4292](https://github.com/community-scripts/ProxmoxVE/pull/4292))

### 🧰 Maintenance

  - #### 💾 Core

    - Config file Function in build.func [@michelroegl-brunner](https://github.com/michelroegl-brunner) ([#4411](https://github.com/community-scripts/ProxmoxVE/pull/4411))
    - fix: detect all bridge types, not just vmbr prefix [@filippolauria](https://github.com/filippolauria) ([#4351](https://github.com/community-scripts/ProxmoxVE/pull/4351))
    - build.func Change the menu for Bridge Selection [@michelroegl-brunner](https://github.com/michelroegl-brunner) ([#4326](https://github.com/community-scripts/ProxmoxVE/pull/4326))

  - #### 📂 Github

    - Add a Repo check to all Workflows [@michelroegl-brunner](https://github.com/michelroegl-brunner) ([#4339](https://github.com/community-scripts/ProxmoxVE/pull/4339))
    - Auto-Merge Automatic PR [@michelroegl-brunner](https://github.com/michelroegl-brunner) ([#4343](https://github.com/community-scripts/ProxmoxVE/pull/4343))

### 🌐 Website

  - FAQ: Explanation "updatable" [@tremor021](https://github.com/tremor021) ([#4300](https://github.com/community-scripts/ProxmoxVE/pull/4300))

  - #### 📝 Script Information

    - Pingvin Share: Added explanation on how to add/edit environment variables [@tremor021](https://github.com/tremor021) ([#4432](https://github.com/community-scripts/ProxmoxVE/pull/4432))
    - pingvin.json: fix typo [@warmbo](https://github.com/warmbo) ([#4426](https://github.com/community-scripts/ProxmoxVE/pull/4426))
    - Navidrome - Fix config path (use /etc/ instead of /var/lib) [@quake1508](https://github.com/quake1508) ([#4406](https://github.com/community-scripts/ProxmoxVE/pull/4406))
    - OpenWebUI: Update docs link [@tremor021](https://github.com/tremor021) ([#4298](https://github.com/community-scripts/ProxmoxVE/pull/4298))

## 2025-03-24

### 🆕 New Scripts

- fileflows [@kkroboth](https://github.com/kkroboth) ([#3392](https://github.com/community-scripts/ProxmoxVE/pull/3392))
- wazuh [@omiinaya](https://github.com/omiinaya) ([#3381](https://github.com/community-scripts/ProxmoxVE/pull/3381))
- yt-dlp-webui [@CrazyWolf13](https://github.com/CrazyWolf13) ([#3364](https://github.com/community-scripts/ProxmoxVE/pull/3364))
- Extension/New Script: Redis Alpine Installation [@MickLesk](https://github.com/MickLesk) ([#3367](https://github.com/community-scripts/ProxmoxVE/pull/3367))
- Fluid Calendar [@vhsdream](https://github.com/vhsdream) ([#2869](https://github.com/community-scripts/ProxmoxVE/pull/2869))

### 🚀 Updated Scripts

- License url VED to VE [@bvdberg01](https://github.com/bvdberg01) ([#3258](https://github.com/community-scripts/ProxmoxVE/pull/3258))
- Omada jdk to jre [@bvdberg01](https://github.com/bvdberg01) ([#3319](https://github.com/community-scripts/ProxmoxVE/pull/3319))

  - #### 🐞 Bug Fixes

    - Extend HOME Env for Kubo [@MickLesk](https://github.com/MickLesk) ([#3397](https://github.com/community-scripts/ProxmoxVE/pull/3397))
    - Fluid-Calendar: Remove unneeded $STD in update [@MickLesk](https://github.com/MickLesk) ([#3250](https://github.com/community-scripts/ProxmoxVE/pull/3250))
    - Snipe-IT: Remove composer update & add no interaction for install [@MickLesk](https://github.com/MickLesk) ([#3256](https://github.com/community-scripts/ProxmoxVE/pull/3256))
    - Cronicle: add missing gnupg package [@MickLesk](https://github.com/MickLesk) ([#3323](https://github.com/community-scripts/ProxmoxVE/pull/3323))
    - GoMFT: Check if build-essential is present before updating, if not then install it [@tremor021](https://github.com/tremor021) ([#3358](https://github.com/community-scripts/ProxmoxVE/pull/3358))
    - revealjs: Fix update process [@tremor021](https://github.com/tremor021) ([#3341](https://github.com/community-scripts/ProxmoxVE/pull/3341))
    - MySQL: Correctly add repo to mysql.list [@tremor021](https://github.com/tremor021) ([#3315](https://github.com/community-scripts/ProxmoxVE/pull/3315))
    - Omada zulu 8 to 21 [@bvdberg01](https://github.com/bvdberg01) ([#3318](https://github.com/community-scripts/ProxmoxVE/pull/3318))
    - GoMFT: Fix build dependencies [@tremor021](https://github.com/tremor021) ([#3313](https://github.com/community-scripts/ProxmoxVE/pull/3313))
    - GoMFT: Don't rely on binaries from github [@tremor021](https://github.com/tremor021) ([#3303](https://github.com/community-scripts/ProxmoxVE/pull/3303))
    - Wikijs: Remove Dev Message & Performance-Boost [@bvdberg01](https://github.com/bvdberg01) ([#3232](https://github.com/community-scripts/ProxmoxVE/pull/3232))
    - Update omada download url [@bvdberg01](https://github.com/bvdberg01) ([#3245](https://github.com/community-scripts/ProxmoxVE/pull/3245))
    - TriliumNotes: Fix release handling [@tremor021](https://github.com/tremor021) ([#3160](https://github.com/community-scripts/ProxmoxVE/pull/3160))

  - #### ✨ New Features

    - Netdata: Update to newer deb File [@MickLesk](https://github.com/MickLesk) ([#3276](https://github.com/community-scripts/ProxmoxVE/pull/3276))
    - [core] Rebase Scripts (formatting, highlighting & remove old deps) [@MickLesk](https://github.com/MickLesk) ([#3378](https://github.com/community-scripts/ProxmoxVE/pull/3378))
    - Update nextcloud-vm.sh to 18.1 ISO [@0xN0BADC0FF33](https://github.com/0xN0BADC0FF33) ([#3333](https://github.com/community-scripts/ProxmoxVE/pull/3333))

  - #### 💥 Breaking Changes

    - FluidCalendar: Switch to safer DB operations [@vhsdream](https://github.com/vhsdream) ([#3270](https://github.com/community-scripts/ProxmoxVE/pull/3270))

  - #### 🔧 Refactor

    - Refactor: ErsatzTV Script [@MickLesk](https://github.com/MickLesk) ([#3365](https://github.com/community-scripts/ProxmoxVE/pull/3365))

### 🧰 Maintenance

- #### ✨ New Features

  - [core] add gitignore to prevent big pulls [@MickLesk](https://github.com/MickLesk) ([#3278](https://github.com/community-scripts/ProxmoxVE/pull/3278))
  - [core] install core deps (debian / ubuntu) [@MickLesk](https://github.com/MickLesk) ([#3366](https://github.com/community-scripts/ProxmoxVE/pull/3366))

- #### 💾 Core

  - [core] extend hardware transcoding for fileflows #3392 [@MickLesk](https://github.com/MickLesk) ([#3396](https://github.com/community-scripts/ProxmoxVE/pull/3396))
  - Clarify MTU in advanced Settings. [@michelroegl-brunner](https://github.com/michelroegl-brunner) ([#3296](https://github.com/community-scripts/ProxmoxVE/pull/3296))

- #### 📂 Github

  - [core] cleanup - remove old backups of workflow files [@MickLesk](https://github.com/MickLesk) ([#3247](https://github.com/community-scripts/ProxmoxVE/pull/3247))
  - Refactor Changelog Workflow [@michelroegl-brunner](https://github.com/michelroegl-brunner) ([#3371](https://github.com/community-scripts/ProxmoxVE/pull/3371))

### 🌐 Website

- Update siteConfig.tsx to use new analytics code [@BramSuurdje](https://github.com/BramSuurdje) ([#3389](https://github.com/community-scripts/ProxmoxVE/pull/3389))
- Bump next from 15.1.3 to 15.2.3 in /frontend [@dependabot[bot]](https://github.com/dependabot[bot]) ([#3316](https://github.com/community-scripts/ProxmoxVE/pull/3316))

  - #### 🐞 Bug Fixes

    - Better Text for Version Date [@michelroegl-brunner](https://github.com/michelroegl-brunner) ([#3388](https://github.com/community-scripts/ProxmoxVE/pull/3388))
    - JSON editor note fix [@bvdberg01](https://github.com/bvdberg01) ([#3260](https://github.com/community-scripts/ProxmoxVE/pull/3260))
    - Move cryptpad files to right folders [@bvdberg01](https://github.com/bvdberg01) ([#3242](https://github.com/community-scripts/ProxmoxVE/pull/3242))

  - #### 📝 Script Information

    - Threadfin: add port for website [@MickLesk](https://github.com/MickLesk) ([#3295](https://github.com/community-scripts/ProxmoxVE/pull/3295))
    - Proxmox, rather than Promox [@gringocl](https://github.com/gringocl) ([#3293](https://github.com/community-scripts/ProxmoxVE/pull/3293))
    - Audiobookshelf: Fix category on website [@jaykup26](https://github.com/jaykup26) ([#3304](https://github.com/community-scripts/ProxmoxVE/pull/3304))
    - CrowdSec: Add debian only warning to website [@tremor021](https://github.com/tremor021) ([#3210](https://github.com/community-scripts/ProxmoxVE/pull/3210))
    - Debian VM: Update webpage with login info [@tremor021](https://github.com/tremor021) ([#3215](https://github.com/community-scripts/ProxmoxVE/pull/3215))
    - Heimdall Dashboard: Fix missing logo on website [@tremor021](https://github.com/tremor021) ([#3227](https://github.com/community-scripts/ProxmoxVE/pull/3227))

## 2025-03-03

### 🚀 Initial Release

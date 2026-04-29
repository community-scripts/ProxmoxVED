<?php

// --- Données système ---

$df = shell_exec("df -B1 /mnt/timemachine 2>/dev/null");
$dfLines = array_filter(explode("\n", trim($df)));
$dfData = preg_split('/\s+/', array_values($dfLines)[1] ?? '');
$diskTotal = isset($dfData[1]) ? (int)$dfData[1] : 0;
$diskUsed  = isset($dfData[2]) ? (int)$dfData[2] : 0;
$diskFree  = isset($dfData[3]) ? (int)$dfData[3] : 0;
$diskPct   = $diskTotal > 0 ? round($diskUsed / $diskTotal * 100, 1) : 0;

function humanSize(int $bytes): string {
    if ($bytes >= 1e12) return round($bytes / 1e12, 2) . ' TB';
    if ($bytes >= 1e9)  return round($bytes / 1e9, 2) . ' GB';
    if ($bytes >= 1e6)  return round($bytes / 1e6, 2) . ' MB';
    return $bytes . ' B';
}

$backups = [];
$items = glob('/mnt/timemachine/*');
foreach ($items ?? [] as $item) {
    if (!is_dir($item)) continue;
    $name = basename($item);
    $sizeRaw = shell_exec("du -sb " . escapeshellarg($item) . " 2>/dev/null");
    $size = (int)explode("\t", $sizeRaw)[0];
    $lastModified = filemtime($item);
    try {
        $files = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($item, FilesystemIterator::SKIP_DOTS));
        foreach ($files as $f) { if ($f->getMTime() > $lastModified) $lastModified = $f->getMTime(); }
    } catch (Exception $e) {}

    if ($name === 'ubuntu') {
        $backups[] = ['name' => 'Ubuntu Desktop', 'type' => 'Déjà Dup', 'icon' => 'ubuntu', 'size' => $size, 'last' => $lastModified];
    } elseif (str_ends_with($name, '.sparsebundle')) {
        $backups[] = ['name' => str_replace('.sparsebundle', '', $name), 'type' => 'Time Machine', 'icon' => 'mac', 'size' => $size, 'last' => $lastModified];
    }
}

$uptimeRaw = shell_exec("uptime -p 2>/dev/null") ?? '';
$uptime = trim(str_replace('up ', '', $uptimeRaw));

$meminfo = @file_get_contents('/proc/meminfo') ?: '';
preg_match('/MemTotal:\s+(\d+)/', $meminfo, $mt);
preg_match('/MemAvailable:\s+(\d+)/', $meminfo, $ma);
$ramTotal = isset($mt[1]) ? (int)$mt[1] * 1024 : 0;
$ramUsed  = $ramTotal - (isset($ma[1]) ? (int)$ma[1] * 1024 : 0);
$ramPct   = $ramTotal > 0 ? round($ramUsed / $ramTotal * 100) : 0;

function serviceActive(string $name): bool {
    return trim(shell_exec("systemctl is-active " . escapeshellarg($name) . " 2>/dev/null")) === 'active';
}
$smbActive   = serviceActive('smbd');
$avahiActive = serviceActive('avahi-daemon');

$now = new DateTime();
$backupCount = count($backups);

?><!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Time Machine Server</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

/* ── Dark (défaut) ── */
:root {
  --bg:        #1c1c1e;
  --surface:   #2c2c2e;
  --surface2:  #3a3a3c;
  --surface3:  #48484a;
  --border:    rgba(255,255,255,0.09);
  --text:      #f5f5f7;
  --text-sec:  #aeaeb2;
  --text-ter:  #636366;
  --blue:      #0a84ff;
  --green:     #30d158;
  --orange:    #ff9f0a;
  --red:       #ff453a;
  --radius:    14px;
  --radius-sm: 10px;
  --shadow:    0 2px 16px rgba(0,0,0,0.35);
}

/* ── Light ── */
html.light {
  --bg:        #f2f2f7;
  --surface:   #ffffff;
  --surface2:  #f2f2f7;
  --surface3:  #e5e5ea;
  --border:    rgba(0,0,0,0.09);
  --text:      #1c1c1e;
  --text-sec:  #636366;
  --text-ter:  #aeaeb2;
  --blue:      #007aff;
  --green:     #34c759;
  --orange:    #ff9500;
  --red:       #ff3b30;
  --shadow:    0 2px 16px rgba(0,0,0,0.07);
}

body {
  background: var(--bg);
  color: var(--text);
  font-family: -apple-system, 'Helvetica Neue', sans-serif;
  font-size: 14px;
  line-height: 1.5;
  min-height: 100vh;
  padding: 32px 24px 48px;
  -webkit-font-smoothing: antialiased;
  transition: background .25s, color .25s;
}

@media (max-width: 600px) {
  body { padding: 20px 16px 40px; }
}

.wrapper { max-width: 860px; margin: 0 auto; }

/* ── Header ── */
header {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 28px; padding-bottom: 20px;
  border-bottom: 1px solid var(--border); gap: 12px;
  flex-wrap: wrap;
}

@media (max-width: 600px) {
  header { flex-direction: column; align-items: flex-start; gap: 14px; }
}

.header-left  { display: flex; align-items: center; gap: 14px; }
.header-right { display: flex; flex-direction: column; align-items: flex-end; gap: 8px; }

@media (max-width: 600px) {
  .header-right { align-items: flex-start; width: 100%; }
}

.app-icon {
  width: 50px; height: 50px;
  background: linear-gradient(145deg, #1a6fdb, #0a84ff);
  border-radius: 13px;
  display: flex; align-items: center; justify-content: center;
  box-shadow: 0 4px 16px rgba(10,132,255,0.35);
  flex-shrink: 0;
}
.app-icon svg { width: 28px; height: 28px; }

h1 { font-size: 20px; font-weight: 600; letter-spacing: -.3px; }
.subtitle { font-size: 12px; color: var(--text-sec); margin-top: 2px; }

/* Boutons contrôle */
.controls { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; }

@media (max-width: 600px) {
  .controls { gap: 5px; }
  .ctrl-btn { padding: 5px 9px; font-size: 11px; }
  .divider  { display: none; }
}

.ctrl-btn {
  background: var(--surface);
  border: 1px solid var(--border);
  color: var(--text-sec);
  font-size: 12px;
  padding: 5px 11px;
  border-radius: 8px;
  cursor: pointer;
  display: flex; align-items: center; gap: 5px;
  transition: background .15s, color .15s, border-color .15s;
  font-family: inherit;
  white-space: nowrap;
  user-select: none;
}
.ctrl-btn:hover  { background: var(--surface2); color: var(--text); }
.ctrl-btn.active { background: var(--blue); border-color: var(--blue); color: #fff; }

.divider {
  width: 1px; height: 20px;
  background: var(--border); margin: 0 2px;
}

.timestamp { font-size: 11px; color: var(--text-ter); }

/* ── Grilles ── */
.grid-top    { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 14px; }
.grid-bottom { display: grid; gap: 14px; }

@media (max-width: 640px) {
  .grid-top { grid-template-columns: 1fr; }
}

/* ── Card ── */
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 18px 20px;
  box-shadow: var(--shadow);
  animation: fadeUp .35s ease both;
  transition: background .25s, border-color .25s, box-shadow .25s;
}
.card:nth-child(1) { animation-delay: .04s; }
.card:nth-child(2) { animation-delay: .08s; }
.card:nth-child(3) { animation-delay: .12s; }

@keyframes fadeUp {
  from { opacity: 0; transform: translateY(8px); }
  to   { opacity: 1; transform: translateY(0); }
}

.card-label {
  font-size: 11px; font-weight: 600;
  letter-spacing: .06em; text-transform: uppercase;
  color: var(--text-ter); margin-bottom: 14px;
}

/* ── Disque ── */
.disk-value {
  font-size: 34px; font-weight: 300;
  letter-spacing: -1.5px; line-height: 1; margin-bottom: 4px;
}
@media (max-width: 400px) {
  .disk-value { font-size: 26px; }
}
.disk-value span { font-size: 17px; font-weight: 400; color: var(--text-sec); }
.disk-sub { font-size: 12px; color: var(--text-ter); margin-bottom: 14px; }

.progress-track {
  height: 6px; background: var(--surface2);
  border-radius: 99px; overflow: hidden; margin-bottom: 8px;
}
.progress-fill {
  height: 100%; border-radius: 99px;
  transition: width .8s cubic-bezier(.4,0,.2,1);
}
.progress-fill.ok     { background: linear-gradient(90deg,#30d158,#34c759); }
.progress-fill.warn   { background: linear-gradient(90deg,#ff9f0a,#ffcc00); }
.progress-fill.danger { background: linear-gradient(90deg,#ff453a,#ff375f); }

.disk-legend { display: flex; gap: 14px; font-size: 11px; color: var(--text-sec); }
.disk-legend span { display: flex; align-items: center; gap: 5px; }
.dot { width: 7px; height: 7px; border-radius: 50%; display: inline-block; }
.dot.used { background: var(--blue); }
.dot.free { background: var(--surface2); border: 1px solid var(--border); }

/* ── Stats ── */
.stat-row { display: flex; gap: 10px; margin-bottom: 12px; }
.stat-pill {
  flex: 1; background: var(--surface2); border: 1px solid var(--border);
  border-radius: var(--radius-sm); padding: 10px 13px;
  display: flex; align-items: center; gap: 10px;
  transition: background .25s;
}
.stat-icon { font-size: 20px; line-height: 1; }
.stat-val  { font-size: 14px; font-weight: 600; }
.stat-lbl  { font-size: 11px; color: var(--text-ter); }

/* ── Services ── */
.service-list  { display: flex; flex-direction: column; gap: 8px; }
.service-row {
  display: flex; align-items: center; justify-content: space-between;
  padding: 9px 12px; background: var(--surface2);
  border-radius: var(--radius-sm); border: 1px solid var(--border);
  transition: background .25s;
}
.service-name { font-size: 13px; font-weight: 500; }
.service-desc { font-size: 11px; color: var(--text-ter); margin-top: 1px; }

.badge {
  font-size: 11px; font-weight: 600;
  padding: 3px 9px; border-radius: 99px;
  white-space: nowrap;
}
.badge.on  { background: rgba(48,209,88,.18);  color: var(--green); }
.badge.off { background: rgba(255,69,58,.18);   color: var(--red);  }

/* ── Backups ── */
.backup-list { display: flex; flex-direction: column; gap: 9px; }
.backup-row {
  display: flex; align-items: center; gap: 14px;
  padding: 13px 15px; background: var(--surface2);
  border-radius: var(--radius-sm); border: 1px solid var(--border);
  transition: background .15s;
}
.backup-row:hover { background: var(--surface3); }

@media (max-width: 480px) {
  .backup-row { flex-wrap: wrap; }
  .backup-size { width: 100%; text-align: left; margin-top: 4px; padding-left: 56px; }
}

.backup-avatar {
  width: 42px; height: 42px; border-radius: 10px;
  display: flex; align-items: center; justify-content: center;
  font-size: 22px; flex-shrink: 0;
}
.backup-avatar.mac    { background: linear-gradient(145deg,#3a3a3c,#2c2c2e); border: 1px solid rgba(255,255,255,.08); }
.backup-avatar.ubuntu { background: linear-gradient(145deg,#772953,#e95420); }
html.light .backup-avatar.mac { background: linear-gradient(145deg,#e5e5ea,#d1d1d6); border: 1px solid rgba(0,0,0,.08); }

.backup-info { flex: 1; min-width: 0; }
.backup-name { font-size: 14px; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.backup-meta {
  font-size: 11px; color: var(--text-ter); margin-top: 3px;
  display: flex; gap: 8px; align-items: center; flex-wrap: wrap;
}
.backup-type { font-size: 11px; font-weight: 600; padding: 2px 8px; border-radius: 99px; }
.backup-type.tm { background: rgba(10,132,255,.18); color: var(--blue); }
.backup-type.dj { background: rgba(255,159,10,.18);  color: var(--orange); }

.backup-size { font-size: 14px; font-weight: 500; color: var(--text-sec); text-align: right; flex-shrink: 0; }
.backup-size small { display: block; font-size: 11px; color: var(--text-ter); font-weight: 400; margin-top: 2px; }

.empty { text-align: center; color: var(--text-ter); padding: 24px; font-size: 13px; }
</style>
</head>
<body>
<div class="wrapper">

<header>
  <div class="header-left">
    <div class="app-icon">
      <svg viewBox="0 0 30 30" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="15" cy="15" r="12" stroke="white" stroke-width="1.5" stroke-dasharray="3 2"/>
        <circle cx="15" cy="15" r="5" fill="white"/>
        <line x1="15" y1="3" x2="15" y2="8" stroke="white" stroke-width="1.5" stroke-linecap="round"/>
        <line x1="15" y1="22" x2="15" y2="27" stroke="white" stroke-width="1.5" stroke-linecap="round"/>
        <line x1="3" y1="15" x2="8" y2="15" stroke="white" stroke-width="1.5" stroke-linecap="round"/>
        <line x1="22" y1="15" x2="27" y2="15" stroke="white" stroke-width="1.5" stroke-linecap="round"/>
      </svg>
    </div>
    <div>
      <h1>Time Machine Server</h1>
      <div class="subtitle">timemachine.pve.local &nbsp;·&nbsp; 192.168.1.143</div>
    </div>
  </div>

  <div class="header-right">
    <div class="controls">
      <button class="ctrl-btn" id="btn-fr" onclick="setLang('fr')">🇫🇷 FR</button>
      <button class="ctrl-btn" id="btn-en" onclick="setLang('en')">🇬🇧 EN</button>
      <div class="divider"></div>
      <button class="ctrl-btn" id="btn-theme" onclick="toggleTheme()">☀️</button>
      <div class="divider"></div>
      <button class="ctrl-btn" onclick="location.reload()">↻</button>
    </div>
    <div class="timestamp"><?= $now->format('d/m/Y H:i:s') ?></div>
  </div>
</header>

<div class="grid-top">

  <!-- Disque -->
  <div class="card">
    <div class="card-label" data-i18n="storage"></div>
    <div class="disk-value">
      <?= humanSize($diskUsed) ?> <span data-i18n="used"></span>
    </div>
    <div class="disk-sub">
      <?= humanSize($diskFree) ?> <span data-i18n="free-of"></span> <?= humanSize($diskTotal) ?> &nbsp;·&nbsp; <?= $diskPct ?>%
    </div>
    <div class="progress-track">
      <div class="progress-fill <?= $diskPct >= 90 ? 'danger' : ($diskPct >= 70 ? 'warn' : 'ok') ?>"
           style="width:<?= min($diskPct, 100) ?>%"></div>
    </div>
    <div class="disk-legend">
      <span><i class="dot used"></i> <span data-i18n="used-leg"></span></span>
      <span><i class="dot free"></i> <span data-i18n="free-leg"></span></span>
    </div>
  </div>

  <!-- Ressources + Services -->
  <div class="card">
    <div class="card-label" data-i18n="resources"></div>
    <div class="stat-row">
      <div class="stat-pill">
        <div class="stat-icon">🧠</div>
        <div>
          <div class="stat-val"><?= humanSize($ramUsed) ?></div>
          <div class="stat-lbl">RAM · <?= $ramPct ?>%</div>
        </div>
      </div>
      <div class="stat-pill">
        <div class="stat-icon">⏱</div>
        <div>
          <div class="stat-val" style="font-size:12px;line-height:1.3"><?= htmlspecialchars($uptime) ?></div>
          <div class="stat-lbl" data-i18n="uptime-lbl"></div>
        </div>
      </div>
    </div>

    <div class="card-label" style="margin-top:4px" data-i18n="services"></div>
    <div class="service-list">
      <div class="service-row">
        <div>
          <div class="service-name">smbd</div>
          <div class="service-desc" data-i18n="smb-desc"></div>
        </div>
        <span class="badge <?= $smbActive ? 'on' : 'off' ?>" data-i18n="<?= $smbActive ? 'svc-on' : 'svc-off' ?>"></span>
      </div>
      <div class="service-row">
        <div>
          <div class="service-name">avahi-daemon</div>
          <div class="service-desc" data-i18n="avahi-desc"></div>
        </div>
        <span class="badge <?= $avahiActive ? 'on' : 'off' ?>" data-i18n="<?= $avahiActive ? 'svc-on' : 'svc-off' ?>"></span>
      </div>
    </div>
  </div>

</div>

<!-- Sauvegardes -->
<div class="grid-bottom">
  <div class="card">
    <div class="card-label">
      <span data-i18n="backups"></span> &nbsp;·&nbsp;
      <?= $backupCount ?> <span data-i18n="<?= $backupCount > 1 ? 'volumes' : 'volume' ?>"></span>
    </div>

    <?php if (empty($backups)): ?>
      <div class="empty" data-i18n="no-backups"></div>
    <?php else: ?>
    <div class="backup-list">
      <?php foreach ($backups as $b): ?>
      <div class="backup-row">
        <div class="backup-avatar <?= $b['icon'] ?>">
          <?= $b['icon'] === 'mac' ? '🍎' : '🐧' ?>
        </div>
        <div class="backup-info">
          <div class="backup-name"><?= htmlspecialchars($b['name']) ?></div>
          <div class="backup-meta">
            <span class="backup-type <?= $b['type'] === 'Time Machine' ? 'tm' : 'dj' ?>">
              <?= htmlspecialchars($b['type']) ?>
            </span>
            <span data-i18n="last-activity"></span>&nbsp;: <?= date('d/m/Y H:i', $b['last']) ?>
          </div>
        </div>
        <div class="backup-size">
          <?= humanSize($b['size']) ?>
          <small data-i18n="on-disk"></small>
        </div>
      </div>
      <?php endforeach; ?>
    </div>
    <?php endif; ?>
  </div>
</div>

</div>

<script>
const T = {
  fr: {
    'storage':       'Stockage · tank/timemachine',
    'used':          'utilisés',
    'free-of':       'libres sur',
    'used-leg':      'Utilisé',
    'free-leg':      'Libre',
    'resources':     'Ressources système',
    'uptime-lbl':    'Disponibilité',
    'services':      'Services',
    'smb-desc':      'Partage Samba SMB',
    'avahi-desc':    'Découverte réseau mDNS',
    'svc-on':        'Actif',
    'svc-off':       'Arrêté',
    'backups':       'Sauvegardes',
    'volume':        'volume',
    'volumes':       'volumes',
    'last-activity': 'Dernière activité',
    'on-disk':       'sur disque',
    'no-backups':    'Aucune sauvegarde trouvée dans /mnt/timemachine',
  },
  en: {
    'storage':       'Storage · tank/timemachine',
    'used':          'used',
    'free-of':       'free of',
    'used-leg':      'Used',
    'free-leg':      'Free',
    'resources':     'System resources',
    'uptime-lbl':    'Uptime',
    'services':      'Services',
    'smb-desc':      'Samba SMB share',
    'avahi-desc':    'mDNS network discovery',
    'svc-on':        'Active',
    'svc-off':       'Stopped',
    'backups':       'Backups',
    'volume':        'volume',
    'volumes':       'volumes',
    'last-activity': 'Last activity',
    'on-disk':       'on disk',
    'no-backups':    'No backup found in /mnt/timemachine',
  }
};

let lang  = localStorage.getItem('tm-lang')  || 'fr';
let theme = localStorage.getItem('tm-theme') || 'dark';

function applyLang(l) {
  lang = l;
  localStorage.setItem('tm-lang', l);
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[l][k] !== undefined) el.textContent = T[l][k];
  });
  document.getElementById('btn-fr').classList.toggle('active', l === 'fr');
  document.getElementById('btn-en').classList.toggle('active', l === 'en');
}

function setLang(l) { applyLang(l); }

function applyTheme(t) {
  theme = t;
  localStorage.setItem('tm-theme', t);
  document.documentElement.classList.toggle('light', t === 'light');
  document.getElementById('btn-theme').textContent = t === 'light' ? '🌙' : '☀️';
}

function toggleTheme() { applyTheme(theme === 'dark' ? 'light' : 'dark'); }

// Init au chargement
applyTheme(theme);
applyLang(lang);
</script>
</body>
</html>
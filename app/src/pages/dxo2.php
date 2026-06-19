<?php
declare(strict_types=1);

require_once __DIR__ . '/../lib/product.php';

auth_require_admin();

// ── Helpers ────────────────────────────────────────────────────────────────────

/**
 * Return the last $n lines of a file without reading the whole thing.
 *
 * @param string $path  Absolute path to the file.
 * @param int    $n     Number of lines to return.
 *
 * @return string  Tail content, or empty string if unreadable.
 */
function tail_file(string $path, int $n = 40): string {
  if (!is_readable($path)) {
    return '';
  }
  $fp = fopen($path, 'rb');
  if (!$fp) {
    return '';
  }
  fseek($fp, 0, SEEK_END);
  $size = ftell($fp);
  if ($size === 0) {
    fclose($fp);
    return '';
  }
  $buffer = '';
  $lines  = 0;
  $chunk  = 4096;
  $pos    = $size;
  while ($pos > 0 && $lines <= $n) {
    $read  = min($chunk, $pos);
    $pos  -= $read;
    fseek($fp, $pos);
    $buffer = fread($fp, $read) . $buffer;
    $lines  = substr_count($buffer, "\n");
  }
  fclose($fp);
  $parts = explode("\n", $buffer);
  return implode("\n", array_slice($parts, -$n));
}

/**
 * Try to open a TCP connection; return true if reachable within $timeout.
 *
 * @param string $host     Hostname or IP.
 * @param int    $port     TCP port.
 * @param int    $timeout  Seconds to wait.
 *
 * @return bool  True when a connection was established.
 */
function check_tcp(string $host, int $port, int $timeout = 2): bool {
  $fp = @fsockopen($host, $port, $errno, $errstr, $timeout);
  if ($fp) {
    fclose($fp);
    return true;
  }
  return false;
}

/**
 * Parse a flat key=value INI file into an associative array.
 * Lines starting with ; or # are skipped.
 *
 * @param string $path  Absolute path to the INI file.
 *
 * @return array<string,string>  Parsed key/value pairs.
 */
function parse_ini_flat(string $path): array {
  if (!is_readable($path)) {
    return [];
  }
  $result = [];
  foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
    $line = trim($line);
    if ($line === '' || $line[0] === ';' || $line[0] === '#') {
      continue;
    }
    $eq = strpos($line, '=');
    if ($eq === false) {
      continue;
    }
    $result[trim(substr($line, 0, $eq))] = trim(substr($line, $eq + 1));
  }
  return $result;
}

// ── Static paths ───────────────────────────────────────────────────────────────
define('BPA_CONF_PATH',       '/etc/apache2/conf-enabled/bpa.conf');
define('APMIA_HOME',          '/opt/apmia');
define('APMIA_LOGS_DIR',      '/opt/apmia/logs');
define('BTL_LOG_PATH',        '/opt/apmia/logs/BTListener.log');
define('PHP_PROBE_LOGS_DIR',  '/var/log/php-probe');

// The /opt/apmia directory is populated by the dxo2-init initContainer.
// Its absence means the DX O2 sidecar is not enabled (dxo2.enabled=false in Helm).
$dxo2Deployed = is_dir(APMIA_HOME);

// Build the apache2 conf.d path from the running PHP version (avoids hardcoding 8.1).
$phpConfD = sprintf('/etc/php/%d.%d/apache2/conf.d', PHP_MAJOR_VERSION, PHP_MINOR_VERSION);

// ── 1. PHP Probe ───────────────────────────────────────────────────────────────
$probeLoaded = extension_loaded('wily_php_agent');

// The entrypoint places the INI as a symlink with a numeric prefix, e.g.:
//   /etc/php/8.1/apache2/conf.d/99-wily_php_agent.ini -> /etc/php/8.1/mods-available/wily_php_agent.ini
// Glob for any *-wily_php_agent.ini so the check works regardless of priority prefix.
$iniSymlinks    = glob($phpConfD . '/*-wily_php_agent.ini') ?: [];
$iniSymlinkPath = $iniSymlinks[0] ?? null;
$iniRealPath    = $iniSymlinkPath ? (realpath($iniSymlinkPath) ?: $iniSymlinkPath) : null;
$iniExists      = $iniSymlinkPath !== null;
$iniValues      = $iniRealPath ? parse_ini_flat($iniRealPath) : [];

$probeIniDisplay = [
  'wily_php_agent.agentName'                                   => 'Agent name',
  'wily_php_agent.collectorHost'                               => 'Collector host',
  'wily_php_agent.collectorPort'                               => 'Collector port',
  'wily_php_agent.logdir'                                      => 'Log directory',
  'wily_php_agent.disableLogging'                              => 'Logging disabled flag',
  'wily_php_agent.logLevel'                                    => 'Log level',
  'wily_php_agent.enable.browseragent.snippet.autoInjection'   => 'Browser-agent auto-injection',
  'wily_php_agent.browseragent.autoInjection.snippetString'    => 'Browser snippet configured',
];

// ── 2. BPA Apache module ───────────────────────────────────────────────────────
$bpaConfExists  = file_exists(BPA_CONF_PATH);
$bpaConfContent = $bpaConfExists ? (file_get_contents(BPA_CONF_PATH) ?: '') : '';
$bpaModuleName  = '';
if (preg_match('/LoadModule\s+(\S+)\s/', $bpaConfContent, $bm)) {
  $bpaModuleName = $bm[1];
}

// Authoritative detection: apache2ctl -t -D DUMP_MODULES lists every loaded
// module by its internal name.  The BPA Apache module is always registered as
// 'caplugin_module'.  Fall back to apache_get_modules() when shell_exec is
// unavailable (e.g. PHP disable_functions).
$dumpRaw    = '';
$dumpList   = [];
$dumpViaCmd = false;
if (function_exists('shell_exec')) {
  $raw = shell_exec('apache2ctl -t -D DUMP_MODULES 2>&1') ?? '';
  if ($raw !== '') {
    $dumpRaw    = trim($raw);
    $dumpViaCmd = true;
    foreach (explode("\n", $raw) as $line) {
      if (preg_match('/^\s+(\w+_module)\b/', $line, $mm)) {
        $dumpList[] = $mm[1];
      }
    }
  }
}
if (empty($dumpList) && function_exists('apache_get_modules')) {
  $dumpList   = apache_get_modules();
  $dumpViaCmd = false;
}

$bpaModuleLoaded = in_array('caplugin_module', $dumpList, true);

// ── 3. Browser agent ───────────────────────────────────────────────────────────
$baEnabled = ($iniValues['wily_php_agent.enable.browseragent.snippet.autoInjection'] ?? '0') === '1';
$baSnippet = $iniValues['wily_php_agent.browseragent.autoInjection.snippetString'] ?? '';

// ── 4. APMIA connectivity ──────────────────────────────────────────────────────
$phpCollectorHost = getenv('APMIA_PHP_COLLECTOR_HOST') ?: '127.0.0.1';
$phpCollectorPort = (int) (getenv('APMIA_PHP_COLLECTOR_PORT') ?: 5005);
$btlHost          = getenv('APMIA_BTL_HOST') ?: '127.0.0.1';
$btlPort          = (int) (getenv('APMIA_BTL_PORT') ?: 8000);
$phpReachable     = check_tcp($phpCollectorHost, $phpCollectorPort);
$btlReachable     = check_tcp($btlHost, $btlPort);

// ── 5. APMIA log files ─────────────────────────────────────────────────────────
$logFiles = [];
if (is_dir(APMIA_LOGS_DIR)) {
  $found = glob(APMIA_LOGS_DIR . '/*.log') ?: [];
  sort($found);
  foreach ($found as $logPath) {
    if (basename($logPath) === 'BTListener.log') {
      continue; // shown in the dedicated BTListener log card below
    }
    $logFiles[basename($logPath)] = tail_file($logPath, 40);
  }
}

// ── 6. PHP probe log files ─────────────────────────────────────────────────────
// The probe generates two naming groups; keep the 2 most recent per group:
//   Group A: wily_php_agent_<pid>.log            (active per-process log)
//   Group B: wily_php_agent_<pid>-<ts>_N.log     (rolled log with sequence suffix)
$phpProbeLogFiles = [];
if (is_dir(PHP_PROBE_LOGS_DIR)) {
  $found = glob(PHP_PROBE_LOGS_DIR . '/wily_php_agent*.log') ?: [];
  sort($found);
  $groupA = [];
  $groupB = [];
  foreach ($found as $logPath) {
    if (preg_match('/wily_php_agent_\d+-\d+_\d+\.log$/', basename($logPath))) {
      $groupB[] = $logPath;
    }
    else {
      $groupA[] = $logPath;
    }
  }
  foreach (array_merge(array_slice($groupA, -2), array_slice($groupB, -2)) as $logPath) {
    $phpProbeLogFiles[basename($logPath)] = tail_file($logPath, 40);
  }
}

// ── 7. BTListener log ──────────────────────────────────────────────────────────
$btlLogContent = tail_file(BTL_LOG_PATH, 40);

// ── 6. APMIA environment variables ────────────────────────────────────────────
$apmiaEnv = [];
foreach ($_SERVER as $k => $v) {
  if (!is_string($k) || !is_string($v)) {
    continue;
  }
  if (str_starts_with($k, 'APMIA_') || str_starts_with($k, 'APMENV_')) {
    if (preg_match('/PASSWORD|SECRET|TOKEN|KEY|JWT|CREDENTIAL/i', $k)) {
      $apmiaEnv[$k] = '*** redacted ***';
    }
    else {
      $apmiaEnv[$k] = $v;
    }
  }
}
ksort($apmiaEnv);

// ── Overall health flags (used in summary row) ─────────────────────────────────
$overallOk = $probeLoaded && $bpaModuleLoaded && $phpReachable;

$pageTitle = APP_NAME . ' – DX O2 Status';
require __DIR__ . '/../templates/layout.php';
?>

<div class="section-title" style="margin-bottom:1.2rem">&#128202; DX O2 Agent Status</div>

<?php /* ── Summary badges ──────────────────────────────────────────────────── */ ?>
<div style="display:flex;gap:1rem;flex-wrap:wrap;margin-bottom:1.5rem">
<?php
$badges = [
  ['PHP probe',      $probeLoaded,     $probeLoaded     ? 'loaded'     : 'not loaded'],
  ['BPA module',     $bpaModuleLoaded, $bpaModuleLoaded ? 'loaded'     : 'not loaded'],
  ['Browser agent',  $baEnabled,       $baEnabled       ? 'enabled'    : 'disabled'],
  ['PHP collector',  $phpReachable,    $phpReachable    ? 'reachable'  : 'unreachable'],
  ['BTL',            $btlReachable,    $btlReachable    ? 'reachable'  : 'unreachable'],
];
foreach ($badges as [$label, $ok, $state]):
  $bg = $ok ? '#e8f5e9' : '#fff8e1';
  $col = $ok ? '#2e7d32' : '#f57f17';
  $icon = $ok ? '&#10003;' : '&#9888;';
?>
  <div class="card" style="flex:1;min-width:130px;text-align:center;margin-bottom:0;padding:.9rem">
    <div style="font-size:1.6rem;color:<?= $col ?>"><?= $icon ?></div>
    <div style="font-size:.85rem;font-weight:700;color:<?= $col ?>;margin-top:.3rem"><?= $state ?></div>
    <div style="font-size:.75rem;color:#607d8b;margin-top:.15rem"><?= $label ?></div>
  </div>
<?php endforeach ?>
</div>

<?php if (!$dxo2Deployed): ?>
<div class="card" style="margin-bottom:1.2rem">
  <p class="alert alert-info" style="margin:0">
    <strong>DX O2 not deployed.</strong>
    The <code>/opt/apmia</code> volume is absent — the DX O2 sidecar has not been enabled.
    To activate monitoring, set a non-empty <code>APMIA_EM_HOST</code> in <code>.config</code>
    and redeploy (<code>build-scripts/deploy.sh</code>).
  </p>
</div>
<?php else: ?>

<?php /* ── PHP Probe ────────────────────────────────────────────────────────── */ ?>
<div class="card" style="margin-bottom:1.2rem">
  <h2>PHP Probe (wily_php_agent)</h2>
  <table class="admin-table" style="max-width:700px;margin-bottom:1rem">
    <thead>
      <tr><th>Check</th><th>Status / Value</th></tr>
    </thead>
    <tbody>
      <tr>
        <td>Extension loaded</td>
        <td><?php if ($probeLoaded): ?>
          <span style="color:#2e7d32;font-weight:700">&#10003; yes</span>
        <?php else: ?>
          <span style="color:#c62828;font-weight:700">&#10007; no</span>
          <span style="color:#607d8b;font-size:.8rem"> — apmia volume absent or probe injection failed</span>
        <?php endif ?></td>
      </tr>
      <tr>
        <td>INI symlink<br>
            <span style="font-size:.75rem;color:#90a4ae"><?= htmlspecialchars($phpConfD) ?>/*-wily_php_agent.ini</span></td>
        <td><?php if ($iniExists): ?>
          <span style="color:#2e7d32">&#10003;</span>
          <code style="font-size:.82rem"><?= htmlspecialchars((string) $iniSymlinkPath) ?></code>
          <?php if ($iniRealPath && $iniRealPath !== $iniSymlinkPath): ?>
            <br><span style="font-size:.75rem;color:#90a4ae">&#8594; <?= htmlspecialchars($iniRealPath) ?></span>
          <?php endif ?>
        <?php else: ?>
          <span style="color:#c62828">&#10007; not found</span>
          <span style="color:#607d8b;font-size:.8rem"> — no *-wily_php_agent.ini in <?= htmlspecialchars($phpConfD) ?></span>
        <?php endif ?></td>
      </tr>
      <?php foreach ($probeIniDisplay as $iniKey => $label): ?>
      <?php
        $val = $iniValues[$iniKey] ?? null;
        if ($iniKey === 'wily_php_agent.browseragent.autoInjection.snippetString') {
          $display = $val !== null ? '&#10003; set (' . mb_strlen(trim($val, "'")) . ' chars)' : '<span style="color:#607d8b">not set</span>';
        }
        else {
          $display = $val !== null ? '<code style="font-size:.82rem">' . htmlspecialchars($val) . '</code>' : '<span style="color:#607d8b">not set</span>';
        }
      ?>
      <tr>
        <td><?= htmlspecialchars($label) ?><br>
            <span style="font-size:.75rem;color:#90a4ae"><?= htmlspecialchars($iniKey) ?></span></td>
        <td><?= $display ?></td>
      </tr>
      <?php endforeach ?>
    </tbody>
  </table>
</div>

<?php /* ── BPA Apache module ─────────────────────────────────────────────────── */ ?>
<div class="card" style="margin-bottom:1.2rem">
  <h2>BPA Web Server Plugin (Apache)</h2>
  <table class="admin-table" style="max-width:700px;margin-bottom:1rem">
    <thead>
      <tr><th>Check</th><th>Status / Value</th></tr>
    </thead>
    <tbody>
      <tr>
        <td>Conf file</td>
        <td><?php if ($bpaConfExists): ?>
          <span style="color:#2e7d32">&#10003;</span>
          <code style="font-size:.82rem"><?= htmlspecialchars(BPA_CONF_PATH) ?></code>
        <?php else: ?>
          <span style="color:#c62828">&#10007; not found</span>
          <span style="color:#607d8b;font-size:.8rem"> — BPA Apache .so absent or conf injection failed</span>
        <?php endif ?></td>
      </tr>
      <tr>
        <td>LoadModule name<br>
            <span style="font-size:.75rem;color:#90a4ae">from bpa.conf</span></td>
        <td><?php if ($bpaModuleName !== ''): ?>
          <code style="font-size:.82rem"><?= htmlspecialchars($bpaModuleName) ?></code>
        <?php else: ?>
          <span style="color:#607d8b">unknown — conf not found or not parsed</span>
        <?php endif ?></td>
      </tr>
      <tr>
        <td>caplugin_module loaded<br>
            <span style="font-size:.75rem;color:#90a4ae">
              <?= $dumpViaCmd ? 'apache2ctl -t -D DUMP_MODULES' : 'apache_get_modules()' ?>
            </span></td>
        <td><?php if ($bpaModuleLoaded): ?>
          <span style="color:#2e7d32;font-weight:700">&#10003; yes</span>
        <?php elseif (!empty($dumpList)): ?>
          <span style="color:#c62828;font-weight:700">&#10007; no</span>
          <span style="color:#607d8b;font-size:.8rem"> — caplugin_module not in module list</span>
        <?php else: ?>
          <span style="color:#f57f17">&#9888; unable to determine — shell_exec and apache_get_modules() both unavailable</span>
        <?php endif ?></td>
      </tr>
    </tbody>
  </table>
  <?php if ($bpaConfContent !== ''): ?>
  <div style="font-size:.8rem;color:#607d8b;margin-bottom:.3rem">
    <strong>bpa.conf contents:</strong>
  </div>
  <pre style="background:#1a1a2e;color:#b0bec5;border-radius:8px;padding:1rem;font-size:.8rem;overflow-x:auto;white-space:pre-wrap;word-break:break-all;margin-bottom:1rem"><?= htmlspecialchars($bpaConfContent) ?></pre>
  <?php endif ?>
  <?php if ($dumpRaw !== ''): ?>
  <div style="font-size:.8rem;color:#607d8b;margin-bottom:.3rem">
    <strong>apache2ctl -t -D DUMP_MODULES output:</strong>
  </div>
  <pre style="background:#1a1a2e;color:#b0bec5;border-radius:8px;padding:1rem;font-size:.75rem;max-height:280px;overflow-y:auto;white-space:pre-wrap;word-break:break-all"><?= htmlspecialchars($dumpRaw) ?></pre>
  <?php elseif (!$dumpViaCmd && function_exists('apache_get_modules')): ?>
  <p style="font-size:.8rem;color:#90a4ae;font-style:italic">
    shell_exec unavailable — module list sourced from apache_get_modules().
  </p>
  <?php endif ?>
</div>

<?php /* ── Browser Agent ─────────────────────────────────────────────────────── */ ?>
<div class="card" style="margin-bottom:1.2rem">
  <h2>Browser Agent Auto-Injection</h2>
  <table class="admin-table" style="max-width:700px">
    <thead>
      <tr><th>Check</th><th>Status / Value</th></tr>
    </thead>
    <tbody>
      <tr>
        <td>Auto-injection enabled<br>
            <span style="font-size:.75rem;color:#90a4ae">wily_php_agent.enable.browseragent.snippet.autoInjection</span></td>
        <td><?php if ($baEnabled): ?>
          <span style="color:#2e7d32;font-weight:700">&#10003; enabled (1)</span>
        <?php else: ?>
          <span style="color:#607d8b">disabled (0 or not set)</span>
          <span style="font-size:.8rem;color:#90a4ae"> — set APMIA_BROWSER_SNIPPET in .config to activate</span>
        <?php endif ?></td>
      </tr>
      <tr>
        <td>Snippet configured<br>
            <span style="font-size:.75rem;color:#90a4ae">wily_php_agent.browseragent.autoInjection.snippetString</span></td>
        <td><?php if ($baSnippet !== ''): ?>
          <span style="color:#2e7d32;font-weight:700">&#10003; set</span>
          <span style="color:#607d8b;font-size:.8rem"> (<?= mb_strlen(trim($baSnippet, "'")) ?> chars)</span>
        <?php else: ?>
          <span style="color:#607d8b">not set</span>
        <?php endif ?></td>
      </tr>
    </tbody>
  </table>
</div>

<?php /* ── APMIA Connectivity ────────────────────────────────────────────────── */ ?>
<div class="card" style="margin-bottom:1.2rem">
  <h2>APMIA Connectivity</h2>
  <table class="admin-table" style="max-width:700px">
    <thead>
      <tr><th>Endpoint</th><th>Address</th><th>Status</th></tr>
    </thead>
    <tbody>
      <tr>
        <td>PHP collector</td>
        <td><code style="font-size:.82rem"><?= htmlspecialchars($phpCollectorHost) ?>:<?= $phpCollectorPort ?></code></td>
        <td><?php if ($phpReachable): ?>
          <span style="color:#2e7d32;font-weight:700">&#10003; reachable</span>
        <?php else: ?>
          <span style="color:#c62828;font-weight:700">&#10007; unreachable</span>
          <span style="color:#607d8b;font-size:.8rem"> — IA sidecar not running or wrong host/port</span>
        <?php endif ?></td>
      </tr>
      <tr>
        <td>Business Transaction Listener</td>
        <td><code style="font-size:.82rem"><?= htmlspecialchars($btlHost) ?>:<?= $btlPort ?></code></td>
        <td><?php if ($btlReachable): ?>
          <span style="color:#2e7d32;font-weight:700">&#10003; reachable</span>
        <?php else: ?>
          <span style="color:#c62828;font-weight:700">&#10007; unreachable</span>
          <span style="color:#607d8b;font-size:.8rem"> — BTL sidecar not running or wrong host/port</span>
        <?php endif ?></td>
      </tr>
    </tbody>
  </table>
</div>

<?php /* ── APMIA environment variables ──────────────────────────────────────── */ ?>
<div class="card" style="margin-bottom:1.2rem">
  <h2>APMIA / APMENV Environment Variables</h2>
  <?php if (empty($apmiaEnv)): ?>
    <p class="alert alert-info">No APMIA_* or APMENV_* variables found in the container environment — dxo2 sidecar not enabled.</p>
  <?php else: ?>
  <table class="admin-table" style="max-width:900px">
    <thead>
      <tr><th>Variable</th><th>Value</th></tr>
    </thead>
    <tbody>
      <?php foreach ($apmiaEnv as $k => $v): ?>
      <tr>
        <td><code style="font-size:.8rem"><?= htmlspecialchars($k) ?></code></td>
        <td style="word-break:break-all;max-width:500px">
          <?php if ($v === '*** redacted ***'): ?>
            <span style="color:#90a4ae;font-style:italic">*** redacted ***</span>
          <?php else: ?>
            <code style="font-size:.8rem"><?= htmlspecialchars($v) ?></code>
          <?php endif ?>
        </td>
      </tr>
      <?php endforeach ?>
    </tbody>
  </table>
  <?php endif ?>
</div>

<?php /* ── APMIA log tails ───────────────────────────────────────────────────── */ ?>
<div class="card" style="margin-bottom:1.2rem">
  <h2>APMIA Logs
    <span style="font-size:.8rem;font-weight:400;color:#607d8b">
      &nbsp;(<?= htmlspecialchars(APMIA_LOGS_DIR) ?> — last 40 lines per file)
    </span>
  </h2>
  <?php if (empty($logFiles)): ?>
    <p class="alert alert-info">No log files found — apmia volume absent or not yet written to.</p>
  <?php else: ?>
    <?php foreach ($logFiles as $name => $content): ?>
    <div style="margin-bottom:1rem">
      <div style="font-size:.85rem;font-weight:700;color:#3949ab;margin-bottom:.3rem">
        &#128196; <?= htmlspecialchars($name) ?>
      </div>
      <?php if ($content === ''): ?>
        <p style="font-size:.8rem;color:#90a4ae;font-style:italic">Empty.</p>
      <?php else: ?>
        <pre style="background:#1a1a2e;color:#b0bec5;border-radius:8px;padding:1rem;font-size:.75rem;max-height:320px;overflow-y:auto;white-space:pre-wrap;word-break:break-all"><?= htmlspecialchars($content) ?></pre>
      <?php endif ?>
    </div>
    <?php endforeach ?>
  <?php endif ?>
</div>

<?php /* ── PHP probe log tail ──────────────────────────────────────────────────── */ ?>
<div class="card" style="margin-bottom:1.2rem">
  <h2>PHP Probe Logs
    <span style="font-size:.8rem;font-weight:400;color:#607d8b">
      &nbsp;(<?= htmlspecialchars(PHP_PROBE_LOGS_DIR) ?> — 2 most recent per group, last 40 lines each)
    </span>
  </h2>
  <?php if (empty($phpProbeLogFiles)): ?>
    <p class="alert alert-info">No log files found in <?= htmlspecialchars(PHP_PROBE_LOGS_DIR) ?> — probe not yet active or logging not yet triggered.</p>
  <?php else: ?>
    <?php foreach ($phpProbeLogFiles as $name => $content): ?>
    <div style="margin-bottom:1rem">
      <div style="font-size:.85rem;font-weight:700;color:#3949ab;margin-bottom:.3rem">
        &#128196; <?= htmlspecialchars($name) ?>
      </div>
      <?php if ($content === ''): ?>
        <p style="font-size:.8rem;color:#90a4ae;font-style:italic">Empty.</p>
      <?php else: ?>
        <pre style="background:#1a1a2e;color:#b0bec5;border-radius:8px;padding:1rem;font-size:.75rem;max-height:320px;overflow-y:auto;white-space:pre-wrap;word-break:break-all"><?= htmlspecialchars($content) ?></pre>
      <?php endif ?>
    </div>
    <?php endforeach ?>
  <?php endif ?>
</div>

<?php /* ── BTListener log tail ─────────────────────────────────────────────────── */ ?>
<div class="card" style="margin-bottom:1.2rem">
  <h2>BTListener Log
    <span style="font-size:.8rem;font-weight:400;color:#607d8b">
      &nbsp;(<?= htmlspecialchars(BTL_LOG_PATH) ?> — last 40 lines)
    </span>
  </h2>
  <?php if ($btlLogContent === ''): ?>
    <p class="alert alert-info">Log file not found or empty — BTL not yet started or log not yet written to.</p>
  <?php else: ?>
    <pre style="background:#1a1a2e;color:#b0bec5;border-radius:8px;padding:1rem;font-size:.75rem;max-height:320px;overflow-y:auto;white-space:pre-wrap;word-break:break-all"><?= htmlspecialchars($btlLogContent) ?></pre>
  <?php endif ?>
</div>

<?php endif /* $dxo2Deployed */ ?>

<?php require __DIR__ . '/../templates/footer.php' ?>

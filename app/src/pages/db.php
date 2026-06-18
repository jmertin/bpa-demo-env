<?php
declare(strict_types=1);

require_once __DIR__ . '/../lib/product.php';

auth_require_admin();

$host = getenv('MARIADB_HOST')     ?: '127.0.0.1';
$port = (int) (getenv('MARIADB_PORT') ?: 3306);
$db   = getenv('MARIADB_DATABASE') ?: 'phpapp';
$user = getenv('MARIADB_USER')     ?: 'phpuser';
$pass = getenv('MARIADB_PASSWORD') ?: '';

$pageTitle = 'Database';
require __DIR__ . '/../templates/layout.php';

echo "<h2>MariaDB Connection Test</h2>\n";

try {
  $dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
  $pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_TIMEOUT            => 5,
  ]);

  $version = $pdo->query('SELECT VERSION() AS v')->fetchColumn();
  $uptime  = $pdo->query("SHOW STATUS LIKE 'Uptime'")->fetch()['Value'] ?? '?';

  echo "<p class=\"alert alert-success\">&#10003; Connected successfully</p>\n";
  echo "<table class=\"admin-table\" style=\"max-width:500px\">\n";
  echo "  <tr><th>Parameter</th><th>Value</th></tr>\n";
  echo '  <tr><td>Server version</td><td>' . htmlspecialchars((string) $version) . "</td></tr>\n";
  echo '  <tr><td>Uptime (s)</td><td>' . htmlspecialchars((string) $uptime) . "</td></tr>\n";
  echo '  <tr><td>Database</td><td>' . htmlspecialchars($db) . "</td></tr>\n";
  echo '  <tr><td>Host</td><td>' . htmlspecialchars($host) . ':' . $port . "</td></tr>\n";
  echo "</table>\n";
}
catch (PDOException $e) {
  echo '<p class="alert alert-error">&#10007; Connection failed: ' . htmlspecialchars($e->getMessage()) . "</p>\n";
}

require __DIR__ . '/../templates/footer.php';

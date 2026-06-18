<?php
declare(strict_types=1);

require_once __DIR__ . '/../lib/product.php';

auth_require_admin();

$pageTitle = 'PHP Info';
require __DIR__ . '/../templates/layout.php';

echo "<h2>PHP Runtime Information</h2>\n";
echo "<table class=\"admin-table\" style=\"max-width:700px\">\n";
echo "  <tr><th>Parameter</th><th>Value</th></tr>\n";
$rows = [
  'PHP Version'       => PHP_VERSION,
  'SAPI'              => PHP_SAPI,
  'OS'                => PHP_OS_FAMILY,
  'Architecture'      => PHP_INT_SIZE === 8 ? '64-bit' : '32-bit',
  'Memory limit'      => ini_get('memory_limit'),
  'Max exec time'     => ini_get('max_execution_time') . 's',
  'Loaded extensions' => implode(', ', get_loaded_extensions()),
];
foreach ($rows as $k => $v) {
  echo '  <tr><td>' . htmlspecialchars($k) . '</td><td>' . htmlspecialchars((string) $v) . "</td></tr>\n";
}
echo "</table>\n";

require __DIR__ . '/../templates/footer.php';

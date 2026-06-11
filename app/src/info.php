<?php
declare(strict_types=1);

render_header('PHP Info');

echo "<h2>PHP Runtime Information</h2>\n";
echo "<table>\n";
$rows = [
    'PHP Version'      => PHP_VERSION,
    'SAPI'             => PHP_SAPI,
    'OS'               => PHP_OS_FAMILY,
    'Architecture'     => PHP_INT_SIZE === 8 ? '64-bit' : '32-bit',
    'Memory limit'     => ini_get('memory_limit'),
    'Max exec time'    => ini_get('max_execution_time') . 's',
    'Loaded extensions'=> implode(', ', get_loaded_extensions()),
];
foreach ($rows as $k => $v) {
    echo "  <tr><th>" . htmlspecialchars($k) . "</th><td>" . htmlspecialchars((string)$v) . "</td></tr>\n";
}
echo "</table>\n";

render_footer();

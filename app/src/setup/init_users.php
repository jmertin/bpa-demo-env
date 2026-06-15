<?php
// Database initialisation check – run via kubectl exec, NOT via HTTP.
// This file must not be web-accessible; nginx blocks the /setup/ path.

// Only allow CLI execution.
if (PHP_SAPI !== 'cli') {
  http_response_code(403);
  exit("This script must be run from the command line.\n");
}

require_once __DIR__ . '/../config/database.php';

$pdo = db();

// Verify connection.
$row = $pdo->query('SELECT VERSION() AS v')->fetch();
echo 'Connected to MariaDB ' . $row['v'] . "\n";

// Report user count.
$count = $pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
echo "Users in database: {$count}\n";

// Report product count.
$count = $pdo->query('SELECT COUNT(*) FROM products')->fetchColumn();
echo "Products in database: {$count}\n";

// Report use-case assignments.
$stmt = $pdo->query("
  SELECT u.username, uu.usecase_name
  FROM user_usecases uu
  JOIN users u ON u.id = uu.user_id
  ORDER BY u.username
");
echo "Use-case assignments:\n";
foreach ($stmt->fetchAll() as $row) {
  echo "  {$row['username']} → {$row['usecase_name']}\n";
}

echo "Initialisation check complete.\n";

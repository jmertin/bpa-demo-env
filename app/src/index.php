<?php
// BPA-Demo front controller.
// All requests are routed here by nginx (SCRIPT_FILENAME hardcoded).

require_once __DIR__ . '/config/app.php';
require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/lib/validate.php';
require_once __DIR__ . '/lib/page_id.php';
require_once __DIR__ . '/lib/auth.php';
require_once __DIR__ . '/lib/basket.php';
require_once __DIR__ . '/lib/usecase.php';

// ── Resolve page ───────────────────────────────────────────────────────────────
$page = validate_slug($_GET['page'] ?? 'shop') ?? 'shop';

// Valid routes → page file mapping.
$routes = [
  'shop'     => 'pages/shop.php',
  'product'  => 'pages/product.php',
  'basket'   => 'pages/basket.php',
  'checkout' => 'pages/checkout.php',
  'order'    => 'pages/order.php',
  'login'    => 'pages/login.php',
  'logout'   => 'pages/logout.php',
  'admin'    => 'pages/admin.php',
];

if (!array_key_exists($page, $routes)) {
  $page = 'shop';
}

// ── Run use case for logged-in user ────────────────────────────────────────────
$ctx = ['page' => $page];
usecase_run($ctx);

// ── Dispatch ──────────────────────────────────────────────────────────────────
$file = __DIR__ . '/' . $routes[$page];
if (!is_file($file)) {
  http_response_code(404);
  exit('Page not found.');
}

require $file;

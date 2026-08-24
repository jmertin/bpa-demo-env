<?php
// BPA-Demo front controller.
// Every page is reached as index.php?page=<slug> -- there is no clean-URL
// rewriting (vhost.conf has no RewriteRule at all).  Bare / and /index.php
// default to 'shop' internally, with no redirect.

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
  'info'     => 'pages/info.php',
  'db'       => 'pages/db.php',
  'dxo2'     => 'pages/dxo2.php',
];

if (!array_key_exists($page, $routes)) {
  $page = 'shop';
}

// Emit a baseline page identifier on every response so monitoring tools and
// browser devtools always see X-Page-ID regardless of which page is served.
// Pages that call set_monitoring_headers() replace this with a richer value.
header('X-Page-ID: page_' . $page);

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

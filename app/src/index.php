<?php
// BPA-Demo front controller.
// Routing is controlled by the APP_TYPE environment variable (see
// lib/routing.php): "mp" (the default) reaches every page as a clean URL
// (/shop, /basket, ...) via a per-page wrapper file at the document root
// and a vhost.conf rewrite rule; "plain" reaches every page as
// index.php?page=<slug> with no rewriting at all. Either way, $_GET['page']
// is already set by the time this file runs (the wrapper file sets it in
// mp mode; the query string sets it directly in plain mode), so the
// dispatch logic below is identical for both modes.

require_once __DIR__ . '/config/app.php';
require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/lib/validate.php';
require_once __DIR__ . '/lib/routing.php';
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
// Uppercased to match set_page_id()/set_monitoring_headers()'s own
// MODULE-ACTION-TARGET format, which is always uppercase (see page_id.php) --
// pages that call set_monitoring_headers() replace this with a richer value.
header('X-Page-ID: PAGE_' . strtoupper($page));

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

<?php
// Application constants and session bootstrap.

define('APP_NAME',    'BPA-Demo');
define('APP_VERSION', '1.0.0');

// Session cookie is HTTP-only, same-site strict, no JS access.
if (session_status() === PHP_SESSION_NONE) {
  session_set_cookie_params([
    'lifetime' => 3600,
    'path'     => '/',
    'secure'   => isset($_SERVER['HTTPS']),
    'httponly' => true,
    'samesite' => 'Strict',
  ]);
  session_start();
}

// CSRF token: one per session, regenerated on login/logout.
if (empty($_SESSION['csrf_token'])) {
  $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

/**
 * Returns the CSRF token for the current session.
 *
 * @return string
 *   64-character hex CSRF token stored in $_SESSION.
 */
function csrf_token(): string {
  return $_SESSION['csrf_token'];
}

/**
 * Verifies the CSRF token submitted with a POST request.
 *
 * Compares the submitted csrf_token field against the session token using a
 * timing-safe comparison. Terminates with HTTP 403 on mismatch.
 *
 * @return void
 */
function csrf_verify(): void {
  $token = $_POST['csrf_token'] ?? '';
  if (!hash_equals($_SESSION['csrf_token'] ?? '', $token)) {
    http_response_code(403);
    exit('Invalid CSRF token.');
  }
}

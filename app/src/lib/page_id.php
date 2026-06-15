<?php
// Emits monitoring HTTP headers on every response.
// Call set_monitoring_headers() once per request before any output.

/**
 * Sets the X-Page-ID response header.
 *
 * Sanitises each component to uppercase alphanumeric characters before
 * emitting the header in MODULE-ACTION-TARGET format.
 *
 * @param string $module
 *   Logical module name (e.g. 'SHOP', 'AUTH').
 * @param string $action
 *   Action being performed (e.g. 'LIST', 'VIEW').
 * @param string $target
 *   Target of the action (e.g. brand slug, order ID). Defaults to 'none'.
 *
 * @return void
 */
function set_page_id(string $module, string $action, string $target = 'none'): void {
  $module = strtoupper(preg_replace('/[^a-zA-Z0-9]/', '', $module));
  $action = strtoupper(preg_replace('/[^a-zA-Z0-9]/', '', $action));
  $target = strtoupper(preg_replace('/[^a-zA-Z0-9]/', '', $target));
  header("X-Page-ID: {$module}-{$action}-{$target}");
}

/**
 * Sets all DX O2 monitoring response headers for the current request.
 *
 * Emits X-Page-ID, X-User-Role, X-Basket-Total, and optionally X-Alert and
 * X-Use-Case. All values are sanitised to prevent header injection.
 *
 * @param string $module
 *   Logical module name for X-Page-ID.
 * @param string $action
 *   Action name for X-Page-ID.
 * @param string $target
 *   Target identifier for X-Page-ID.
 * @param string $role
 *   Authenticated role string ('anonymous', 'user', 'admin'). Defaults to
 *   'anonymous'.
 * @param float $basketTotal
 *   Current basket total in EUR. Defaults to 0.0.
 * @param string $alert
 *   Optional alert key (e.g. 'LOGIN_FAILED'). Omitted when empty.
 * @param string $usecase
 *   Active use case name. Omitted when empty.
 *
 * @return void
 */
function set_monitoring_headers(
  string $module,
  string $action,
  string $target,
  string $role        = 'anonymous',
  float  $basketTotal = 0.0,
  string $alert       = '',
  string $usecase     = ''
): void {
  set_page_id($module, $action, $target);
  header('X-User-Role: ' . preg_replace('/[^\w\-]/', '', $role));
  header('X-Basket-Total: ' . number_format($basketTotal, 2, '.', ''));
  if ($alert !== '') {
    header('X-Alert: ' . preg_replace('/[\r\n]/', ' ', $alert));
  }
  if ($usecase !== '') {
    header('X-Use-Case: ' . preg_replace('/[^\w\-]/', '', $usecase));
  }
}

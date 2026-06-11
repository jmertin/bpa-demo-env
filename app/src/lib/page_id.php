<?php
// Emits monitoring HTTP headers on every response.
// Call set_page_id() once per request before any output.

function set_page_id(string $module, string $action, string $target = 'none'): void
{
    $module = strtoupper(preg_replace('/[^a-zA-Z0-9]/', '', $module));
    $action = strtoupper(preg_replace('/[^a-zA-Z0-9]/', '', $action));
    $target = strtoupper(preg_replace('/[^a-zA-Z0-9]/', '', $target));
    header("X-Page-ID: {$module}-{$action}-{$target}");
}

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

<?php
// Per-page wrapper for "mp" (metric-path) routing -- see lib/routing.php
// and CLAUDE.md's "Front controller" section. Only reachable when
// vhost.conf's mp rewrite rule is active (APP_TYPE=mp); harmless and
// unreferenced by any internal link when APP_TYPE=plain.
// The non-include opcode below (as opposed to a bare `require`) is load
// -bearing: it forces the PHP probe to establish "Frontend start" at this
// file, and vhost.conf's mp rewrite rule points SCRIPT_NAME at this file
// rather than at index.php, satisfying both of the probe's independent
// browser-agent-injection gates (see bug_php_probe.md).
$_GET['page'] ??= basename(__FILE__, '.php');
require __DIR__ . '/index.php';

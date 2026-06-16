#!/usr/bin/env bash
# entrypoint.sh – NGINX container with optional BPA WebServer Plugin injection.
# Injection is opportunistic: NGINX starts with or without the BPA module
# depending on whether the dx-o2-agents APMIA volume is mounted.
set -euo pipefail

APMIA_HOME="${APMIA_HOME:-/opt/apmia}"
BPA_MODULE_DIR="${APMIA_HOME}/extensions/WebServerPlugin"
BPA_MODULE="${BPA_MODULE_DIR}/ngx_http_ca_plugin_filter_module.so"
BPA_MODULE_CONF="/etc/nginx/modules-enabled/bpa.conf"
# IPC address where the BPA plugin reaches the BTL in the dx-o2-agent sidecar.
# Default port 8000 matches the BTL's default from the DX O2 installer.
APMIA_BTL_HOST="${APMIA_BTL_HOST:-127.0.0.1}"
APMIA_BTL_PORT="${APMIA_BTL_PORT:-8000}"

# ── BPA WebServer Plugin Injection ────────────────────────────────────────────
# Checks for the Broadcom BPA shared module in the agent volume mounted at
# APMIA_HOME.  Expected file (placed there by dx-o2-agents at build time):
#   ${BPA_MODULE_DIR}/ngx_http_ca_plugin_filter_module.so
#
# A load_module directive is written to /etc/nginx/modules-enabled/bpa.conf.
# This file is included by the top-level include directive in nginx.conf
# before the events {} block, which is the only valid position for
# load_module in NGINX (dynamic modules must be declared at the top level).
if [[ -f "${BPA_MODULE}" ]]; then
    echo "[entrypoint] Injecting BPA WebServer Plugin from ${BPA_MODULE}"

    # Write the load_module drop-in; nginx.conf includes modules-enabled/*.conf
    echo "load_module ${BPA_MODULE};" > "${BPA_MODULE_CONF}"
    echo "[entrypoint]   Wrote ${BPA_MODULE_CONF}"

    # The BPA plugin package from the DX O2 interface ships only the .so module;
    # there is no separate webserver_plugin.ini.  The plugin communicates with
    # the BTL via its own internal defaults; APMIA_BTL_HOST/PORT are logged for
    # observability and will be used if future plugin versions expose ini config.
    echo "[entrypoint]   BPA → BTL: ${APMIA_BTL_HOST}:${APMIA_BTL_PORT}"

    echo "[entrypoint] BPA WebServer Plugin active – BPA instrumentation enabled."
else
    echo "[entrypoint] BPA module not found at ${BPA_MODULE}."
    echo "[entrypoint] Starting without BPA instrumentation (no module loaded)."
    # Ensure no stale bpa.conf exists from a previous container lifecycle.
    rm -f "${BPA_MODULE_CONF}"
fi

# ── Start cron for daily security updates ─────────────────────────────────────
service cron start

# ── Validate nginx configuration ─────────────────────────────────────────────
nginx -t

# ── Forward logs to container stdout/stderr ───────────────────────────────────
ln -sf /proc/self/fd/1 /var/log/nginx/access.log
ln -sf /proc/self/fd/2 /var/log/nginx/error.log

# ── Launch NGINX ──────────────────────────────────────────────────────────────
exec nginx -g 'daemon off;'

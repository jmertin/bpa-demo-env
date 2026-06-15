#!/usr/bin/env bash
# entrypoint.sh – NGINX container with optional BPA WebServer Plugin injection.
# Injection is opportunistic: NGINX starts with or without the BPA module
# depending on whether the dx-o2-agents APMIA volume is mounted.
set -euo pipefail

APMIA_HOME="${APMIA_HOME:-/opt/apmia}"
BPA_MODULE_DIR="${APMIA_HOME}/extensions/WebServerPlugin"
BPA_MODULE="${BPA_MODULE_DIR}/ngx_http_ca_plugin_filter_module.so"
BPA_MODULE_CONF="/etc/nginx/modules-enabled/bpa.conf"

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

    # Copy the BPA plugin configuration file if the package provides one.
    BPA_PLUGIN_INI="${BPA_MODULE_DIR}/webserver_plugin.ini"
    if [[ -f "${BPA_PLUGIN_INI}" ]]; then
        cp "${BPA_PLUGIN_INI}" /etc/nginx/bpa_plugin.ini
        echo "[entrypoint]   Copied BPA plugin config → /etc/nginx/bpa_plugin.ini"
    fi

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

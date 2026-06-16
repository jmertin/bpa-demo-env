#!/usr/bin/env bash
# entrypoint.sh – NGINX container with optional BPA WebServer Plugin injection.
# Injection is opportunistic: NGINX starts with or without the BPA module
# depending on whether the dx-o2-agents APMIA volume is mounted.
set -euo pipefail

APMIA_HOME="${APMIA_HOME:-/opt/apmia}"
BPA_MODULE_DIR="${APMIA_HOME}/extensions/WebServerPlugin"
BPA_MODULE_CONF="/etc/nginx/modules-enabled/bpa.conf"
# IPC address where the BPA plugin reaches the BTL in the dx-o2-agent sidecar.
# Default port 8000 matches the BTL's default from the DX O2 installer.
APMIA_BTL_HOST="${APMIA_BTL_HOST:-127.0.0.1}"
APMIA_BTL_PORT="${APMIA_BTL_PORT:-8000}"

# ── BPA WebServer Plugin Injection ────────────────────────────────────────────
# Plugin .so files in the agent volume are named with their target nginx version
# (e.g. ngx_http_ca_plugin_filter_module_1.18.0.so).  We detect the running
# nginx version and select the matching file.  A load_module directive is then
# written to /etc/nginx/modules-enabled/bpa.conf (included at top-level scope
# before events {} in nginx.conf — the only valid position for load_module).
# If nginx -t rejects the module (version mismatch), bpa.conf is removed and
# nginx starts cleanly without BPA rather than crashing the container.

NGINX_VER=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
BPA_MODULE=""

if [[ -d "${BPA_MODULE_DIR}" ]]; then
    # Prefer exact version match.
    candidate="${BPA_MODULE_DIR}/ngx_http_ca_plugin_filter_module_${NGINX_VER}.so"
    if [[ -f "${candidate}" ]]; then
        BPA_MODULE="${candidate}"
    else
        # Fall back to any available variant as a last resort.
        BPA_MODULE=$(ls "${BPA_MODULE_DIR}"/ngx_http_ca_plugin_filter_module_*.so 2>/dev/null | head -1 || true)
    fi
fi

if [[ -n "${BPA_MODULE}" ]]; then
    echo "[entrypoint] Injecting BPA WebServer Plugin (nginx ${NGINX_VER}): $(basename "${BPA_MODULE}")"
    echo "load_module ${BPA_MODULE};" > "${BPA_MODULE_CONF}"
    echo "[entrypoint]   Wrote ${BPA_MODULE_CONF}"
    echo "[entrypoint]   BPA → BTL: ${APMIA_BTL_HOST}:${APMIA_BTL_PORT}"

    # Validate before committing – version mismatch produces a hard nginx error.
    if nginx -t 2>/dev/null; then
        echo "[entrypoint] BPA WebServer Plugin active – BPA instrumentation enabled."
    else
        echo "[entrypoint] WARNING: nginx -t rejected the BPA module (version mismatch)." >&2
        echo "[entrypoint]   nginx version   : ${NGINX_VER}" >&2
        echo "[entrypoint]   Module selected : $(basename "${BPA_MODULE}")" >&2
        echo "[entrypoint]   Available variants:" >&2
        ls "${BPA_MODULE_DIR}"/ngx_http_ca_plugin_filter_module_*.so 2>/dev/null \
            | sed 's/^/[entrypoint]     /' >&2 || true
        echo "[entrypoint] Rebuild dx-o2-agents with the nginx ${NGINX_VER} BPA plugin." >&2
        echo "[entrypoint] Disabling BPA module – starting nginx without BPA instrumentation." >&2
        rm -f "${BPA_MODULE_CONF}"
    fi
else
    echo "[entrypoint] BPA module not found in ${BPA_MODULE_DIR}."
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

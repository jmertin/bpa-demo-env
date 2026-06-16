#!/usr/bin/env bash
# entrypoint.sh – PHP-FPM container with optional DX O2 PHP probe injection.
# Injection is opportunistic: the container starts cleanly whether or not the
# APMIA agent volume is mounted, so the application image itself has no
# compile-time dependency on the Broadcom binaries.
set -euo pipefail

APMIA_HOME="${APMIA_HOME:-/opt/apmia}"
PHP_PROBE_DIR="${APMIA_HOME}/extensions/PHPAgent"
# IPC address where the PHP probe reaches the Infrastructure Agent (same pod).
APMIA_PHP_COLLECTOR_HOST="${APMIA_PHP_COLLECTOR_HOST:-127.0.0.1}"
APMIA_PHP_COLLECTOR_PORT="${APMIA_PHP_COLLECTOR_PORT:-55512}"
PHP_VERSION="8.1"
PHP_CONF_D="/etc/php/${PHP_VERSION}/fpm/conf.d"
PHP_MODS_AVAIL="/etc/php/${PHP_VERSION}/mods-available"

# ── DX O2 PHP Probe Injection ──────────────────────────────────────────────────
# Checks for the Broadcom PHP probe in the agent volume mounted at APMIA_HOME.
# Expected files (placed there by the dx-o2-agents container at build time):
#   ${PHP_PROBE_DIR}/wily_php_agent.so   – PHP extension shared library
#   ${PHP_PROBE_DIR}/wily_php_agent.ini  – PHP INI snippet enabling the probe
if [[ -f "${PHP_PROBE_DIR}/wily_php_agent.ini" ]]; then
    echo "[entrypoint] Injecting DX O2 PHP probe from ${PHP_PROBE_DIR}"

    # Copy the extension shared library into PHP's extension directory.
    PHP_EXT_DIR=$(php8.1 -r 'echo ini_get("extension_dir");')
    if [[ -f "${PHP_PROBE_DIR}/wily_php_agent.so" ]]; then
        cp "${PHP_PROBE_DIR}/wily_php_agent.so" "${PHP_EXT_DIR}/wily_php_agent.so"
        echo "[entrypoint]   Copied wily_php_agent.so → ${PHP_EXT_DIR}/"
    fi

    # Install the INI snippet into mods-available and enable it for FPM.
    # Using priority 99 ensures the probe loads after all other extensions.
    cp "${PHP_PROBE_DIR}/wily_php_agent.ini" \
       "${PHP_MODS_AVAIL}/wily_php_agent.ini"
    ln -sf "${PHP_MODS_AVAIL}/wily_php_agent.ini" \
           "${PHP_CONF_D}/99-wily_php_agent.ini"
    echo "[entrypoint]   Probe INI installed at ${PHP_CONF_D}/99-wily_php_agent.ini"

    # Patch the Infrastructure Agent IPC endpoint so the probe can reach the
    # dx-o2-agent sidecar.  In Kubernetes, all pod containers share 127.0.0.1.
    # Replace the collectorAddress property if already present; append if absent.
    local collector_line="introscope.agent.php.collectorAddress=${APMIA_PHP_COLLECTOR_HOST}:${APMIA_PHP_COLLECTOR_PORT}"
    if grep -qE '^[[:space:]]*introscope\.agent\.php\.collectorAddress' \
            "${PHP_MODS_AVAIL}/wily_php_agent.ini" 2>/dev/null; then
        sed -i "s|.*introscope\.agent\.php\.collectorAddress=.*|${collector_line}|" \
            "${PHP_MODS_AVAIL}/wily_php_agent.ini"
    else
        printf '\n%s\n' "${collector_line}" >> "${PHP_MODS_AVAIL}/wily_php_agent.ini"
    fi
    echo "[entrypoint]   PHP probe collector: ${APMIA_PHP_COLLECTOR_HOST}:${APMIA_PHP_COLLECTOR_PORT}"

    # Run the agent's own install helper if present (sets up any additional
    # symlinks or registers the probe with php-fpm's configuration).
    INSTALL_HELPER="${PHP_PROBE_DIR}/install.sh"
    if [[ -x "${INSTALL_HELPER}" ]]; then
        echo "[entrypoint]   Running PHP probe install helper..."
        "${INSTALL_HELPER}" --silent 2>/dev/null || true
    fi

    echo "[entrypoint] DX O2 PHP probe active – APM instrumentation enabled."
else
    echo "[entrypoint] DX O2 agent volume not mounted at ${PHP_PROBE_DIR}."
    echo "[entrypoint] Starting without APM instrumentation (no probe injected)."
fi

# ── Start cron for daily security updates ─────────────────────────────────────
service cron start

# ── Launch PHP-FPM ────────────────────────────────────────────────────────────
# -F : keeps the master process in the foreground (required for PID 1).
# -R : permits the master to run as root; workers drop to www-data per www.conf.
exec php-fpm-run -F -R

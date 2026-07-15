#!/usr/bin/env bash
# entrypoint.sh - Apache + mod_php container with optional DX O2 probe injection.
# Injects the PHP probe and the BPA WebServer Plugin (Apache) at container
# startup from the shared APMIA agent volume.  Starts cleanly without either
# if the volume is absent (opportunistic injection pattern).
set -euo pipefail

APMIA_HOME="${APMIA_HOME:-/opt/apmia}"
PHP_PROBE_DIR="${APMIA_HOME}/extensions/PHPAgent"
BPA_MODULE_DIR="${APMIA_HOME}/extensions/WebServerPlugin"

APMIA_PHP_COLLECTOR_HOST="${APMIA_PHP_COLLECTOR_HOST:-127.0.0.1}"
APMIA_PHP_COLLECTOR_PORT="${APMIA_PHP_COLLECTOR_PORT:-5005}"
APMIA_BTL_HOST="${APMIA_BTL_HOST:-127.0.0.1}"
APMIA_BTL_PORT="${APMIA_BTL_PORT:-8000}"
APMIA_APP_NAME="${APMIA_APP_NAME:-bpa-demo}"
# PHP probe identity in the APM metric tree (wily_php_agent.agentName).
APMIA_PHP_AGENT_NAME="${APMIA_PHP_AGENT_NAME:-bpa-demo-php-probe}"
# PHP probe log level. Accepts names (TRACE/DEBUG/INFO/WARN/WARNING/ERROR/FATAL)
# or numeric values (0-5). The entrypoint maps names to numbers; the INI requires
# a numeric value: 0=trace,1=debug,2=info,3=warning,4=error,5=fatal.
APMIA_PHP_LOG_LEVEL="${APMIA_PHP_LOG_LEVEL:-INFO}"
# Web plugin identity - available to the BPA Apache module via process environment.
APMIA_WEB_AGENT_NAME="${APMIA_WEB_AGENT_NAME:-bpa-demo-web-plugin}"
# Browser agent snippet string from the DX O2 tenant (DX O2 Settings -> Manage Mobile/Browser Web Monitoring -> App to Monitor -> Web App).
# When non-empty, the PHP probe automatically injects the snippet into every HTML
# response (wily_php_agent.browseragent.autoInjection).  Leave empty to disable.
APMIA_BROWSER_SNIPPET="${APMIA_BROWSER_SNIPPET:-}"

PHP_VERSION="8.1"
PHP_MODS_AVAIL="/etc/php/${PHP_VERSION}/mods-available"
# mod_php uses the apache2 SAPI conf.d, not the fpm one.
PHP_CONF_D="/etc/php/${PHP_VERSION}/apache2/conf.d"

# == DX O2 PHP Probe Injection =================================================
if [[ -f "${PHP_PROBE_DIR}/wily_php_agent.ini" ]]; then
    echo "[entrypoint] Injecting DX O2 PHP probe from ${PHP_PROBE_DIR}"

    PHP_EXT_DIR=$(php8.1 -r 'echo ini_get("extension_dir");')
    if [[ -f "${PHP_PROBE_DIR}/wily_php_agent.so" ]]; then
        cp "${PHP_PROBE_DIR}/wily_php_agent.so" "${PHP_EXT_DIR}/"
        echo "[entrypoint]   Copied wily_php_agent.so -> ${PHP_EXT_DIR}/"
    fi

    mkdir -p "${PHP_MODS_AVAIL}" "${PHP_CONF_D}"
    cp "${PHP_PROBE_DIR}/wily_php_agent.ini" "${PHP_MODS_AVAIL}/wily_php_agent.ini"
    ln -sf "${PHP_MODS_AVAIL}/wily_php_agent.ini" "${PHP_CONF_D}/99-wily_php_agent.ini"
    echo "[entrypoint]   Probe INI installed at ${PHP_CONF_D}/99-wily_php_agent.ini"

    INI_PATH="${PHP_MODS_AVAIL}/wily_php_agent.ini"
    sed -i "s|^wily_php_agent\.collectorHost=.*|wily_php_agent.collectorHost=\"${APMIA_PHP_COLLECTOR_HOST}\"|" "${INI_PATH}"
    sed -i "s|^wily_php_agent\.collectorPort=.*|wily_php_agent.collectorPort=\"${APMIA_PHP_COLLECTOR_PORT}\"|" "${INI_PATH}"
    sed -i "s|^wily_php_agent\.application\.name=.*|wily_php_agent.application.name=\"${APMIA_APP_NAME}\"|" "${INI_PATH}"
    echo "[entrypoint]   PHP probe IPC: ${APMIA_PHP_COLLECTOR_HOST}:${APMIA_PHP_COLLECTOR_PORT}"

    # == PHP probe logging =====================================================
    # Log directory is /var/log/php-probe, created in the Dockerfile and owned
    # by www-data so Apache's PHP process can write to it without privilege.
    sed -i "s|^wily_php_agent\.logdir=.*|wily_php_agent.logdir=\"/var/log/php-probe\"|" "${INI_PATH}"
    if grep -qE "^wily_php_agent\.disableLogging=" "${INI_PATH}"; then
        sed -i "s|^wily_php_agent\.disableLogging=.*|wily_php_agent.disableLogging=0|" "${INI_PATH}"
    else
        printf '\nwily_php_agent.disableLogging=0\n' >> "${INI_PATH}"
    fi
    # Map string names to numeric values (INI requires 0-5, not string names).
    case "${APMIA_PHP_LOG_LEVEL}" in
        [Tt][Rr][Aa][Cc][Ee]|0)       _php_log_num=0 ;;
        [Dd][Ee][Bb][Uu][Gg]|1)       _php_log_num=1 ;;
        [Ii][Nn][Ff][Oo]|2)           _php_log_num=2 ;;
        [Ww][Aa][Rr][Nn]*|3)          _php_log_num=3 ;;
        [Ee][Rr][Rr][Oo][Rr]|4)       _php_log_num=4 ;;
        [Ff][Aa][Tt][Aa][Ll]|5)       _php_log_num=5 ;;
        *)                             _php_log_num=2 ; APMIA_PHP_LOG_LEVEL='INFO' ;;
    esac
    if grep -qE "^wily_php_agent\.logLevel=" "${INI_PATH}"; then
        sed -i "s|^wily_php_agent\.logLevel=.*|wily_php_agent.logLevel=${_php_log_num}|" "${INI_PATH}"
    else
        printf '\nwily_php_agent.logLevel=%s\n' "${_php_log_num}" >> "${INI_PATH}"
    fi
    echo "[entrypoint]   PHP probe logging: enabled (level=${APMIA_PHP_LOG_LEVEL}/${_php_log_num}, dir=/var/log/php-probe)"

    # Set PHP probe agent name (wily_php_agent.agentName controls the probe's
    # identity in the DX O2 metric tree; add the property if absent in the INI).
    if grep -qE "^wily_php_agent\.agentName=" "${INI_PATH}"; then
        sed -i "s|^wily_php_agent\.agentName=.*|wily_php_agent.agentName=\"${APMIA_PHP_AGENT_NAME}\"|" "${INI_PATH}"
    else
        printf '\nwily_php_agent.agentName="%s"\n' "${APMIA_PHP_AGENT_NAME}" >> "${INI_PATH}"
    fi
    echo "[entrypoint]   PHP probe agent : ${APMIA_PHP_AGENT_NAME}"

    # Set PHP probe hostname (wily_php_agent.hostname overrides OS gethostname()
    # so the probe appears with a recognisable name in the DX O2 metric path
    # instead of the auto-generated pod or container ID).
    if grep -qE "^wily_php_agent\.hostname=" "${INI_PATH}"; then
        sed -i "s|^wily_php_agent\.hostname=.*|wily_php_agent.hostname=\"${APMIA_PHP_AGENT_NAME}\"|" "${INI_PATH}"
    else
        printf '\nwily_php_agent.hostname="%s"\n' "${APMIA_PHP_AGENT_NAME}" >> "${INI_PATH}"
    fi
    echo "[entrypoint]   PHP probe host  : ${APMIA_PHP_AGENT_NAME}"

    # == Browser agent auto-injection ==========================================
    # Three INI properties control snippet injection:
    #   1. wily_php_agent.enable.browseragent.response.decoration=1
    #      Master switch for the browser agent module (same as -enableBrowserAgentSupport
    #      in the official installer).  Without this the module is inactive and
    #      snippet.autoInjection is silently ignored.
    #   2. wily_php_agent.enable.browseragent.snippet.autoInjection=1
    #      Activates automatic JavaScript snippet insertion into HTML responses.
    #   3. wily_php_agent.browseragent.autoInjection.snippetString='<script ...>'
    #      The snippet value from DX O2 (single-quoted; value from APMIA_BROWSER_SNIPPET).
    #
    # maxSearchingLength: bytes the probe scans to find <head>/<body> for injection.
    # CSS is now in app/src/css/app.css (external); layout.php emits </head> at byte 239.
    # Valid range is 100-30000 (probe clamps outside values).  30000 gives 125x headroom.
    if grep -qE "^wily_php_agent\.enable\.browseragent\.autoInjection\.snippet\.maxSearchingLength=" "${INI_PATH}"; then
        sed -i "s|^wily_php_agent\.enable\.browseragent\.autoInjection\.snippet\.maxSearchingLength=.*|wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength=30000|" "${INI_PATH}"
    else
        printf '\nwily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength=30000\n' >> "${INI_PATH}"
    fi
    echo "[entrypoint]   Browser agent scan length: 30000 bytes"
    if [[ -n "${APMIA_BROWSER_SNIPPET}" ]]; then
        # Enable the browser agent module (master switch required by the PHP probe).
        if grep -qE "^wily_php_agent\.enable\.browseragent\.response\.decoration=" "${INI_PATH}"; then
            sed -i "s|^wily_php_agent\.enable\.browseragent\.response\.decoration=.*|wily_php_agent.enable.browseragent.response.decoration=1|" "${INI_PATH}"
        else
            printf '\nwily_php_agent.enable.browseragent.response.decoration=1\n' >> "${INI_PATH}"
        fi
        if grep -qE "^wily_php_agent\.enable\.browseragent\.snippet\.autoInjection=" "${INI_PATH}"; then
            sed -i "s|^wily_php_agent\.enable\.browseragent\.snippet\.autoInjection=.*|wily_php_agent.enable.browseragent.snippet.autoInjection=1|" "${INI_PATH}"
        else
            printf '\nwily_php_agent.enable.browseragent.snippet.autoInjection=1\n' >> "${INI_PATH}"
        fi
        sed -i "/^wily_php_agent\.browseragent\.autoInjection\.snippetString=/d" "${INI_PATH}"
        printf "wily_php_agent.browseragent.autoInjection.snippetString='%s'\n" "${APMIA_BROWSER_SNIPPET}" >> "${INI_PATH}"
        echo "[entrypoint]   Browser agent : auto-injection enabled"
    else
        if grep -qE "^wily_php_agent\.enable\.browseragent\.response\.decoration=" "${INI_PATH}"; then
            sed -i "s|^wily_php_agent\.enable\.browseragent\.response\.decoration=.*|wily_php_agent.enable.browseragent.response.decoration=0|" "${INI_PATH}"
        fi
        if grep -qE "^wily_php_agent\.enable\.browseragent\.snippet\.autoInjection=" "${INI_PATH}"; then
            sed -i "s|^wily_php_agent\.enable\.browseragent\.snippet\.autoInjection=.*|wily_php_agent.enable.browseragent.snippet.autoInjection=0|" "${INI_PATH}"
        fi
        sed -i "/^wily_php_agent\.browseragent\.autoInjection\.snippetString=/d" "${INI_PATH}"
        echo "[entrypoint]   Browser agent : disabled (APMIA_BROWSER_SNIPPET not set)"
    fi
    # Remove legacy enable property regardless of branch.
    sed -i "/^wily_php_agent\.browseragent\.autoInjection\.enabled=/d" "${INI_PATH}"

    echo "[entrypoint] DX O2 PHP probe active - APM instrumentation enabled."
else
    echo "[entrypoint] DX O2 agent volume not mounted - PHP probe skipped."
    echo "[entrypoint] Starting without APM instrumentation."
fi

# == BPA WebServer Plugin Injection (Apache) ===================================
# The BPA Apache module is named mod_<name>.so; the LoadModule directive derives
# the module identifier from the filename: mod_<name>.so -> <name>_module.
# Apache 2.4 auto-includes /etc/apache2/conf-enabled/*.conf (IncludeOptional).

BPA_APACHE_SO=$(find "${BPA_MODULE_DIR}" -maxdepth 1 -name "mod_*.so" 2>/dev/null | head -1 || true)

if [[ -n "${BPA_APACHE_SO}" ]]; then
    MODULE_BASENAME=$(basename "${BPA_APACHE_SO}" .so)
    MODULE_NAME="${MODULE_BASENAME#mod_}_module"

    echo "[entrypoint] Injecting BPA WebServer Plugin (Apache): $(basename "${BPA_APACHE_SO}")"
    echo "[entrypoint]   Module name : ${MODULE_NAME}"
    echo "[entrypoint]   BPA -> BTL  : ${APMIA_BTL_HOST}:${APMIA_BTL_PORT}"

    cat > /etc/apache2/conf-available/bpa.conf <<EOF
# Written at container startup by entrypoint.sh.
LoadModule ${MODULE_NAME} ${BPA_APACHE_SO}

# Expose web plugin identity to the BPA module via the Apache request env.
SetEnv APMIA_WEB_AGENT_NAME ${APMIA_WEB_AGENT_NAME}

# BTL connection: native module directives per Broadcom TechDocs.
# TcpClientHostAndPort tells the BPA module where to forward payload data.
TcpClientHostAndPort ${APMIA_BTL_HOST}:${APMIA_BTL_PORT}
TcpClientWaitTimeForReconnectInSecs 30
EOF
    ln -sf /etc/apache2/conf-available/bpa.conf /etc/apache2/conf-enabled/bpa.conf

    if apache2ctl configtest 2>/dev/null; then
        echo "[entrypoint] BPA WebServer Plugin active - BPA instrumentation enabled."
        echo "[entrypoint]   BTL: ${APMIA_BTL_HOST}:${APMIA_BTL_PORT}"
    else
        echo "[entrypoint] WARNING: Apache rejected BPA module (${MODULE_BASENAME})." >&2
        echo "[entrypoint]   Disabling BPA - starting Apache without BPA instrumentation." >&2
        rm -f /etc/apache2/conf-enabled/bpa.conf /etc/apache2/conf-available/bpa.conf
    fi
else
    echo "[entrypoint] No BPA Apache module (mod_*.so) found in ${BPA_MODULE_DIR}."
    echo "[entrypoint] Starting without BPA instrumentation."
    # Remove any stale bpa.conf from a previous container lifecycle.
    rm -f /etc/apache2/conf-enabled/bpa.conf
fi

# NOTE (2026-07-15): the "UnknownAgent" PHP-probe naming bug previously had two
# timing-based workarounds here in sequence (a PHP-collector TCP-port wait, then
# an Infrastructure-Agent-EM-connection-log wait) -- both removed. Root cause
# turned out not to be a race worth waiting out at all: the IA's remote-agent
# auto-naming assigns the probe's AgentName segment based on whichever of its
# own identities has resolved by the time the probe first registers, and no
# wait deadline can be sized correctly against that. The real fix is in the
# dx-o2-agent container's environment instead -- APMENV_INTROSCOPE_AGENT_
# AGENTAUTONAMINGENABLED=false plus APMENV_INTROSCOPE_REMOTEAGENT_PROBE_AGENT_NAME
# force the probe's identity statically, removing the race instead of timing
# around it. See CLAUDE.md's "PHP probe injection" section and
# helm/php-demo/templates/statefulset.yaml / docker-compose.yml's dxo2 service.

# == Start cron for daily security updates ====================================
service cron start

# == Validate Apache configuration ============================================
apache2ctl configtest

# == Launch Apache =============================================================
# Source Apache envvars so APACHE_RUN_DIR, APACHE_LOG_DIR, etc. are set.
# The envvars file references APACHE_CONFDIR before defining it; temporarily
# suspend nounset (-u) so the source does not abort under set -euo pipefail.
# exec replaces the shell, making Apache PID 1 directly (required for container
# lifecycle signal handling - SIGTERM reaches Apache, not a wrapper shell).
# shellcheck source=/etc/apache2/envvars
set +u
. /etc/apache2/envvars
set -u
exec apache2 -D FOREGROUND

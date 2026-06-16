# ════════════════════════════════════════════════════════════════════════════
# Broadcom DX O2 – Combined Infrastructure Agent + BTL Container
# Base: ubuntu:22.04 (Jammy LTS, glibc 2.35)
#
# Installer prerequisites (build-time) – download from your DX O2 interface:
#
#   PHP_apmia_<date>_v<n>.tar
#     DX O2 → Agents → Infrastructure Agent → Linux
#     Contains the Infrastructure Agent, PHP probe (all PHP versions), and a
#     bundled JRE.  The archive includes a pre-configured IntroscopeAgent.profile
#     with your tenant's EM URL and JWT credential – do NOT overwrite this.
#
#   Business_Transaction_Listener.zip
#     DX O2 → Agents → Business Transaction Listener
#
#   Business_Payload_Analyzer_WebServer_Plugins.zip
#     DX O2 → Agents → Business Payload Analyzer WebServer Plugins
#
# Place all three archives in src/dx-o2-agents/installers/ before running
# build.sh.  The installers/ directory is git-ignored.
#
# Runtime environment variables (optional – EM connection is pre-configured):
#   APMIA_AGENT_NAME    Unique agent name shown in the APM console
#   APMIA_APP_NAME      Application name shown in the APM console
#   APMIA_LOG_LEVEL     Log verbosity (optional, default INFO)
# ════════════════════════════════════════════════════════════════════════════

FROM ubuntu:22.04

# Use bash for all RUN commands (required for [[ ]] and process substitution).
SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV APMIA_HOME=/opt/apmia
ENV BTL_HOME=/opt/btlistener

# Install unzip (needed for BTL and BPA archives).
# The PHP_apmia package includes a bundled JRE – openjdk is not required.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        unzip \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY installers/ /tmp/installers/

# ── Infrastructure Agent + PHP Probe ─────────────────────────────────────────
# Extract PHP_apmia_*.tar directly to /opt.  The archive has a single top-level
# 'apmia/' directory → produces /opt/apmia/ with a pre-configured profile.
RUN set -euo pipefail && \
    APMIA_TAR=$(ls /tmp/installers/PHP_apmia*.tar 2>/dev/null | head -1) && \
    if [[ -z "${APMIA_TAR}" ]]; then \
        echo ""; \
        echo "╔══════════════════════════════════════════════════════════════╗"; \
        echo "║  BUILD ERROR: PHP_apmia*.tar not found.                     ║"; \
        echo "║  Download from your DX O2 interface:                        ║"; \
        echo "║    Agents → Infrastructure Agent → Linux                    ║"; \
        echo "║  and place PHP_apmia_*.tar in:                              ║"; \
        echo "║    src/dx-o2-agents/installers/                             ║"; \
        echo "╚══════════════════════════════════════════════════════════════╝"; \
        echo ""; \
        exit 1; \
    fi && \
    echo "Extracting APMIA from: $(basename "${APMIA_TAR}")" && \
    tar -xf "${APMIA_TAR}" -C /opt && \
    echo "Infrastructure Agent extracted to /opt/apmia"

# ── PHP Probe – normalise to expected extension path ─────────────────────────
# The PHP_apmia archive places the probe under probe/lib/php<ver>/.
# Create extensions/PHPAgent/ so the php-fpm entrypoint uses the same path
# regardless of APMIA release generation.
RUN set -euo pipefail && \
    mkdir -p /opt/apmia/extensions/PHPAgent && \
    cp /opt/apmia/probe/lib/php81/wily_php_agent.so \
       /opt/apmia/extensions/PHPAgent/wily_php_agent.so && \
    cp /opt/apmia/probe/wily_php_agent.ini \
       /opt/apmia/extensions/PHPAgent/wily_php_agent.ini && \
    echo "PHP probe files installed to /opt/apmia/extensions/PHPAgent/"

# ── Business Transaction Listener ─────────────────────────────────────────────
RUN set -euo pipefail && \
    BTL_ZIP=$(ls /tmp/installers/Business_Transaction_Listener.zip 2>/dev/null | head -1) && \
    if [[ -z "${BTL_ZIP}" ]]; then \
        echo ""; \
        echo "╔══════════════════════════════════════════════════════════════╗"; \
        echo "║  BUILD ERROR: Business_Transaction_Listener.zip not found.  ║"; \
        echo "║  Download from your DX O2 interface:                        ║"; \
        echo "║    Agents → Business Transaction Listener                   ║"; \
        echo "║  and place it in src/dx-o2-agents/installers/               ║"; \
        echo "╚══════════════════════════════════════════════════════════════╝"; \
        echo ""; \
        exit 1; \
    fi && \
    echo "Extracting BTL from: $(basename "${BTL_ZIP}")" && \
    unzip -q "${BTL_ZIP}" -d /tmp/btl-extract && \
    BTL_DIR=$(find /tmp/btl-extract -maxdepth 1 -mindepth 1 -type d | head -1) && \
    mv "${BTL_DIR}" /opt/btlistener && \
    rm -rf /tmp/btl-extract && \
    echo "BTL extracted to /opt/btlistener"

# ── BPA WebServer Plugin ──────────────────────────────────────────────────────
# Extract EVERY nginx plugin variant from the BPA zip and store each .so as
# ngx_http_ca_plugin_filter_module_<nginx-ver>.so  (e.g. _1.18.0.so).
# The nginx entrypoint selects the file matching the running nginx version at
# startup, so the image works regardless of which nginx release is in the
# container — no hardcoded version required here.
RUN set -euo pipefail && \
    BPA_ZIP=$(ls /tmp/installers/Business_Payload_Analyzer_WebServer_Plugins.zip 2>/dev/null | head -1) && \
    if [[ -z "${BPA_ZIP}" ]]; then \
        echo "WARNING: Business_Payload_Analyzer_WebServer_Plugins.zip not found – BPA plugin skipped."; \
        exit 0; \
    fi && \
    echo "Extracting BPA plugin from: $(basename "${BPA_ZIP}")" && \
    mkdir -p /opt/apmia/extensions/WebServerPlugin && \
    unzip -q "${BPA_ZIP}" -d /tmp/bpa-extract && \
    FOUND=0 && \
    for plugin_tar in $(find /tmp/bpa-extract -name "nginx-webserver-plugin-*-ngx_*.tar.gz" 2>/dev/null | sort); do \
        ngx_ver=$(basename "${plugin_tar}" | sed 's/.*-ngx_\([0-9.]*\)\.tar\.gz/\1/') && \
        rm -rf /tmp/bpa-ngx && mkdir -p /tmp/bpa-ngx && \
        tar -xzf "${plugin_tar}" -C /tmp/bpa-ngx && \
        so=$(find /tmp/bpa-ngx -name "ngx_http_ca_plugin_filter_module.so" | head -1) && \
        if [[ -n "${so}" ]]; then \
            dest="/opt/apmia/extensions/WebServerPlugin/ngx_http_ca_plugin_filter_module_${ngx_ver}.so" && \
            cp "${so}" "${dest}" && \
            echo "  Installed plugin for nginx ${ngx_ver}: $(basename "${dest}")" && \
            FOUND=$((FOUND + 1)); \
        fi; \
    done && \
    rm -rf /tmp/bpa-extract /tmp/bpa-ngx && \
    if [[ ${FOUND} -eq 0 ]]; then \
        echo "ERROR: No nginx plugin variants found inside BPA zip" >&2; \
        exit 1; \
    fi && \
    echo "BPA WebServer Plugin: ${FOUND} nginx variant(s) installed."

# ── Permissions and runtime directories ──────────────────────────────────────
RUN set -euo pipefail && \
    chmod +x /opt/apmia/bin/APMIAgent.sh \
             /opt/apmia/APMIACtrl.sh \
             /opt/btlistener/bin/BTListener.sh && \
    mkdir -p /opt/apmia/logs && \
    mkdir -p /opt/btlistener/logs 2>/dev/null || true

# Clean up installer archives.
RUN rm -rf /tmp/installers

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# Declare /opt/apmia as a shareable volume.  The dxo2-init initContainer copies
# this tree (including probe .so, BPA .so, and the pre-configured profile) to a
# shared emptyDir so php-fpm and nginx can access agent files at pod startup.
VOLUME ["${APMIA_HOME}"]

ENTRYPOINT ["/entrypoint.sh"]

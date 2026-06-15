# ════════════════════════════════════════════════════════════════════════════
# Broadcom DX O2 – Combined Infrastructure Agent + BTL Container
# Base: ubuntu:22.04 (Jammy LTS, glibc 2.35 – confirmed by Broadcom for APMIA)
#
# Installer prerequisite (build-time):
#   Download the Broadcom Infrastructure Agent tar.gz from the Broadcom
#   Support Portal (support.broadcom.com) and place it in:
#     src/dx-o2-agents/installers/apmia-<version>.tar.gz
#
#   The installer directory is git-ignored (.gitignore).
#   Verify the download checksum against the hash published on the portal
#   before placing the file in this directory.
#
# Shared agent directory:
#   After build, /opt/apmia is declared as a VOLUME.  The PHP-FPM and NGINX
#   containers mount it (read-only) to access probe extension packages at
#   their own container startup without having to embed agent binaries in
#   every application image.
#
# Runtime environment variables (all required unless marked optional):
#   APMIA_EM_HOST       Enterprise Manager hostname or IP
#   APMIA_EM_PORT       Enterprise Manager port (optional, default 5001)
#   APMIA_AGENT_NAME    Unique agent name shown in the APM console
#   APMIA_APP_NAME      Application name shown in the APM console
#   APMIA_LOG_LEVEL     Log verbosity (optional, default INFO)
# ════════════════════════════════════════════════════════════════════════════

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV APMIA_HOME=/opt/apmia

# Install runtime prerequisites.
# openjdk-11-jre-headless: required by the Business Transaction Listener (BTL)
# and any Java-based agent extension (e.g. APM Transaction Discovery).
# ca-certificates: required for TLS connections to the Enterprise Manager.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-11-jre-headless \
        ca-certificates \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ── Install Broadcom Infrastructure Agent ────────────────────────────────────
# The installers/ directory must contain exactly one apmia-*.tar.gz archive
# obtained from the Broadcom Support Portal with an active DX APM licence.
# Build fails explicitly (not silently) when the archive is absent.
COPY installers/ /tmp/installers/

RUN set -e && \
    ARCHIVE=$(ls /tmp/installers/apmia-*.tar.gz 2>/dev/null | head -1) && \
    if [[ -z "${ARCHIVE}" ]]; then \
        echo ""; \
        echo "╔══════════════════════════════════════════════════════════════════╗"; \
        echo "║  BUILD ERROR: No APMIA installer found.                         ║"; \
        echo "║  Download the Infrastructure Agent from Broadcom Support Portal ║"; \
        echo "║  and place apmia-<version>.tar.gz in:                           ║"; \
        echo "║    src/dx-o2-agents/installers/                                 ║"; \
        echo "╚══════════════════════════════════════════════════════════════════╝"; \
        echo ""; \
        exit 1; \
    fi && \
    echo "Installing from: ${ARCHIVE}" && \
    mkdir -p /tmp/apmia-install && \
    tar -xzf "${ARCHIVE}" -C /tmp/apmia-install && \
    INSTALL_SCRIPT=$(find /tmp/apmia-install -maxdepth 4 -name "install.sh" | head -1) && \
    if [[ -z "${INSTALL_SCRIPT}" ]]; then \
        echo "ERROR: install.sh not found inside the extracted archive." >&2; \
        exit 1; \
    fi && \
    chmod +x "${INSTALL_SCRIPT}" && \
    "${INSTALL_SCRIPT}" -i silent -DUSER_INSTALL_DIR="${APMIA_HOME}" && \
    rm -rf /tmp/apmia-install /tmp/installers && \
    echo "Infrastructure Agent installed at: ${APMIA_HOME}"

# Copy the agent profile template.  The entrypoint renders it into
# IntroscopeAgent.profile using environment variables at container startup.
COPY config/IntroscopeAgent.profile.template \
     ${APMIA_HOME}/config/IntroscopeAgent.profile.template

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# Declare /opt/apmia as a shareable volume.  When the PHP-FPM and NGINX pods
# mount this path they gain access to the probe .so and .ini files that their
# entrypoints inject at startup without having to rebuild those images.
VOLUME ["${APMIA_HOME}"]

ENTRYPOINT ["/entrypoint.sh"]

#!/usr/bin/env bash
# entrypoint.sh – Broadcom DX O2 combined agent container
#
# The IntroscopeAgent.profile is pre-configured by the DX O2 installer download
# (contains tenant EM URL and JWT credential).  This entrypoint must NOT modify it.
#
# Agent identity is configured via APMENV_* environment variables – the native
# APMIA Docker container mechanism.  The agent startup script reads APMENV_* vars
# at launch and overrides the corresponding introscope.* properties automatically,
# with no profile patching required.  APMIA_* vars are accepted as a fallback for
# backward compatibility and are promoted to APMENV_* below if not already set.
#
# Requires: all three packages downloaded from the DX O2 interface (not from
# support.broadcom.com).  See DX-O2-AGENT-SETUP.md for download instructions.
set -euo pipefail

APMIA_HOME="${APMIA_HOME:-/opt/apmia}"
BTL_HOME="${BTL_HOME:-/opt/btlistener}"
PROFILE="${APMIA_HOME}/core/config/IntroscopeAgent.profile"
AGENT_SCRIPT="${APMIA_HOME}/bin/APMIAgent.sh"
BTL_SCRIPT="${BTL_HOME}/bin/BTListener.sh"

# Use the JRE bundled in the PHP_apmia archive.
# The BTListener.sh start script checks JAVA_HOME; it must be set before launch.
export JAVA_HOME="${APMIA_HOME}/jre"
export PATH="${JAVA_HOME}/bin:${PATH}"

# ── Agent identity (APMENV_* – native APMIA Docker mechanism) ─────────────────
# APMENV_* vars are set directly in the container environment from
# docker-compose.yml or the Helm deployment.  The APMIA agent startup script reads
# them and overrides the corresponding profile properties without any file patching.
# If only legacy APMIA_* vars are present they are promoted to APMENV_* here.
export APMENV_INTROSCOPE_AGENT_AGENTNAME="${APMENV_INTROSCOPE_AGENT_AGENTNAME:-${APMIA_AGENT_NAME:-bpa-demo-agent}}"
export APMENV_INTROSCOPE_AGENT_APPLICATION_NAME="${APMENV_INTROSCOPE_AGENT_APPLICATION_NAME:-${APMIA_APP_NAME:-bpa-demo}}"
export APMENV_INTROSCOPE_AGENT_HOSTNAME="${APMENV_INTROSCOPE_AGENT_HOSTNAME:-${APMIA_HOST_NAME:-bpa-demo-host}}"
export APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME="${APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME:-${APMIA_PROCESS_NAME:-bpa-demo}}"

# ── Deploy mode ────────────────────────────────────────────────────────────────
# APMIA_DEPLOY=false creates a passive volume: the named volume (apmia_data in
# Compose, apmia-share emptyDir in Kubernetes) is seeded with the agent tree
# from the image but the IA and BTL daemons are NOT started.  Use this when
# the IA is provided externally (existing on-premises agent or separate service).
# Default: true (start the IA and BTL from this container).
APMIA_DEPLOY="${APMIA_DEPLOY:-true}"

if [[ "${APMIA_DEPLOY}" != "true" ]]; then
    echo "[entrypoint] APMIA_DEPLOY=${APMIA_DEPLOY} – passive volume mode."
    echo "[entrypoint] Agent tree available at ${APMIA_HOME}."
    echo "[entrypoint] IA and BTL not started; sleeping to keep volume accessible."
    exec sleep infinity
fi

# ── Verify pre-configured profile ─────────────────────────────────────────────
# The EM connection (URL, credential, transport protocol) is embedded in the
# profile by the DX O2 installer.  This block must never be patched or overwritten.
if [[ ! -f "${PROFILE}" ]]; then
    echo "[entrypoint] ERROR: Pre-configured agent profile not found:" >&2
    echo "[entrypoint]        ${PROFILE}" >&2
    echo "[entrypoint]        Download the agent package from your DX O2 interface" >&2
    echo "[entrypoint]        (Agents → Infrastructure Agent → Linux), not from" >&2
    echo "[entrypoint]        support.broadcom.com. The DX O2 download includes" >&2
    echo "[entrypoint]        a pre-configured IntroscopeAgent.profile." >&2
    exit 1
fi

echo "[entrypoint] Pre-configured agent profile verified: ${PROFILE}"
echo "[entrypoint] Agent identity (APMENV_*):"
echo "[entrypoint]   Agent name    : ${APMENV_INTROSCOPE_AGENT_AGENTNAME}"
echo "[entrypoint]   App name      : ${APMENV_INTROSCOPE_AGENT_APPLICATION_NAME}"
echo "[entrypoint]   Host name     : ${APMENV_INTROSCOPE_AGENT_HOSTNAME}"
echo "[entrypoint]   Process name  : ${APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME}"

# ── Validate agent binary ──────────────────────────────────────────────────────
if [[ ! -x "${AGENT_SCRIPT}" ]]; then
    echo "[entrypoint] ERROR: Agent start script not found: ${AGENT_SCRIPT}" >&2
    exit 1
fi

# ── Signal handler for graceful shutdown ───────────────────────────────────────
AGENT_PID=""
WATCHDOG_PID=""

_shutdown() {
    echo "[entrypoint] Received shutdown signal – stopping agents..."
    [[ -n "${WATCHDOG_PID}" ]] && kill "${WATCHDOG_PID}" 2>/dev/null || true
    [[ -n "${AGENT_PID}"    ]] && kill "${AGENT_PID}"    2>/dev/null || true
    pkill -f 'BTListener' 2>/dev/null || true
    wait 2>/dev/null || true
    echo "[entrypoint] Agents stopped."
    exit 0
}
trap _shutdown TERM INT

# ── Start Infrastructure Agent ─────────────────────────────────────────────────
# 'console' mode runs the Java Service Wrapper in the foreground so container
# logs capture all agent output via the pod's log driver.
echo "[entrypoint] Starting Broadcom Infrastructure Agent (console mode)..."

"${AGENT_SCRIPT}" console &
AGENT_PID=$!
echo "[entrypoint] Infrastructure Agent started (PID ${AGENT_PID})"

# ── BTL helpers ────────────────────────────────────────────────────────────────
# Use pgrep to find the BTL Java process regardless of how BTListener.sh
# launches it (inline exec vs. background daemon pattern).

_btl_is_alive() {
    pgrep -f 'BTListener' >/dev/null 2>&1
}

_start_btl() {
    echo "[entrypoint] Starting Business Transaction Listener..."
    "${BTL_SCRIPT}" &
    echo "[entrypoint] BTL started (PID $!)"
}

# ── Start Business Transaction Listener ───────────────────────────────────────
if [[ ! -x "${BTL_SCRIPT}" ]]; then
    echo "[entrypoint] WARNING: BTL script not found at ${BTL_SCRIPT} – BTL not started."
else
    _start_btl

    # ── BTL watchdog ──────────────────────────────────────────────────────────
    # Runs in the background; every 30 s checks whether a BTListener process is
    # alive (via pgrep) and restarts it if not.
    _btl_watchdog() {
        while true; do
            sleep 30
            if ! _btl_is_alive; then
                echo "[entrypoint] BTL process has exited – restarting..."
                _start_btl
            fi
        done
    }

    _btl_watchdog &
    WATCHDOG_PID=$!
    echo "[entrypoint] BTL watchdog started (PID ${WATCHDOG_PID})"
fi

# ── Wait ───────────────────────────────────────────────────────────────────────
wait "${AGENT_PID}"

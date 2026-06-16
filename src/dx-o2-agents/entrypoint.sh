#!/usr/bin/env bash
# entrypoint.sh – Broadcom DX O2 combined agent container
# Starts the Infrastructure Agent and, when present, the Business Transaction
# Listener (BTL) as a sidecar process.  Handles SIGTERM/SIGINT for graceful
# shutdown so Kubernetes pod termination completes within the grace period.
set -euo pipefail

APMIA_HOME="${APMIA_HOME:-/opt/apmia}"
PROFILE_TEMPLATE="${APMIA_HOME}/config/IntroscopeAgent.profile.template"
PROFILE="${APMIA_HOME}/config/IntroscopeAgent.profile"
AGENT_BIN="${APMIA_HOME}/bin/APMIAgent"
BTL_BIN="${APMIA_HOME}/bin/btl"

# ── Validate required environment variables ────────────────────────────────────
: "${APMIA_EM_HOST:?APMIA_EM_HOST must be set (Enterprise Manager hostname)}"
APMIA_EM_PORT="${APMIA_EM_PORT:-8443}"          # WSS default; 5001=plain-TCP, 5443=SSL/TCP
APMIA_AGENT_NAME="${APMIA_AGENT_NAME:-bpa-demo-agent}"
APMIA_APP_NAME="${APMIA_APP_NAME:-BPA-Demo}"
APMIA_LOG_LEVEL="${APMIA_LOG_LEVEL:-INFO}"

# Same-pod IPC addresses – used in the rendered profile so the PHP probe and
# BPA plugin can reach the IA collector and BTL running in this container.
# In Kubernetes all pod containers share 127.0.0.1.  Override for other topologies.
APMIA_PHP_COLLECTOR_HOST="${APMIA_PHP_COLLECTOR_HOST:-127.0.0.1}"
APMIA_PHP_COLLECTOR_PORT="${APMIA_PHP_COLLECTOR_PORT:-55512}"
APMIA_BTL_HOST="${APMIA_BTL_HOST:-127.0.0.1}"
APMIA_BTL_PORT="${APMIA_BTL_PORT:-9001}"

# ── Render agent profile from template ────────────────────────────────────────
if [[ -f "${PROFILE_TEMPLATE}" ]]; then
    echo "[entrypoint] Rendering agent profile from template..."
    export APMIA_HOME APMIA_EM_HOST APMIA_EM_PORT APMIA_AGENT_NAME \
           APMIA_APP_NAME APMIA_LOG_LEVEL \
           APMIA_PHP_COLLECTOR_HOST APMIA_PHP_COLLECTOR_PORT \
           APMIA_BTL_HOST APMIA_BTL_PORT
    # Use envsubst to replace ${VAR} placeholders in the template.
    # Only expand the variables we export to avoid clobbering properties that
    # contain $ signs for other purposes.
    envsubst '${APMIA_HOME} ${APMIA_EM_HOST} ${APMIA_EM_PORT} \
              ${APMIA_AGENT_NAME} ${APMIA_APP_NAME} ${APMIA_LOG_LEVEL} \
              ${APMIA_PHP_COLLECTOR_HOST} ${APMIA_PHP_COLLECTOR_PORT} \
              ${APMIA_BTL_HOST} ${APMIA_BTL_PORT}' \
        < "${PROFILE_TEMPLATE}" > "${PROFILE}"
    echo "[entrypoint] Agent profile written to ${PROFILE}"
fi

# ── Validate agent binary ──────────────────────────────────────────────────────
if [[ ! -x "${AGENT_BIN}" ]]; then
    echo "[entrypoint] ERROR: Agent binary not found or not executable: ${AGENT_BIN}" >&2
    echo "[entrypoint]        Ensure the APMIA installer completed successfully." >&2
    exit 1
fi

# ── Signal handler for graceful shutdown ───────────────────────────────────────
AGENT_PID=""
BTL_PID=""

_shutdown() {
    echo "[entrypoint] Received shutdown signal – stopping agents..."
    [[ -n "${AGENT_PID}" ]] && kill "${AGENT_PID}" 2>/dev/null || true
    [[ -n "${BTL_PID}"   ]] && kill "${BTL_PID}"   2>/dev/null || true
    wait 2>/dev/null || true
    echo "[entrypoint] Agents stopped."
    exit 0
}
trap _shutdown TERM INT

# ── Start Infrastructure Agent ─────────────────────────────────────────────────
echo "[entrypoint] Starting Broadcom Infrastructure Agent..."
echo "[entrypoint]   EM host  : ${APMIA_EM_HOST}:${APMIA_EM_PORT}"
echo "[entrypoint]   Agent    : ${APMIA_AGENT_NAME}"
echo "[entrypoint]   App      : ${APMIA_APP_NAME}"

"${AGENT_BIN}" &
AGENT_PID=$!
echo "[entrypoint] Infrastructure Agent started (PID ${AGENT_PID})"

# ── Start Business Transaction Listener (if present as a standalone binary) ────
if [[ -x "${BTL_BIN}" ]]; then
    echo "[entrypoint] Starting Business Transaction Listener..."
    "${BTL_BIN}" &
    BTL_PID=$!
    echo "[entrypoint] BTL started (PID ${BTL_PID})"
else
    echo "[entrypoint] BTL binary not found at ${BTL_BIN} – BTL may be embedded in the Infrastructure Agent."
fi

# ── Wait ───────────────────────────────────────────────────────────────────────
# Stay alive until the main agent process exits or a signal is received.
wait "${AGENT_PID}"

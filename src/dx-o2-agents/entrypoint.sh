#!/usr/bin/env bash
# entrypoint.sh – Broadcom DX O2 combined agent container
#
# The IntroscopeAgent.profile is pre-configured by the DX O2 installer download
# (contains tenant EM URL and JWT credential).  This entrypoint must NOT
# overwrite it.  It patches only the deployment-specific fields at runtime,
# then starts the Infrastructure Agent and the Business Transaction Listener.
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

# ── Deployment-specific parameters ────────────────────────────────────────────
# The EM connection (URL, credential, transport protocol) is already embedded
# in IntroscopeAgent.profile by the DX O2 installer.  Only agent identity and
# same-pod IPC settings need runtime values.

# Agent identity – controls how this agent appears in the DX O2 APM console.
# Override any of these via environment variables in docker-compose.yml or
# values.yaml to avoid auto-detected Docker container hostnames appearing in APM.
APMIA_AGENT_NAME="${APMIA_AGENT_NAME:-bpa-demo-agent}"     # agent leaf name
APMIA_APP_NAME="${APMIA_APP_NAME:-bpa-demo}"                # application grouping
APMIA_HOST_NAME="${APMIA_HOST_NAME:-bpa-demo-host}"         # hostname override (prevents container IP/ID)
APMIA_PROCESS_NAME="${APMIA_PROCESS_NAME:-bpa-demo}"        # custom process name in metric path
APMIA_LOG_LEVEL="${APMIA_LOG_LEVEL:-INFO}"

# Same-pod IPC addresses.  PHP probe (apache-php) connects to the IA collector;
# BPA plugin (apache-php) connects to the BTL.  Both reach this container on
# 127.0.0.1 (shared Kubernetes pod network namespace).
APMIA_PHP_COLLECTOR_HOST="${APMIA_PHP_COLLECTOR_HOST:-127.0.0.1}"
APMIA_PHP_COLLECTOR_PORT="${APMIA_PHP_COLLECTOR_PORT:-5005}"
APMIA_BTL_HOST="${APMIA_BTL_HOST:-127.0.0.1}"
APMIA_BTL_PORT="${APMIA_BTL_PORT:-8000}"

# ── Patch pre-configured profile ───────────────────────────────────────────────
# Never touch the agentManager.url / agentManager.credential blocks – they are
# set by the DX O2 installer and must remain intact.
if [[ ! -f "${PROFILE}" ]]; then
    echo "[entrypoint] ERROR: Pre-configured agent profile not found:" >&2
    echo "[entrypoint]        ${PROFILE}" >&2
    echo "[entrypoint]        Download the agent package from your DX O2 interface" >&2
    echo "[entrypoint]        (Agents → Infrastructure Agent → Linux), not from" >&2
    echo "[entrypoint]        support.broadcom.com. The DX O2 download includes" >&2
    echo "[entrypoint]        a pre-configured IntroscopeAgent.profile." >&2
    exit 1
fi

echo "[entrypoint] Using pre-configured agent profile: ${PROFILE}"
echo "[entrypoint]   Agent name    : ${APMIA_AGENT_NAME}"
echo "[entrypoint]   App name      : ${APMIA_APP_NAME}"
echo "[entrypoint]   Host name     : ${APMIA_HOST_NAME}"
echo "[entrypoint]   Process name  : ${APMIA_PROCESS_NAME}"

# Helper: set or append a property in IntroscopeAgent.profile.
# Handles commented-out, present, and absent property lines.
_set_profile_prop() {
    local -r key="$1"
    local -r val="$2"
    if grep -qE "^[#;[:space:]]*${key}=" "${PROFILE}"; then
        sed -i "s|^[#;[:space:]]*${key}=.*|${key}=${val}|" "${PROFILE}"
    else
        printf '\n%s=%s\n' "${key}" "${val}" >> "${PROFILE}"
    fi
}

# Patch agent name (property is present with value 'Agent' in the shipped profile).
sed -i "s|^introscope\.agent\.agentName=.*|introscope.agent.agentName=${APMIA_AGENT_NAME}|" \
    "${PROFILE}"

_set_profile_prop "introscope.agent.application.name" "${APMIA_APP_NAME}"
_set_profile_prop "introscope.agent.hostName"          "${APMIA_HOST_NAME}"
_set_profile_prop "introscope.agent.customProcessName" "${APMIA_PROCESS_NAME}"

echo "[entrypoint] Agent profile patched."

# ── Inject JVM identity flags into wrapper.conf ────────────────────────────────
# The Java Service Wrapper reads wrapper.java.additional.N= entries for JVM -D
# properties.  These override profile properties and are the canonical way to
# set agent identity from the documentation:
#   -Dintroscope.agent.customProcessName
#   -Dcom.wily.introscope.agent.agentName
#   -Dintroscope.agent.application.name
#   -Dintroscope.agent.hostName
WRAPPER_CONF=$(find "${APMIA_HOME}" -name "wrapper.conf" 2>/dev/null | head -1 || true)

if [[ -n "${WRAPPER_CONF}" ]]; then
    echo "[entrypoint] Injecting JVM identity args into: ${WRAPPER_CONF}"

    # Find the highest existing additional index to avoid collisions.
    JVM_IDX=$(grep -oE 'wrapper\.java\.additional\.[0-9]+' "${WRAPPER_CONF}" | \
              grep -oE '[0-9]+$' | sort -n | tail -1 2>/dev/null || echo 0)

    _add_jvm_arg() {
        JVM_IDX=$((JVM_IDX + 1))
        printf 'wrapper.java.additional.%d=-D%s=%s\n' "${JVM_IDX}" "$1" "$2" \
            >> "${WRAPPER_CONF}"
        echo "[entrypoint]   -D$1=$2"
    }

    _add_jvm_arg "introscope.agent.hostName"          "${APMIA_HOST_NAME}"
    _add_jvm_arg "introscope.agent.customProcessName" "${APMIA_PROCESS_NAME}"
    _add_jvm_arg "com.wily.introscope.agent.agentName" "${APMIA_AGENT_NAME}"
    _add_jvm_arg "introscope.agent.application.name"  "${APMIA_APP_NAME}"
else
    echo "[entrypoint] wrapper.conf not found – identity set via profile only."
fi

# ── Validate agent binary ──────────────────────────────────────────────────────
if [[ ! -x "${AGENT_SCRIPT}" ]]; then
    echo "[entrypoint] ERROR: Agent start script not found: ${AGENT_SCRIPT}" >&2
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
# 'console' mode runs the Java Service Wrapper in the foreground so container
# logs capture all agent output via the pod's log driver.
echo "[entrypoint] Starting Broadcom Infrastructure Agent (console mode)..."
echo "[entrypoint]   Agent   : ${APMIA_AGENT_NAME}"
echo "[entrypoint]   App     : ${APMIA_APP_NAME}"
echo "[entrypoint]   Host    : ${APMIA_HOST_NAME}"
echo "[entrypoint]   Process : ${APMIA_PROCESS_NAME}"

"${AGENT_SCRIPT}" console &
AGENT_PID=$!
echo "[entrypoint] Infrastructure Agent started (PID ${AGENT_PID})"

# ── Start Business Transaction Listener ───────────────────────────────────────
if [[ -x "${BTL_SCRIPT}" ]]; then
    echo "[entrypoint] Starting Business Transaction Listener..."
    "${BTL_SCRIPT}" &
    BTL_PID=$!
    echo "[entrypoint] BTL started (PID ${BTL_PID})"
else
    echo "[entrypoint] BTL script not found at ${BTL_SCRIPT} – BTL not started."
fi

# ── Wait ───────────────────────────────────────────────────────────────────────
wait "${AGENT_PID}"

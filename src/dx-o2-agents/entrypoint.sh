#!/usr/bin/env bash
# entrypoint.sh - Broadcom DX O2 combined agent container
#
# The IntroscopeAgent.profile is pre-configured by the DX O2 installer download
# (contains tenant EM URL and JWT credential).  This entrypoint must NOT modify it.
#
# Agent identity is configured via APMENV_* environment variables - the native
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

# == Agent identity (APMENV_* - native APMIA Docker mechanism) =================
# APMENV_* vars are set directly in the container environment from
# docker-compose.yml or the Helm deployment.  The APMIA agent startup script reads
# them and overrides the corresponding profile properties without any file patching.
# If only legacy APMIA_* vars are present they are promoted to APMENV_* here.
export APMENV_INTROSCOPE_AGENT_AGENTNAME="${APMENV_INTROSCOPE_AGENT_AGENTNAME:-${APMIA_AGENT_NAME:-bpa-demo-agent}}"
export APMENV_INTROSCOPE_AGENT_APPLICATION_NAME="${APMENV_INTROSCOPE_AGENT_APPLICATION_NAME:-${APMIA_APP_NAME:-bpa-demo}}"
export APMENV_INTROSCOPE_AGENT_HOSTNAME="${APMENV_INTROSCOPE_AGENT_HOSTNAME:-${APMIA_HOST_NAME:-bpa-demo-host}}"
export APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME="${APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME:-${APMIA_PROCESS_NAME:-bpa-demo}}"

# == Deploy mode ===============================================================
# APMIA_DEPLOY=false creates a passive volume: the named volume (apmia_data in
# Compose, apmia-share emptyDir in Kubernetes) is seeded with the agent tree
# from the image but the IA and BTL daemons are NOT started.  Use this when
# the IA is provided externally (existing on-premises agent or separate service).
# Default: true (start the IA and BTL from this container).
APMIA_DEPLOY="${APMIA_DEPLOY:-true}"

if [[ "${APMIA_DEPLOY}" != "true" ]]; then
    echo "[entrypoint] APMIA_DEPLOY=${APMIA_DEPLOY} - passive volume mode."
    echo "[entrypoint] Agent tree available at ${APMIA_HOME}."
    echo "[entrypoint] IA and BTL not started; sleeping to keep volume accessible."
    exec sleep infinity
fi

# == Verify pre-configured profile ============================================
# The EM connection (URL, credential, transport protocol) is embedded in the
# profile by the DX O2 installer.  This block must never be patched or overwritten.
if [[ ! -f "${PROFILE}" ]]; then
    echo "[entrypoint] ERROR: Pre-configured agent profile not found:" >&2
    echo "[entrypoint]        ${PROFILE}" >&2
    echo "[entrypoint]        Download the agent package from your DX O2 interface" >&2
    echo "[entrypoint]        (Agents -> Infrastructure Agent -> Linux), not from" >&2
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

# == Validate agent binary ====================================================
if [[ ! -x "${AGENT_SCRIPT}" ]]; then
    echo "[entrypoint] ERROR: Agent start script not found: ${AGENT_SCRIPT}" >&2
    exit 1
fi

# == DB Monitor (MySQL/MariaDB) ================================================
# The mysql extension .tar.gz is staged in extensions/deploy/ by the Dockerfile.
# At startup the APMIA auto-deploys any .tar.gz in that directory.  This section
# patches bundle.properties inside the archive (and any already-deployed copy on
# persistent volumes) so the extension connects with the correct credentials.
#
# Connection details come from APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_* vars
# (set via docker-compose.yml or Helm Secret).  MYSQL_MONITOR=false removes the
# extension from deploy/ so the APMIA never loads it.
MYSQL_MONITOR="${MYSQL_MONITOR:-true}"

_db_monitor_setup() {
    local mysql_tar
    mysql_tar=$(find "${APMIA_HOME}/extensions/deploy" -maxdepth 1 \
                     -name 'mysql-*.tar.gz' 2>/dev/null | head -1 || true)

    if [[ -z "${mysql_tar}" ]]; then
        echo "[entrypoint] DB Monitor: mysql extension not staged -- skipping DB monitoring."
        return 0
    fi

    if [[ "${MYSQL_MONITOR}" != "true" ]]; then
        echo "[entrypoint] DB Monitor: MYSQL_MONITOR=${MYSQL_MONITOR} -- removing extension."
        rm -f "${mysql_tar}"
        local ext_dir="${APMIA_HOME}/extensions/$(basename "${mysql_tar}" .tar.gz)"
        rm -rf "${ext_dir}" 2>/dev/null || true
        return 0
    fi

    # Resolve connection details from APMENV_* environment variables.
    local -r _prof="${APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES:-bpadb}"
    local -r _pu="${_prof^^}"
    local _v _db_host _db_port _db_user _db_pass _db_inst _db_ver
    _v="APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_${_pu}_HOSTNAME"
    _db_host="${!_v:-mariadb}"
    _v="APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_${_pu}_PORT"
    _db_port="${!_v:-3306}"
    _v="APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_${_pu}_USERNAME"
    _db_user="${!_v:-}"
    _v="APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_${_pu}_PASSWORD"
    _db_pass="${!_v:-}"
    _v="APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_${_pu}_INSTANCENAME"
    _db_inst="${!_v:-phpapp}"
    _v="APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_${_pu}_VERSION"
    _db_ver="${!_v:-}"

    if [[ -z "${_db_user}" ]]; then
        echo "[entrypoint] WARNING: DB Monitor: no username set (${_pu}_USERNAME unset)" >&2
    fi

    # Patch a bundle.properties file in-place.
    # Renames the original profile entry to _prof and updates all connection properties.
    # Uses @ as sed delimiter -- passwords containing @ are not supported.
    _patch_bundle_props() {
        local -r _bp="$1"
        [[ -f "${_bp}" ]] || return 0

        local _orig
        _orig=$(sed -n 's/^introscope\.agent\.dbmonitor\.mysql\.profiles=//p' "${_bp}" \
                | tr -d '[:space:]' | cut -d, -f1 || true)

        if [[ -n "${_orig}" && "${_orig}" != "${_prof}" ]]; then
            sed -i \
                "s@^introscope\.agent\.dbmonitor\.mysql\.profiles=.*@introscope.agent.dbmonitor.mysql.profiles=${_prof}@" \
                "${_bp}"
            sed -i \
                "s@^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_orig}\.@introscope.agent.dbmonitor.mysql.profiles.${_prof}.@g" \
                "${_bp}"
        fi

        sed -i "s@^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_prof}\.hostName=.*@introscope.agent.dbmonitor.mysql.profiles.${_prof}.hostName=${_db_host}@" "${_bp}"
        sed -i "s@^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_prof}\.port=.*@introscope.agent.dbmonitor.mysql.profiles.${_prof}.port=${_db_port}@" "${_bp}"
        sed -i "s@^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_prof}\.userName=.*@introscope.agent.dbmonitor.mysql.profiles.${_prof}.userName=${_db_user}@" "${_bp}"
        sed -i "s@^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_prof}\.password=.*@introscope.agent.dbmonitor.mysql.profiles.${_prof}.password=${_db_pass}@" "${_bp}"
        sed -i "s@^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_prof}\.instanceName=.*@introscope.agent.dbmonitor.mysql.profiles.${_prof}.instanceName=${_db_inst}@" "${_bp}"

        if [[ -n "${_db_ver}" ]]; then
            if grep -q "^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_prof}\.version=" "${_bp}" 2>/dev/null; then
                sed -i "s@^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_prof}\.version=.*@introscope.agent.dbmonitor.mysql.profiles.${_prof}.version=${_db_ver}@" "${_bp}"
            else
                printf 'introscope.agent.dbmonitor.mysql.profiles.%s.version=%s\n' "${_prof}" "${_db_ver}" >> "${_bp}"
            fi
        else
            sed -i "/^introscope\.agent\.dbmonitor\.mysql\.profiles\.${_prof}\.version=/d" "${_bp}"
        fi
    }

    # 1. Patch the staged .tar.gz so the APMIA gets correct credentials on first deploy.
    local _tmpdir
    _tmpdir=$(mktemp -d)
    tar -xzf "${mysql_tar}" -C "${_tmpdir}"
    _patch_bundle_props "${_tmpdir}/bundle.properties"
    tar -czf "${mysql_tar}" -C "${_tmpdir}" .
    rm -rf "${_tmpdir}"

    # 2. Patch the already-deployed extension directory (survives volume persistence).
    local -r _ext_dir="${APMIA_HOME}/extensions/$(basename "${mysql_tar}" .tar.gz)"
    if [[ -d "${_ext_dir}" ]]; then
        _patch_bundle_props "${_ext_dir}/bundle.properties"
        echo "[entrypoint] DB Monitor: patched deployed extension at $(basename "${_ext_dir}")/"
    fi

    echo "[entrypoint] DB Monitor: enabled (profile=${_prof}, host=${_db_host}:${_db_port}, instance=${_db_inst}, user=${_db_user:-<unset>})"
}

_db_monitor_setup

# == Signal handler for graceful shutdown =====================================
AGENT_PID=""
WATCHDOG_PID=""
IA_TAIL_PID=""
BTL_TAIL_PID=""

_shutdown() {
    echo "[entrypoint] Received shutdown signal - stopping agents..."
    [[ -n "${WATCHDOG_PID}" ]] && kill "${WATCHDOG_PID}" 2>/dev/null || true
    [[ -n "${AGENT_PID}"    ]] && kill "${AGENT_PID}"    2>/dev/null || true
    pkill -f 'BTListener' 2>/dev/null || true
    [[ -n "${IA_TAIL_PID}"  ]] && kill "${IA_TAIL_PID}"  2>/dev/null || true
    [[ -n "${BTL_TAIL_PID}" ]] && kill "${BTL_TAIL_PID}" 2>/dev/null || true
    wait 2>/dev/null || true
    echo "[entrypoint] Agents stopped."
    exit 0
}
trap _shutdown TERM INT

# == Start Infrastructure Agent ===============================================
# 'console' mode runs the Java Service Wrapper in the foreground so container
# logs capture all agent output via the pod's log driver.
echo "[entrypoint] Starting Broadcom Infrastructure Agent (console mode)..."

"${AGENT_SCRIPT}" console &
AGENT_PID=$!
echo "[entrypoint] Infrastructure Agent started (PID ${AGENT_PID})"

# == Helpers ==================================================================
# Use pgrep to find the BTL Java process regardless of whether BTListener.sh
# exec's Java directly or daemonizes it in the background.

_btl_is_alive() {
    pgrep -f 'BTListener' >/dev/null 2>&1
}

_start_btl() {
    echo "[entrypoint] Starting Business Transaction Listener..."
    "${BTL_SCRIPT}" start
    echo "[entrypoint] BTL start command completed."
}

# Wait up to 60 s for a log file to appear, then tail it to stdout forever.
# Called in the background (&) so the entrypoint continues; the resulting
# tail output is captured by kubectl logs / docker compose logs via stdout.
_await_and_tail() {
    local -r logfile="$1"
    local waited=0
    while [[ ! -f "${logfile}" && ${waited} -lt 60 ]]; do
        sleep 2
        waited=$(( waited + 2 ))
    done
    if [[ -f "${logfile}" ]]; then
        exec tail -F "${logfile}"
    else
        echo "[entrypoint] WARNING: log not found after 60 s: ${logfile}" >&2
    fi
}

# == Start Business Transaction Listener ======================================
if [[ ! -x "${BTL_SCRIPT}" ]]; then
    echo "[entrypoint] WARNING: BTL script not found at ${BTL_SCRIPT} - BTL not started."
else
    # == Redirect BTL logs to the shared APMIA volume ==========================
    # /opt/btlistener/logs/ is local to this container; the apache-php container
    # mounts only /opt/apmia (the shared emptyDir/named volume) and cannot read
    # paths outside it.  Replace the BTL log directory with a symlink into the
    # shared volume so BTListener.log is visible to the dxo2 status page.
    mkdir -p "${APMIA_HOME}/logs"
    rm -rf "${BTL_HOME}/logs"
    ln -sf "${APMIA_HOME}/logs" "${BTL_HOME}/logs"
    echo "[entrypoint] BTL logs redirected -> ${APMIA_HOME}/logs/ (shared volume)"

    _start_btl

    # == BTL watchdog =========================================================
    # Runs in the background; every 30 s checks whether a BTListener process is
    # alive (via pgrep) and restarts it if not.
    _btl_watchdog() {
        while true; do
            sleep 30
            if ! _btl_is_alive; then
                echo "[entrypoint] BTL process has exited - restarting..."
                _start_btl
            fi
        done
    }

    _btl_watchdog &
    WATCHDOG_PID=$!
    echo "[entrypoint] BTL watchdog started (PID ${WATCHDOG_PID})"

    _await_and_tail "${APMIA_HOME}/logs/BTListener.log" &
    BTL_TAIL_PID=$!
    echo "[entrypoint] BTL log tailer started (PID ${BTL_TAIL_PID})"
fi

# == Stream IA log to stdout ==================================================
# BTListener.log is tailed inside the BTL block above when BTL is present.
# IntroscopeAgent.log is tailed here unconditionally after the JVM starts.
_await_and_tail "${APMIA_HOME}/logs/IntroscopeAgent.log" &
IA_TAIL_PID=$!
echo "[entrypoint] IA log tailer started (PID ${IA_TAIL_PID})"

# == Wait =====================================================================
wait "${AGENT_PID}"

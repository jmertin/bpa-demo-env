#!/usr/bin/env bash
# deploy.sh – Deploy or upgrade the BPA-Demo Helm release to Kubernetes.
#
# Generates a transient values override file from .config, applies it via
# `helm upgrade --install`, and immediately removes the override so that no
# sensitive values remain on disk after the deployment.
#
# Usage:
#   build-scripts/deploy.sh [--skip-init] [-h|--help]
#
# Options:
#   --skip-init  Skip the post-deploy DB init check (init_users.php).
#   -h, --help   Print this help message and exit.
#
# Prerequisites:
#   docker     Must be installed (used for registry credential validation).
#   helm       Must be installed (v3+).
#   kubectl    Must be installed and pointed at the target cluster.
#   .config    Must exist in the project root (copy from .config.example).
#              Required variables: REGISTRY, REGISTRY_USER, REGISTRY_PASSWORD,
#              IMAGE_PREFIX, IMAGE_TAG, APP_NAMESPACE, APP_HOSTNAME,
#              TLS_CLUSTER_ISSUER, INGRESS_CLASS_NAME, KUBECONFIG,
#              MARIADB_ROOT_PASSWORD, MARIADB_DATABASE, MARIADB_USER,
#              MARIADB_PASSWORD.
#              Optional: HELM_CHART_PATH (defaults to helm/php-demo),
#              APMIA_EM_HOST, APMIA_EM_PORT, APMIA_AGENT_NAME, APMIA_APP_NAME,
#              APMIA_LOG_LEVEL, APMIA_PHP_COLLECTOR_HOST, APMIA_PHP_COLLECTOR_PORT,
#              APMIA_BTL_HOST, APMIA_BTL_PORT.
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ── Functions ──────────────────────────────────────────────────────────────────

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[deploy] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[deploy] ERROR: $*" >&2
    exit 1
}

## Verify required CLI tools are installed and the cluster is reachable.
check_prerequisites() {
    local -r required_tools=("helm" "kubectl")
    local tool
    for tool in "${required_tools[@]}"; do
        command -v "${tool}" >/dev/null 2>&1 || \
            fatal "Required tool not found in PATH: ${tool}"
    done

    kubectl cluster-info >/dev/null 2>&1 || \
        fatal "Cannot reach Kubernetes cluster. Check KUBECONFIG and cluster connectivity."
}

## Load and validate the .config file.
load_config() {
    local -r config_file="${ROOT_DIR}/.config"
    [[ -f "${config_file}" ]] || \
        fatal ".config not found in project root. Copy .config.example to .config."
    # shellcheck source=../.config
    source "${config_file}"

    # Mandatory deployment variables.
    : "${REGISTRY:?REGISTRY must be set in .config}"
    : "${REGISTRY_USER:?REGISTRY_USER must be set in .config}"
    : "${REGISTRY_PASSWORD:?REGISTRY_PASSWORD must be set in .config}"
    : "${IMAGE_PREFIX:?IMAGE_PREFIX must be set in .config}"
    : "${IMAGE_TAG:?IMAGE_TAG must be set in .config}"
    : "${APP_NAMESPACE:?APP_NAMESPACE must be set in .config}"
    : "${APP_HOSTNAME:?APP_HOSTNAME must be set in .config}"
    : "${TLS_CLUSTER_ISSUER:?TLS_CLUSTER_ISSUER must be set in .config}"
    : "${INGRESS_CLASS_NAME:?INGRESS_CLASS_NAME must be set in .config}"
    : "${KUBECONFIG:?KUBECONFIG must be set in .config}"
    : "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD must be set in .config}"
    : "${MARIADB_DATABASE:?MARIADB_DATABASE must be set in .config}"
    : "${MARIADB_USER:?MARIADB_USER must be set in .config}"
    : "${MARIADB_PASSWORD:?MARIADB_PASSWORD must be set in .config}"

    export KUBECONFIG
}

## Resolve the Helm chart path (from .config or project default).
resolve_chart_path() {
    local chart_path="${HELM_CHART_PATH:-${ROOT_DIR}/helm/php-demo}"
    [[ -d "${chart_path}" ]] || \
        fatal "Helm chart directory not found: ${chart_path}"
    printf '%s' "${chart_path}"
}

## Generate the transient values override file.
# Arguments: chart directory, output path.
generate_values() {
    local -r chart_dir="$1"
    local -r out="$2"

    # DX O2 optional variables – default to empty strings when not configured.
    local apmia_em_host="${APMIA_EM_HOST:-}"
    local apmia_em_port="${APMIA_EM_PORT:-8443}"
    local apmia_deploy="${APMIA_DEPLOY:-true}"
    local apmia_agent_name="${APMIA_AGENT_NAME:-bpa-demo-agent}"
    local apmia_app_name="${APMIA_APP_NAME:-bpa-demo}"
    local apmia_host_name="${APMIA_HOST_NAME:-bpa-demo-host}"
    local apmia_process_name="${APMIA_PROCESS_NAME:-bpa-demo}"
    local apmia_php_agent_name="${APMIA_PHP_AGENT_NAME:-bpa-demo-php-probe}"
    local apmia_web_agent_name="${APMIA_WEB_AGENT_NAME:-bpa-demo-web-plugin}"
    # The browser snippet contains double-quotes (HTML src="..." attributes).
    # Embed it as a YAML single-quoted string so those double-quotes are safe.
    # Escape any literal single-quote in the value as '' per YAML spec.
    local apmia_browser_snippet="${APMIA_BROWSER_SNIPPET:-}"
    local apmia_browser_snippet_yaml="${apmia_browser_snippet//\'/\'\'}"
    local apmia_log_level="${APMIA_LOG_LEVEL:-INFO}"
    local apmia_php_collector_host="${APMIA_PHP_COLLECTOR_HOST:-127.0.0.1}"
    local apmia_php_collector_port="${APMIA_PHP_COLLECTOR_PORT:-5005}"
    local apmia_btl_host="${APMIA_BTL_HOST:-127.0.0.1}"
    local apmia_btl_port="${APMIA_BTL_PORT:-8000}"
    local mysql_monitor="${MYSQL_MONITOR:-true}"
    local mariadb_database="${MARIADB_DATABASE:-phpapp}"

    info "Generating transient Helm values override: ${out}"
    cat > "${out}" <<EOF
# Auto-generated from .config by deploy.sh – do NOT commit.
image:
  apachephp:
    repository: ${REGISTRY}/${IMAGE_PREFIX}/apache-php
    tag: "${IMAGE_TAG}"
  dxo2:
    repository: ${REGISTRY}/${IMAGE_PREFIX}/dx-o2-agents
    tag: "${IMAGE_TAG}"

ingress:
  className: "${INGRESS_CLASS_NAME}"
  hosts:
    - host: ${APP_HOSTNAME}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: php-demo-tls
      hosts:
        - ${APP_HOSTNAME}
  annotations:
    cert-manager.io/cluster-issuer: "${TLS_CLUSTER_ISSUER}"

mariadb:
  auth:
    rootPassword: "${MARIADB_ROOT_PASSWORD}"
    database: "${MARIADB_DATABASE}"
    username: "${MARIADB_USER}"
    password: "${MARIADB_PASSWORD}"

imageCredentials:
  registry: "${REGISTRY}"
  username: "${REGISTRY_USER}"
  password: "${REGISTRY_PASSWORD}"

dxo2:
  enabled: $([ -n "${apmia_em_host}" ] && echo "true" || echo "false")
  deploy: "${apmia_deploy}"
  emHost: "${apmia_em_host}"
  emPort: "${apmia_em_port}"
  agentName:   "${apmia_agent_name}"
  appName:     "${apmia_app_name}"
  hostName:    "${apmia_host_name}"
  processName: "${apmia_process_name}"
  phpAgentName: "${apmia_php_agent_name}"
  webAgentName: "${apmia_web_agent_name}"
  browserSnippet: '${apmia_browser_snippet_yaml}'
  logLevel: "${apmia_log_level}"
  phpCollectorHost: "${apmia_php_collector_host}"
  phpCollectorPort: "${apmia_php_collector_port}"
  btlHost: "${apmia_btl_host}"
  btlPort: "${apmia_btl_port}"
  dbMonitor:
    enabled: ${mysql_monitor}
    instanceName: "${mariadb_database}"
EOF
    info "Values file generated."
}

## Ensure the namespace exists before deploying.
# Arguments: namespace name.
ensure_namespace() {
    local -r ns="$1"
    if ! kubectl get namespace "${ns}" >/dev/null 2>&1; then
        info "Namespace '${ns}' not found – creating it."
        kubectl create namespace "${ns}"
    fi
}

## Run the Helm upgrade/install.
# Arguments: chart directory, local values path, namespace.
run_deploy() {
    local -r chart_dir="$1"
    local -r local_values="$2"
    local -r ns="$3"

    info "Deploying Helm release 'php-demo' to namespace '${ns}'..."
    helm upgrade --install php-demo "${chart_dir}" \
        --namespace "${ns}" \
        --values "${chart_dir}/values.yaml" \
        --values "${local_values}" \
        --wait \
        --timeout 5m
    info "Helm release deployed successfully."
}

## Run the DB init check via kubectl exec (optional, non-fatal).
# Arguments: namespace.
post_deploy_init() {
    local -r ns="$1"

    echo ""
    info "Running DB init check (setup/init_users.php)..."
    local pod
    pod=$(kubectl get pods -n "${ns}" \
        -l app.kubernetes.io/name=php-demo \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -n "${pod}" ]]; then
        kubectl exec -n "${ns}" "${pod}" -c apache-php -- \
            php /var/www/html/setup/init_users.php || true
    else
        info "WARNING: php-demo pod not found – skipping init check."
        info "         Run manually: kubectl exec -n ${ns} <pod> -c apache-php -- php /var/www/html/setup/init_users.php"
    fi
}

# ── Argument parsing ───────────────────────────────────────────────────────────
OPT_SKIP_INIT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-init)  OPT_SKIP_INIT=true ;;
        -h|--help)    usage; exit 0       ;;
        *)            fatal "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
done

# ── Main ───────────────────────────────────────────────────────────────────────
load_config
check_prerequisites

readonly HELM_CHART="$(resolve_chart_path)"
readonly LOCAL_VALUES="${HELM_CHART}/values.local.yaml"

echo "=== BPA-Demo Helm deployment ==="
echo "  Release   : php-demo"
echo "  Namespace : ${APP_NAMESPACE}"
echo "  Chart     : ${HELM_CHART}"
echo "  Tag       : ${IMAGE_TAG}"
echo ""

generate_values "${HELM_CHART}" "${LOCAL_VALUES}"
echo ""

ensure_namespace "${APP_NAMESPACE}"
run_deploy "${HELM_CHART}" "${LOCAL_VALUES}" "${APP_NAMESPACE}"

# Always remove the transient override, even on failure.
rm -f "${LOCAL_VALUES}"

echo ""
echo "=== Deployment summary ==="
helm status php-demo --namespace "${APP_NAMESPACE}"

if [[ "${OPT_SKIP_INIT}" == "false" ]]; then
    post_deploy_init "${APP_NAMESPACE}"
fi

#!/usr/bin/env bash
# Wrapper that sources .config and delegates to docker compose.
# Usage: scripts/compose.sh [up -d | down | logs -f | ps | ...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

if [[ ! -f "${ROOT_DIR}/.config" ]]; then
    echo "ERROR: ${ROOT_DIR}/.config not found." >&2
    echo "       Copy .config.example to .config and fill in real values." >&2
    exit 1
fi

# shellcheck source=../.config
source "${ROOT_DIR}/.config"

export REGISTRY
export IMAGE_PREFIX
export IMAGE_TAG
export MARIADB_ROOT_PASSWORD
export MARIADB_DATABASE
export MARIADB_USER
export MARIADB_PASSWORD

cd "${ROOT_DIR}"
exec docker compose "$@"

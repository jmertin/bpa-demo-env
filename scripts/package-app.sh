#!/usr/bin/env bash
# Package the PHP application source into a tar archive that is consumed by
# the php-fpm Docker build.  Must be run before build.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

# shellcheck source=../.config
source "${ROOT_DIR}/.config"

APP_SRC="${ROOT_DIR}/app/src"
ARCHIVE="${ROOT_DIR}/docker/php-fpm/app.tar.gz"

if [[ ! -d "${APP_SRC}" ]]; then
    echo "ERROR: Application source directory not found: ${APP_SRC}" >&2
    exit 1
fi

echo "Packaging application from ${APP_SRC} ..."
tar -czf "${ARCHIVE}" -C "${APP_SRC}" .

echo "Archive created: ${ARCHIVE}"
echo "  Size: $(du -sh "${ARCHIVE}" | cut -f1)"

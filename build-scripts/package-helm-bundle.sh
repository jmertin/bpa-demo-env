#!/usr/bin/env bash
# package-helm-bundle.sh – Package everything needed to deploy BPA-Demo via
# Helm on a different host, when the application images have already been
# built and pushed to the registry (e.g. built and pushed from a bastion
# host that has registry access but no direct cluster access, then deployed
# from a separate host that has kubectl/helm access but not the full repo).
#
# Produces a self-contained tarball containing exactly:
#   - helm/php-demo/            The full Helm chart. Every symlink inside it
#                                (notably files/vhost.conf, which points
#                                outside helm/ at
#                                src/apache-php/config/vhost.conf) is
#                                dereferenced into a real file during
#                                staging. Copying just helm/ from the source
#                                repo without doing this leaves a dangling
#                                symlink on the target host and silently
#                                drops whatever fix vhost.conf carries -- a
#                                real incident this project already hit
#                                once (see CLAUDE.md's Helm chart section
#                                and TOBEDONE.md history).
#   - build-scripts/deploy.sh   The only build-scripts/ file a Helm-only
#                                deploy needs -- it renders values.local.yaml
#                                from .config and runs `helm upgrade
#                                --install`. Its own path resolution
#                                (SCRIPT_DIR/.. as ROOT_DIR, chart at
#                                ROOT_DIR/helm/php-demo) works unmodified as
#                                long as this same sibling layout is
#                                preserved, which is exactly what this
#                                script produces.
#   - .config.example           A template only. The real .config (real
#                                registry/database credentials) is NEVER
#                                read, copied, or otherwise bundled --
#                                except for its IMAGE_TAG value, which is
#                                patched into the bundled .config.example
#                                verbatim (not a secret, and the whole
#                                point of this bundle is to deploy an
#                                already-built, already-pushed image; see
#                                patch_config_example_image_tag()). Without
#                                this, whoever deploys the bundle has no
#                                way to know which b<N> tag was actually
#                                pushed and has to be told out of band --
#                                or worse, guesses wrong and deploys a
#                                stale image.
#   - README.txt                Generated fresh each run with the exact
#                                extract-and-deploy steps for the target
#                                host.
#
# Deliberately excluded, since none of it is needed once the images already
# exist in the registry: application source (app/src/), both Dockerfiles,
# the DX O2 agent installer archives (proprietary, already baked into the
# pushed dx-o2-agents image), and every other build-scripts/ file that
# assumes local Docker access (build.sh, push.sh, compose.sh,
# package-app.sh).
#
# Usage:
#   build-scripts/package-helm-bundle.sh [-o|--output <path>] [-h|--help]
#
# Options:
#   -o, --output <path>  Output tarball path (default:
#                         dist/bpa-demo-helm-bundle-<IMAGE_TAG>.tar.gz --
#                         <IMAGE_TAG> falls back to "untagged" if .config
#                         doesn't exist yet in this checkout).
#   -h, --help            Print this help message and exit.
#
# Prerequisites:
#   tar   Must be installed and in PATH.
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
    echo "[package-helm-bundle] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[package-helm-bundle] ERROR: $*" >&2
    exit 1
}

## Verify required tools and source files are present before doing anything.
check_prerequisites() {
    command -v tar >/dev/null 2>&1 || \
        fatal "Required tool not found in PATH: tar"
    [[ -d "${ROOT_DIR}/helm/php-demo" ]] || \
        fatal "Helm chart directory not found: ${ROOT_DIR}/helm/php-demo"
    [[ -f "${ROOT_DIR}/build-scripts/deploy.sh" ]] || \
        fatal "deploy.sh not found: ${ROOT_DIR}/build-scripts/deploy.sh"
    [[ -f "${ROOT_DIR}/.config.example" ]] || \
        fatal ".config.example not found: ${ROOT_DIR}/.config.example"
}

## Resolve the default output tarball path from .config's IMAGE_TAG when
## .config exists in this checkout; falls back to "untagged" otherwise.
## Never fatal -- this script must still work before .config has been
## created (it never reads anything else from it, and never copies it).
default_output_path() {
    local tag="untagged"
    if [[ -f "${ROOT_DIR}/.config" ]]; then
        # shellcheck disable=SC1091
        tag="$(source "${ROOT_DIR}/.config" 2>/dev/null || true; printf '%s' "${IMAGE_TAG:-untagged}")"
    fi
    printf '%s' "${ROOT_DIR}/dist/bpa-demo-helm-bundle-${tag}.tar.gz"
}

## Patch the bundled .config.example's IMAGE_TAG to match this checkout's
## real .config, if one exists -- so whoever deploys the bundle doesn't
## have to be told out of band (or guess) which b<N> tag was actually
## pushed to the registry. Only IMAGE_TAG is ever read from .config here;
## nothing else, and .config itself is never copied into the bundle (see
## this script's header comment). Prints the tag that was patched in, or
## nothing if .config doesn't exist yet in this checkout -- in which case
## the shipped .config.example placeholder is left untouched, same as
## before this fix existed.
# Arguments: path to the staged .config.example file.
patch_config_example_image_tag() {
    local -r config_example="$1"
    [[ -f "${ROOT_DIR}/.config" ]] || return 0

    local tag
    # shellcheck disable=SC1091
    tag="$(source "${ROOT_DIR}/.config" 2>/dev/null || true; printf '%s' "${IMAGE_TAG:-}")"
    [[ -n "${tag}" ]] || return 0

    sed -i.bak "s/^IMAGE_TAG=.*/IMAGE_TAG=\"${tag}\"/" "${config_example}"
    rm -f "${config_example}.bak"
    printf '%s' "${tag}"
}

## Write the target-host instructions into the staged bundle.
# Arguments: stage directory, the tag patch_config_example_image_tag
#   resolved (empty string if it didn't find one).
write_readme() {
    local -r stage_dir="$1"
    local -r patched_tag="${2:-}"

    local image_tag_note
    if [[ -n "${patched_tag}" ]]; then
        image_tag_note="IMAGE_TAG is already pre-filled below with \"${patched_tag}\" -- the exact tag that was pushed to the registry when this bundle was built. Double-check it still matches what you expect to deploy if you're not sure this is the most recent bundle."
    else
        image_tag_note="IMAGE_TAG is NOT pre-filled -- no .config existed in the checkout this bundle was built from, so you must fill it in yourself with the exact tag that was pushed to the registry."
    fi

    cat > "${stage_dir}/README.txt" <<EOF
BPA-Demo Helm deployment bundle
================================

Assumes the apache-php, dx-o2-agents, and traffic-generator images are
already pushed to your registry (built/pushed separately, e.g. from a
bastion host with registry access). This bundle only deploys the already-
published images -- it contains no application source, no Dockerfiles, and
no DX O2 agent installer archives.

On the target host (needs helm 3.12+ and kubectl 1.28+, pointed at the
target cluster):

  1. cp .config.example .config
  2. Edit .config: fill in REGISTRY/IMAGE_PREFIX, MARIADB_*,
     APP_NAMESPACE, APP_HOSTNAME, TLS_CLUSTER_ISSUER, INGRESS_CLASS_NAME,
     KUBECONFIG, and (optionally) the
     APMIA_*/DEPLOYMENT_NAME/DEPLOYMENT_POSTFIX DX O2 variables. See the
     comments in .config.example for what each one does.

     ${image_tag_note}

  3. build-scripts/deploy.sh

That's it -- deploy.sh renders a transient values.local.yaml from .config,
runs \`helm upgrade --install\`, and deletes the transient file immediately
after. Re-running it later applies whatever changed in .config as an
upgrade to the same release.

Full documentation (not included in this bundle): see the project's
README.md, QUICKSTART.md, and DX-O2-AGENT-SETUP.md.
EOF
}

## Stage the bundle contents into a fresh temporary directory, dereferencing
## every symlink in the Helm chart along the way. Prints the temp directory
## path on stdout; caller must rm -rf it when done.
stage_bundle() {
    local -r stage_dir="$(mktemp -d -t bpa-demo-helm-bundle-XXXXXX)"

    info "Staging Helm chart (dereferencing symlinks)..." >&2
    mkdir -p "${stage_dir}/helm"
    cp -rL "${ROOT_DIR}/helm/php-demo" "${stage_dir}/helm/"

    info "Staging deploy.sh..." >&2
    mkdir -p "${stage_dir}/build-scripts"
    cp "${ROOT_DIR}/build-scripts/deploy.sh" "${stage_dir}/build-scripts/"

    info "Staging .config.example..." >&2
    cp "${ROOT_DIR}/.config.example" "${stage_dir}/"

    local patched_tag
    patched_tag="$(patch_config_example_image_tag "${stage_dir}/.config.example")"
    if [[ -n "${patched_tag}" ]]; then
        info "Pre-filled .config.example's IMAGE_TAG with '${patched_tag}' from this checkout's .config." >&2
    else
        info "No .config found in this checkout -- .config.example ships with its default IMAGE_TAG placeholder; whoever deploys this bundle must fill it in manually." >&2
    fi

    write_readme "${stage_dir}" "${patched_tag}"

    # Verify the vhost.conf symlink was actually dereferenced into a real,
    # non-empty file -- fail loudly here rather than silently ship a bundle
    # with a dangling link, which is exactly the bug this script exists to
    # prevent.
    local -r vhost="${stage_dir}/helm/php-demo/files/vhost.conf"
    [[ -L "${vhost}" ]] && \
        fatal "files/vhost.conf is still a symlink after staging -- 'cp -rL' did not dereference it as expected."
    [[ -s "${vhost}" ]] || \
        fatal "files/vhost.conf is missing or empty after staging -- dereferenced copy failed."

    printf '%s' "${stage_dir}"
}

## Create the tarball from a staged directory.
# Arguments: stage directory, output path.
create_tarball() {
    local -r stage_dir="$1"
    local -r output="$2"

    mkdir -p "$(dirname "${output}")"
    tar -czf "${output}" -C "${stage_dir}" .

    local size
    size=$(du -sh "${output}" | cut -f1)
    info "Bundle created: ${output} (${size})"
}

# ── Argument parsing ───────────────────────────────────────────────────────────
OPT_OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output) OPT_OUTPUT="$2"; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           fatal "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
done

# ── Main ───────────────────────────────────────────────────────────────────────
check_prerequisites

readonly OUTPUT_PATH="${OPT_OUTPUT:-$(default_output_path)}"

STAGE_DIR="$(stage_bundle)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

create_tarball "${STAGE_DIR}" "${OUTPUT_PATH}"

echo ""
info "Contents:"
tar -tzf "${OUTPUT_PATH}" | sed 's/^/  /'
echo ""
info "Copy ${OUTPUT_PATH} to the target host, extract it, and follow the"
info "included README.txt (cp .config.example to .config, fill it in, then"
info "run build-scripts/deploy.sh)."

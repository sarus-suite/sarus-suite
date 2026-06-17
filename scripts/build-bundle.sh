#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

log() {
  printf '[build-bundle] %s\n' "$*"
}

log "running fetch-components.sh"
"${ROOT_DIR}/scripts/fetch-components.sh"
log "running build-podman.sh"
"${ROOT_DIR}/scripts/build-podman.sh"
log "running build-parallax.sh"
"${ROOT_DIR}/scripts/build-parallax.sh"
log "running build-sarusctl.sh"
"${ROOT_DIR}/scripts/build-sarusctl.sh"
log "running build-helpers.sh"
"${ROOT_DIR}/scripts/build-helpers.sh"
log "running assemble-bundle.sh"
"${ROOT_DIR}/scripts/assemble-bundle.sh"
log "running verify-bundle.sh"
"${ROOT_DIR}/scripts/verify-bundle.sh"

tarball="${OUT_DIR}.tar.gz"
rm -f "${tarball}"
COPYFILE_DISABLE=1 tar --no-xattrs --disable-copyfile -C "${OUT_DIR}" -czf "${tarball}" "${BUNDLE_NAME}"

printf 'Bundle ready under %s\n' "${BUNDLE_ROOT}"
printf 'Tarball ready at %s\n' "${tarball}"

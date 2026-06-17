#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

log() {
  printf '[build-bundle] %s\n' "$*"
}

tar_supports_flag() {
  local flag="$1"
  local tmp_dir
  local probe_tar

  tmp_dir="$(mktemp -d)"
  probe_tar="$(mktemp)"
  rm -f "${probe_tar}"

  if tar "${flag}" -cf "${probe_tar}" -C "${tmp_dir}" . >/dev/null 2>&1; then
    rm -rf "${tmp_dir}" "${probe_tar}"
    return 0
  fi

  rm -rf "${tmp_dir}" "${probe_tar}"
  return 1
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
# macOS local builds use these flags/env to avoid AppleDouble files and xattrs;
# GNU tar on Linux CI does not support every flag, so probe before using them.
tar_args=()
for flag in --no-xattrs --disable-copyfile; do
  if tar_supports_flag "${flag}"; then
    tar_args+=("${flag}")
  fi
done

COPYFILE_DISABLE=1 tar "${tar_args[@]}" -C "${OUT_DIR}" -czf "${tarball}" "${BUNDLE_NAME}"

printf 'Bundle ready under %s\n' "${BUNDLE_ROOT}"
printf 'Tarball ready at %s\n' "${tarball}"

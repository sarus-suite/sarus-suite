#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

mkdir -p "${CACHE_DIR}/downloads"
require_cmd tar

case "${PODMAN_MODE}" in
  download-static)
    url="https://github.com/mgoltzsche/podman-static/releases/download/${PODMAN_STATIC_VERSION}/podman-linux-${TARGET_ARCH}.tar.gz"
    tarball="${CACHE_DIR}/downloads/podman-static-${PODMAN_STATIC_VERSION}-${TARGET_ARCH}.tar.gz"
    unpack_dir="${CACHE_DIR}/podman-static-unpack-${PODMAN_STATIC_VERSION}-${TARGET_ARCH}"

    if [ ! -x "${PODMAN_STATIC_PREFIX}/usr/local/bin/podman" ]; then
      rm -rf "${unpack_dir}" "${PODMAN_STATIC_PREFIX}"
      mkdir -p "$(dirname "${tarball}")" "${unpack_dir}" "${PODMAN_STATIC_PREFIX}/usr" "${PODMAN_STATIC_PREFIX}/etc"
      if [ ! -f "${tarball}" ]; then
        if command -v curl >/dev/null 2>&1; then
          curl -fsSL "${url}" -o "${tarball}"
        elif command -v wget >/dev/null 2>&1; then
          wget -q -O "${tarball}" "${url}"
        else
          printf '%s\n' 'error: missing required downloader: curl or wget' >&2
          exit 1
        fi
      fi
      tar -xzf "${tarball}" -C "${unpack_dir}"
      cp -R "${unpack_dir}/podman-linux-${TARGET_ARCH}/usr/." "${PODMAN_STATIC_PREFIX}/usr/"
      cp -R "${unpack_dir}/podman-linux-${TARGET_ARCH}/etc/." "${PODMAN_STATIC_PREFIX}/etc/"
    fi
    ;;
  *)
    printf 'error: unsupported PODMAN_MODE: %s\n' "${PODMAN_MODE}" >&2
    exit 1
    ;;
esac

[ -x "${PODMAN_STATIC_PREFIX}/usr/local/bin/podman" ] || {
  printf 'error: missing podman binary in %s\n' "${PODMAN_STATIC_PREFIX}" >&2
  exit 1
}

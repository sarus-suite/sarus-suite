#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"
HOST_OS="$(uname -s)"

verify_static_elf() {
  local path="$1"

  [ -x "${path}" ] || {
    printf 'error: expected executable: %s\n' "${path}" >&2
    exit 1
  }

  if command -v readelf >/dev/null 2>&1; then
    if readelf -l "${path}" | grep -q 'Requesting program interpreter'; then
      printf 'error: binary is dynamically linked: %s\n' "${path}" >&2
      exit 1
    fi
  fi
}

verify_static_elf "${RUNTIME_BIN_DIR}/podman"
verify_static_elf "${RUNTIME_BIN_DIR}/sarusctl"
verify_static_elf "${RUNTIME_BIN_DIR}/mksquashfs"
verify_static_elf "${RUNTIME_BIN_DIR}/rsync"
verify_static_elf "${RUNTIME_BIN_DIR}/inotifywait"
verify_static_elf "${RUNTIME_BIN_DIR}/squashfuse_ll"
verify_static_elf "${RUNTIME_BIN_DIR}/fuse-overlayfs"
verify_static_elf "${RUNTIME_BIN_DIR}/fusermount3"
verify_static_elf "${RUNTIME_BIN_DIR}/pasta"
verify_static_elf "${RUNTIME_BIN_DIR}/crun"

if [ "${HOST_OS}" = "Linux" ]; then
  [ -u "${RUNTIME_BIN_DIR}/fusermount3" ] || {
    printf 'error: expected setuid bit on %s\n' "${RUNTIME_BIN_DIR}/fusermount3" >&2
    exit 1
  }
fi

[ -x "${RUNTIME_BIN_DIR}/parallax" ]
[ -x "${RUNTIME_BIN_DIR}/sarusctl" ]
[ -x "${RUNTIME_BIN_DIR}/conmon" ]

[ -x "${RUNTIME_BIN_DIR}/parallax-mount-program" ]
[ -x "${RUNTIME_BIN_DIR}/sarus-suite-check" ]
[ -x "${RUNTIME_BIN_DIR}/sarus-suite-shell" ]
[ -f "${RUNTIME_CONTAINERS_ETC_DIR}/containers.conf" ]
[ -f "${RUNTIME_CONTAINERS_ETC_DIR}/storage.conf" ]
[ -f "${RUNTIME_CONTAINERS_ETC_DIR}/registries.conf" ]
[ -f "${RUNTIME_CONTAINERS_MODULES_DIR}/hpc" ]
[ -f "${RUNTIME_PARALLAX_ETC_DIR}/parallax-mount.conf" ]
[ -f "${RUNTIME_SARUS_SUITE_ETC_DIR}/90-sarusctl.conf" ]
[ -f "${BUNDLE_ROOT}/examples/ubuntu.toml" ]
[ -f "${BUNDLE_ROOT}/examples/debian.toml" ]
[ -f "${RUNTIME_MANIFEST}" ]

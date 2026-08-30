#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"
HOST_OS="$(uname -s)"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | sed 's/[[:space:]].*$//'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | sed 's/[[:space:]].*$//'
  else
    printf 'error: sha256sum or shasum is required to verify the seccomp profile\n' >&2
    exit 1
  fi
}

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

verify_glibc_elf() {
  local path="$1"
  local baseline="${2:-2.34}"
  local needed

  [ -x "${path}" ] || {
    printf 'error: expected executable: %s\n' "${path}" >&2
    exit 1
  }
  if ! command -v readelf >/dev/null 2>&1; then
    return 0
  fi
  readelf -l "${path}" | grep -Eq 'Requesting program interpreter: /lib(64)?/ld-linux-(x86-64|aarch64)\.so\.[12]' || {
    printf 'error: Podman is not a glibc-linked ELF: %s\n' "${path}" >&2
    exit 1
  }
  needed="$(readelf -d "${path}" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')"
  while IFS= read -r lib; do
    case "${lib}" in
      libc.so.6|libpthread.so.0|libdl.so.2|librt.so.1|libm.so.6|libresolv.so.2|libutil.so.1|ld-linux-aarch64.so.1|ld-linux-x86-64.so.2) ;;
      '') ;;
      *) printf 'error: unsupported Podman shared dependency: %s\n' "${lib}" >&2; exit 1 ;;
    esac
  done <<< "${needed}"
  max_glibc="$(readelf --version-info "${path}" | sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' | sort -V | tail -n 1)"
  [ -z "${max_glibc}" ] || [ "$(printf '%s\n' "${max_glibc}" "${baseline}" | sort -V | tail -n 1)" = "${baseline}" ] || {
    printf 'error: Podman requires glibc %s, baseline is %s\n' "${max_glibc}" "${baseline}" >&2
    exit 1
  }
}

podman_linkage="$(sed -n 's/^podman_linkage=//p' "${RUNTIME_MANIFEST}" 2>/dev/null || true)"
if [ "${podman_linkage}" = glibc ]; then
  verify_glibc_elf "${RUNTIME_BIN_DIR}/podman" "$(sed -n 's/^podman_glibc_baseline=//p' "${RUNTIME_MANIFEST}")"
else
  verify_static_elf "${RUNTIME_BIN_DIR}/podman"
fi
verify_static_elf "${RUNTIME_BIN_DIR}/crun"
verify_static_elf "${RUNTIME_BIN_DIR}/pasta"
verify_static_elf "${RUNTIME_BIN_DIR}/conmon"
verify_static_elf "${RUNTIME_BIN_DIR}/netavark"
verify_static_elf "${RUNTIME_BIN_DIR}/aardvark-dns"
verify_static_elf "${RUNTIME_BIN_DIR}/catatonit"
if [ -e "${RUNTIME_BIN_DIR}/rootlessport" ]; then
  verify_static_elf "${RUNTIME_BIN_DIR}/rootlessport"
fi
verify_static_elf "${RUNTIME_BIN_DIR}/sarusctl"
verify_static_elf "${RUNTIME_BIN_DIR}/ldcache_hook"
verify_static_elf "${RUNTIME_BIN_DIR}/mps_hook"
verify_static_elf "${RUNTIME_BIN_DIR}/pce_hook"
verify_static_elf "${RUNTIME_BIN_DIR}/pc_injection_hook"
verify_static_elf "${RUNTIME_BIN_DIR}/mkhomedir"
verify_static_elf "${RUNTIME_BIN_DIR}/sethomevar"
verify_static_elf "${RUNTIME_HOOK_BIN_DIR}/ldcache_hook"
verify_static_elf "${RUNTIME_HOOK_BIN_DIR}/mps_hook"
verify_static_elf "${RUNTIME_HOOK_BIN_DIR}/pce_hook"
verify_static_elf "${RUNTIME_HOOK_BIN_DIR}/pc_injection_hook"
verify_static_elf "${RUNTIME_HOOK_BIN_DIR}/mkhomedir"
verify_static_elf "${RUNTIME_HOOK_BIN_DIR}/sethomevar"
verify_static_elf "${RUNTIME_BIN_DIR}/mksquashfs"
verify_static_elf "${RUNTIME_BIN_DIR}/rsync"
verify_static_elf "${RUNTIME_BIN_DIR}/inotifywait"
verify_static_elf "${RUNTIME_BIN_DIR}/squashfuse_ll"
verify_static_elf "${RUNTIME_BIN_DIR}/fuse-overlayfs"
verify_static_elf "${RUNTIME_BIN_DIR}/fusermount3"
verify_static_elf "${RUNTIME_BIN_DIR}/bwrap"

if [ "${HOST_OS}" = "Linux" ]; then
  [ -u "${RUNTIME_BIN_DIR}/fusermount3" ] || {
    printf 'error: expected setuid bit on %s\n' "${RUNTIME_BIN_DIR}/fusermount3" >&2
    exit 1
  }
fi

[ -x "${RUNTIME_BIN_DIR}/parallax" ]
[ -x "${RUNTIME_BIN_DIR}/sarusctl" ]

[ -x "${RUNTIME_BIN_DIR}/parallax-mount-program" ]
[ -x "${RUNTIME_BIN_DIR}/sarus-suite-check" ]
[ -x "${RUNTIME_BIN_DIR}/sarus-suite-shell" ]
[ -x "${RUNTIME_BIN_DIR}/sarus-suite-system-install" ]
[ -d "${RUNTIME_HOOK_BIN_DIR}" ]
[ -f "${RUNTIME_CONTAINERS_ETC_DIR}/containers.conf" ]
[ -f "${RUNTIME_CONTAINERS_ETC_DIR}/storage.conf" ]
[ -f "${RUNTIME_CONTAINERS_ETC_DIR}/registries.conf" ]
[ -f "${RUNTIME_CONTAINERS_ETC_DIR}/policy.json" ]
[ -f "${RUNTIME_CONTAINERS_ETC_DIR}/seccomp.json" ]
[ "$(sha256_file "${RUNTIME_CONTAINERS_ETC_DIR}/seccomp.json")" = "$(sed -n 's/^seccomp_sha256=//p' "${RUNTIME_MANIFEST}")" ] || {
  printf 'error: bundled seccomp profile checksum does not match the manifest\n' >&2
  exit 1
}
grep -Eq '^[[:space:]]*seccomp_profile[[:space:]]*= *".*seccomp\.json"' "${RUNTIME_CONTAINERS_ETC_DIR}/containers.conf"
grep -Eq '^[[:space:]]*seccomp_profile[[:space:]]*= *".*seccomp\.json"' "${BUNDLE_ROOT}/etc/system/containers/containers.conf"
[ -f "${RUNTIME_CONTAINERS_MODULES_DIR}/hpc" ]
[ -d "${RUNTIME_CONTAINERS_HOOKS_DIR}" ]
[ -f "${RUNTIME_CONTAINERS_HOOKS_DIR}/10-ldcache.json" ]
[ -f "${RUNTIME_CONTAINERS_HOOKS_DIR}/20-mps.json" ]
[ -f "${RUNTIME_CONTAINERS_HOOKS_DIR}/30-pce.json" ]
[ -f "${RUNTIME_CONTAINERS_HOOKS_DIR}/40-pc-injection.json" ]
[ -f "${RUNTIME_CONTAINERS_HOOKS_DIR}/50-mkhomedir.json" ]
[ -f "${RUNTIME_CONTAINERS_HOOKS_DIR}/60-sethomevar.json" ]
[ -f "${RUNTIME_PARALLAX_ETC_DIR}/parallax-mount.conf" ]
[ -f "${RUNTIME_SARUS_SUITE_ETC_DIR}/90-sarusctl.conf" ]
[ -f "${BUNDLE_ROOT}/etc/system/containers/containers.conf" ]
[ -f "${BUNDLE_ROOT}/etc/system/containers/storage.conf" ]
[ -f "${BUNDLE_ROOT}/etc/system/parallax-mount.conf" ]
[ -f "${BUNDLE_ROOT}/etc/system/90-sarusctl.conf" ]
[ -f "${BUNDLE_ROOT}/examples/ubuntu.toml" ]
[ -f "${BUNDLE_ROOT}/examples/debian.toml" ]
[ -f "${RUNTIME_MANIFEST}" ]
[ -f "${RUNTIME_LICENSE_DIR}/sarus-suite-LICENSE" ]
"${ROOT_DIR}/scripts/verify-manifest.sh" "${RUNTIME_MANIFEST}"

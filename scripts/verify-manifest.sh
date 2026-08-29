#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-}"

[ -n "${manifest}" ] || {
  printf 'usage: %s MANIFEST\n' "$0" >&2
  exit 2
}
[ -f "${manifest}" ] || {
  printf 'error: manifest does not exist: %s\n' "${manifest}" >&2
  exit 1
}

manifest_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "${manifest}"
}

require_value() {
  local key="$1"
  local value
  value="$(manifest_value "${key}")"
  [ -n "${value}" ] || {
    printf 'error: manifest field is missing or empty: %s\n' "${key}" >&2
    exit 1
  }
  case "${value}" in
    UNKNOWN|unknown)
      printf 'error: manifest field has unresolved provenance: %s=%s\n' "${key}" "${value}" >&2
      exit 1
      ;;
  esac
}

components=(podman conmon netavark aardvark_dns passt crun catatonit)
for component in "${components[@]}"; do
  require_value "${component}_repo"
  require_value "${component}_ref"
  require_value "${component}_version"
  sha="$(manifest_value "${component}_sha")"
  [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || {
    printf 'error: manifest field is not a full Git SHA: %s_sha=%s\n' "${component}" "${sha}" >&2
    exit 1
  }
done

require_value containers_common_ref
podman_linkage="$(manifest_value podman_linkage)"
[[ "${podman_linkage}" =~ ^(static|glibc)$ ]] || {
  printf 'error: invalid Podman linkage: %s\n' "${podman_linkage}" >&2
  exit 1
}
podman_glibc_baseline="$(manifest_value podman_glibc_baseline)"
if [ "${podman_linkage}" = glibc ]; then
  [[ "${podman_glibc_baseline}" =~ ^[0-9]+\.[0-9]+$ ]] || {
    printf 'error: invalid Podman glibc baseline: %s\n' "${podman_glibc_baseline}" >&2
    exit 1
  }
else
  [ "${podman_glibc_baseline}" = none ] || {
    printf 'error: static Podman must not declare a glibc baseline\n' >&2
    exit 1
  }
fi
seccomp_sha256="$(manifest_value seccomp_sha256)"
if [ "${podman_linkage}" = glibc ]; then
  [ "${seccomp_sha256}" = none ] || {
    printf 'error: glibc Podman must not declare a seccomp checksum\n' >&2
    exit 1
  }
else
  [[ "${seccomp_sha256}" =~ ^[0-9a-f]{64}$ ]] || {
    printf 'error: manifest seccomp checksum is invalid: %s\n' "${seccomp_sha256}" >&2
    exit 1
  }
fi

rootlessport_bundled="$(manifest_value rootlessport_bundled)"
[[ "${rootlessport_bundled}" =~ ^(true|false)$ ]] || {
  printf 'error: manifest rootlessport status is invalid: %s\n' "${rootlessport_bundled}" >&2
  exit 1
}

if grep -Eq '^(podman_mode|podman_static_version)=' "${manifest}"; then
  printf 'error: manifest contains obsolete downloaded Podman fields\n' >&2
  exit 1
fi

printf 'manifest provenance verified: %s\n' "${manifest}"

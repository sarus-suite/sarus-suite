#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

PODMAN_MODE="${PODMAN_MODE:-glibc}"

case "${PODMAN_MODE}" in
  static|glibc)
    ;;
  *)
    printf 'error: unsupported PODMAN_MODE=%s (expected static or glibc)\n' "${PODMAN_MODE}" >&2
    exit 2
    ;;
esac

case "${BUILD_CACHE_MODE}" in
  auto|off|required)
    ;;
  *)
    printf 'error: unsupported BUILD_CACHE_MODE=%s (expected auto, off, or required)\n' \
      "${BUILD_CACHE_MODE}" >&2
    exit 2
    ;;
esac

log() {
  printf '[build-podman] %s\n' "$*"
}

append_build_command() {
  local script="$1"
  local quoted_script

  printf -v quoted_script '%q' "./${script}"
  ALPINE_BUILD_COMMAND+=$'\n'"bash ${quoted_script}"
}

rm -rf "${PODMAN_BUILD_PREFIX}"
mkdir -p "${PODMAN_BUILD_PREFIX}"

if [ "${PODMAN_MODE}" = glibc ]; then
  podman_component=podman-glibc
else
  podman_component=podman-static
fi

components=(
  "${podman_component}"
  conmon
  netavark
  aardvark-dns
  passt
  crun
  catatonit
)
cache_misses=()
cache_hits=()

if [ "${BUILD_CACHE_MODE}" = off ]; then
  cache_misses=("${components[@]}")
  log 'build cache disabled'
else
  for component in "${components[@]}"; do
    cache_output_rel=".work/build-cache/consume/${component}-${TARGET_ARCH}"
    cache_output="${ROOT_DIR}/${cache_output_rel}"
    rm -rf "${cache_output}"

    if "${ROOT_DIR}/scripts/build-cache-component.sh" restore \
      "${component}" "${TARGET_ARCH}" "${cache_output_rel}"; then
      cp -R "${cache_output}/restored-root/." "${PODMAN_BUILD_PREFIX}/"
      cache_hits+=("${component}")
    else
      status=$?
      if [ "${status}" -ne 10 ]; then
        printf 'error: refusing invalid build cache for %s\n' "${component}" >&2
        exit "${status}"
      fi
      cache_misses+=("${component}")
    fi
  done
fi

if [ "${#cache_hits[@]}" -gt 0 ]; then
  log "cache hits: ${cache_hits[*]}"
fi
if [ "${#cache_misses[@]}" -gt 0 ]; then
  log "cache misses: ${cache_misses[*]}"
fi

if [ "${BUILD_CACHE_MODE}" = required ] && [ "${#cache_misses[@]}" -gt 0 ]; then
  printf 'error: required build cache entries are unavailable: %s\n' "${cache_misses[*]}" >&2
  exit 1
fi

glibc_podman_missing=0
ALPINE_BUILD_COMMAND=$'set -euo pipefail\nsource ./components.sh\nmkdir -p "${PODMAN_BUILD_PREFIX}"'
alpine_build_count=0

for component in "${cache_misses[@]}"; do
  case "${component}" in
    podman-glibc)
      glibc_podman_missing=1
      ;;
    podman-static)
      append_build_command devcontainer/scripts/build-podman-static.sh
      alpine_build_count=$((alpine_build_count + 1))
      ;;
    conmon)
      append_build_command devcontainer/scripts/build-conmon-static.sh
      alpine_build_count=$((alpine_build_count + 1))
      ;;
    netavark)
      append_build_command devcontainer/scripts/build-netavark-static.sh
      alpine_build_count=$((alpine_build_count + 1))
      ;;
    aardvark-dns)
      append_build_command devcontainer/scripts/build-aardvark-dns-static.sh
      alpine_build_count=$((alpine_build_count + 1))
      ;;
    passt)
      append_build_command devcontainer/scripts/build-passt-static.sh
      alpine_build_count=$((alpine_build_count + 1))
      ;;
    crun)
      append_build_command devcontainer/scripts/build-crun-static.sh
      alpine_build_count=$((alpine_build_count + 1))
      ;;
    catatonit)
      append_build_command devcontainer/scripts/build-catatonit-static.sh
      alpine_build_count=$((alpine_build_count + 1))
      ;;
  esac
done

if [ "${glibc_podman_missing}" -eq 1 ]; then
  glibc_cmd=$(cat <<'BUILD'
set -euo pipefail
source ./components.sh
mkdir -p "${PODMAN_BUILD_PREFIX}"
bash ./devcontainer/scripts/build-podman-glibc.sh
BUILD
  )
  "${ROOT_DIR}/scripts/run-glibc-build.sh" "${glibc_cmd}"
fi

if [ "${alpine_build_count}" -gt 0 ]; then
  "${ROOT_DIR}/scripts/run-alpine-build.sh" "${ALPINE_BUILD_COMMAND}"
fi

required_podman_artifacts=(
  usr/local/bin/podman
  usr/local/bin/crun
  usr/local/bin/pasta
  usr/local/lib/podman/conmon
  usr/local/lib/podman/netavark
  usr/local/lib/podman/aardvark-dns
  usr/local/lib/podman/catatonit
)

for artifact in "${required_podman_artifacts[@]}"; do
  [ -x "${PODMAN_STATIC_PREFIX}/${artifact}" ] || {
    printf 'error: missing required Podman artifact: %s/%s\n' "${PODMAN_STATIC_PREFIX}" "${artifact}" >&2
    exit 1
  }
done

for feature in seccomp selinux apparmor; do
  feature_metadata="${PODMAN_STATIC_PREFIX}/.build-metadata/podman.${feature}"
  [ -s "${feature_metadata}" ] || {
    printf 'error: missing required Podman feature metadata: %s\n' "${feature_metadata}" >&2
    exit 1
  }
  case "$(sed -n '1p' "${feature_metadata}")" in
    enabled|disabled) ;;
    *) printf 'error: invalid Podman feature metadata: %s\n' "${feature_metadata}" >&2; exit 1 ;;
  esac
done

[ "$(sed -n '1p' "${PODMAN_STATIC_PREFIX}/.build-metadata/podman.seccomp")" = enabled ] || {
  printf 'error: Podman was built without required seccomp support\n' >&2
  exit 1
}
[ -s "${PODMAN_STATIC_PREFIX}/etc/containers/seccomp.json" ] || {
  printf 'error: missing required Podman seccomp profile: %s\n' "${PODMAN_STATIC_PREFIX}/etc/containers/seccomp.json" >&2
  exit 1
}

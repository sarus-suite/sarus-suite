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

rm -rf "${PODMAN_BUILD_PREFIX}"
mkdir -p "${PODMAN_BUILD_PREFIX}"

alpine_helpers_cmd=$(cat <<'BUILD'
set -euo pipefail
source ./components.sh
mkdir -p "${PODMAN_BUILD_PREFIX}"

bash ./devcontainer/scripts/build-conmon-static.sh
bash ./devcontainer/scripts/build-netavark-static.sh
bash ./devcontainer/scripts/build-aardvark-dns-static.sh
bash ./devcontainer/scripts/build-passt-static.sh
bash ./devcontainer/scripts/build-crun-static.sh
bash ./devcontainer/scripts/build-catatonit-static.sh
BUILD
)

if [ "${PODMAN_MODE}" = glibc ]; then
  glibc_cmd=$(cat <<'BUILD'
set -euo pipefail
source ./components.sh
mkdir -p "${PODMAN_BUILD_PREFIX}"
bash ./devcontainer/scripts/build-podman-glibc.sh
BUILD
  )
  "${ROOT_DIR}/scripts/run-glibc-build.sh" "${glibc_cmd}"

  # Keep the supporting runtime helpers on the established Alpine/static path.
  "${ROOT_DIR}/scripts/run-alpine-build.sh" "${alpine_helpers_cmd}"
else
  static_cmd=$(cat <<'BUILD'
set -euo pipefail
source ./components.sh
mkdir -p "${PODMAN_BUILD_PREFIX}"
bash ./devcontainer/scripts/build-podman-static.sh
BUILD
  )
  "${ROOT_DIR}/scripts/run-alpine-build.sh" "${static_cmd}
${alpine_helpers_cmd}"
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

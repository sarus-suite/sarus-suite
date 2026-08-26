#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

rm -rf "${PODMAN_BUILD_PREFIX}"
mkdir -p "${PODMAN_BUILD_PREFIX}"

build_cmd=$(cat <<'BUILD'
set -euo pipefail
source ./components.sh
mkdir -p "${PODMAN_BUILD_PREFIX}"

bash ./devcontainer/scripts/build-podman-static.sh
bash ./devcontainer/scripts/build-conmon-static.sh
bash ./devcontainer/scripts/build-netavark-static.sh
bash ./devcontainer/scripts/build-aardvark-dns-static.sh
bash ./devcontainer/scripts/build-passt-static.sh
bash ./devcontainer/scripts/build-crun-static.sh
bash ./devcontainer/scripts/build-catatonit-static.sh
BUILD
)

"${ROOT_DIR}/scripts/run-alpine-build.sh" "${build_cmd}"

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

[ -s "${PODMAN_STATIC_PREFIX}/etc/containers/seccomp.json" ] || {
  printf 'error: missing required Podman seccomp profile: %s\n' "${PODMAN_STATIC_PREFIX}/etc/containers/seccomp.json" >&2
  exit 1
}

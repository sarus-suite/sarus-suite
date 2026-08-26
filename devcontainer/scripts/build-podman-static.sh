#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
# shellcheck source=lib/build-common.sh
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
# shellcheck source=../../components.sh
. "${ROOT_DIR}/components.sh"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/podman"
PREFIX_DIR="${PODMAN_BUILD_PREFIX:-${BUILD_DIR}/podman-static-root}"

build_require_cmd git
build_require_cmd make
build_require_cmd go
build_require_cmd curl

mkdir -p "${PREFIX_DIR}/usr/local/bin" "${PREFIX_DIR}/usr/local/lib/podman" "${PREFIX_DIR}/etc/containers"
build_checkout_tag "${PODMAN_REPO}" "${PODMAN_VERSION}" "${SRC_DIR}"

cd "${SRC_DIR}"

export CGO_ENABLED=1
export GOOS=linux
export GOARCH="${TARGET_ARCH}"
export GOFLAGS="${GOFLAGS:--buildvcs=false -mod=vendor -trimpath}"

make bin/podman \
  BUILDTAGS="${PODMAN_BUILDTAGS}" \
  EXTRA_LDFLAGS="${EXTRA_LDFLAGS:--s -w -extldflags=-static}"

cp bin/podman "${PREFIX_DIR}/usr/local/bin/podman"
chmod 0755 "${PREFIX_DIR}/usr/local/bin/podman"
build_strip_binary "${PREFIX_DIR}/usr/local/bin/podman"
build_verify_static_elf "${PREFIX_DIR}/usr/local/bin/podman"
"${PREFIX_DIR}/usr/local/bin/podman" --help >/dev/null

rootlessport_output="${PREFIX_DIR}/usr/local/lib/podman/rootlessport"
rm -f "${rootlessport_output}"
if [ -d ./cmd/rootlessport ]; then
  if CGO_ENABLED=0 go build -mod=vendor -trimpath -ldflags='-s -w' -o bin/rootlessport ./cmd/rootlessport; then
    cp bin/rootlessport "${PREFIX_DIR}/usr/local/lib/podman/rootlessport"
    chmod 0755 "${PREFIX_DIR}/usr/local/lib/podman/rootlessport"
    build_strip_binary "${PREFIX_DIR}/usr/local/lib/podman/rootlessport"
    build_verify_static_elf "${PREFIX_DIR}/usr/local/lib/podman/rootlessport"
  else
    rm -f "${rootlessport_output}"
    build_log "rootlessport build failed; continuing because it is optional"
  fi
else
  build_log "rootlessport source unavailable; continuing because it is optional"
fi

common_version="$(grep -Eom1 'github.com/containers/common [^ ]+' go.mod | sed 's!github.com/containers/common !!')"
[ -n "${common_version}" ] || build_die "unable to determine containers/common version from Podman go.mod"
curl -fsSL "https://raw.githubusercontent.com/containers/common/${common_version}/pkg/seccomp/seccomp.json" \
  -o "${PREFIX_DIR}/etc/containers/seccomp.json"

build_require_cmd sha256sum
build_record_provenance "${PREFIX_DIR}" podman "${PODMAN_REPO}" "${PODMAN_VERSION}" "${BUILD_CHECKOUT_SHA}"
printf '%s\n' "${common_version}" > "${PREFIX_DIR}/.build-metadata/containers-common.ref"
sha256sum "${PREFIX_DIR}/etc/containers/seccomp.json" | awk '{print $1}' \
  > "${PREFIX_DIR}/.build-metadata/seccomp.sha256"

build_log "published Podman artifacts under ${PREFIX_DIR}"

#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
# shellcheck source=lib/build-common.sh
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
# shellcheck source=../../components.sh
. "${ROOT_DIR}/components.sh"

GLIBC_BASELINE="${PODMAN_GLIBC_BASELINE:-2.28}"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/podman"
PREFIX_DIR="${PODMAN_BUILD_PREFIX:-${BUILD_DIR}/podman-static-root}"

build_require_cmd git
build_require_cmd make
build_require_cmd go
build_require_cmd curl

mkdir -p "${PREFIX_DIR}/usr/local/bin" "${PREFIX_DIR}/usr/local/lib/podman" "${PREFIX_DIR}/etc/containers"
rm -f "${PREFIX_DIR}/etc/containers/seccomp.json"
build_checkout_tag "${PODMAN_REPO}" "${PODMAN_VERSION}" "${SRC_DIR}"

cd "${SRC_DIR}"

export CGO_ENABLED=1
export GOOS=linux
export GOARCH="${TARGET_ARCH}"
export GOFLAGS="${GOFLAGS:--buildvcs=false -mod=vendor -trimpath}"
export PKG_CONFIG_PATH="${PODMAN_PKG_CONFIG_PATH:-/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig}"

# Keep this portability variant focused on glibc/NSS
# seccomp and SELinux integrations are intentionally omitted from the build tags!!!
podman_buildtags="${PODMAN_GLIBC_BUILDTAGS:-containers_image_openpgp btrfs_noversion exclude_graphdriver_btrfs}"
podman_extldflags="${PODMAN_GLIBC_EXTLDFLAGS:--static-libgcc}"
extra_ldflags="${PODMAN_GLIBC_EXTRA_LDFLAGS:--s -w -linkmode=external -extldflags \"${podman_extldflags}\"}"

make bin/podman \
  BUILDTAGS="${podman_buildtags}" \
  EXTRA_LDFLAGS="${extra_ldflags}"

cp bin/podman "${PREFIX_DIR}/usr/local/bin/podman"
chmod 0755 "${PREFIX_DIR}/usr/local/bin/podman"
build_strip_binary "${PREFIX_DIR}/usr/local/bin/podman"
build_verify_glibc_elf "${PREFIX_DIR}/usr/local/bin/podman" "${GLIBC_BASELINE}"
"${PREFIX_DIR}/usr/local/bin/podman" --help >/dev/null

rootlessport_output="${PREFIX_DIR}/usr/local/lib/podman/rootlessport"
rm -f "${rootlessport_output}"
if [ -d ./cmd/rootlessport ]; then
  if CGO_ENABLED=0 go build -mod=vendor -trimpath -ldflags='-s -w' -o bin/rootlessport ./cmd/rootlessport; then
    cp bin/rootlessport "${rootlessport_output}"
    chmod 0755 "${rootlessport_output}"
    build_strip_binary "${rootlessport_output}"
    build_verify_static_elf "${rootlessport_output}"
  else
    rm -f "${rootlessport_output}"
    build_log "rootlessport build failed; continuing because it is optional"
  fi
else
  build_log "rootlessport source unavailable; continuing because it is optional"
fi

build_record_provenance "${PREFIX_DIR}" podman "${PODMAN_REPO}" "${PODMAN_VERSION}" "${BUILD_CHECKOUT_SHA}"
common_version="$(grep -Eom1 'github.com/containers/common [^ ]+' go.mod | sed 's!github.com/containers/common !!')"
[ -n "${common_version}" ] || build_die "unable to determine containers/common version from Podman go.mod"
printf '%s\n' "${common_version}" > "${PREFIX_DIR}/.build-metadata/containers-common.ref"
printf '%s\n' glibc > "${PREFIX_DIR}/.build-metadata/podman.linkage"
printf '%s\n' "${GLIBC_BASELINE}" > "${PREFIX_DIR}/.build-metadata/podman.glibc-baseline"

build_log "published glibc ${GLIBC_BASELINE} Podman artifacts under ${PREFIX_DIR}"

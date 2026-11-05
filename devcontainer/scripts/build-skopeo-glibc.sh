#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
# shellcheck source=lib/build-common.sh
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
# shellcheck source=../../components.sh
. "${ROOT_DIR}/components.sh"

GLIBC_BASELINE="${SKOPEO_GLIBC_BASELINE:-2.34}"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/skopeo"
OUTPUT="${SKOPEO_BIN}"

build_require_cmd git
build_require_cmd make
build_require_cmd go
build_require_cmd gcc
build_require_cmd pkg-config
build_checkout_tag "${SKOPEO_REPO}" "${SKOPEO_VERSION}" "${SRC_DIR}" "${SKOPEO_SHA}"

cd "${SRC_DIR}"

export CGO_ENABLED=1
export GOOS=linux
export GOARCH="${TARGET_ARCH}"
export GOFLAGS="${GOFLAGS:--buildvcs=false -mod=vendor -trimpath}"
export PKG_CONFIG_PATH="${SKOPEO_PKG_CONFIG_PATH:-/usr/local/lib/pkgconfig:/usr/lib/$(gcc -print-multiarch)/pkgconfig}"

# Keep the pure-Go OpenPGP implementation for now: this avoids a runtime GnuPG
# engine dependency while CGO restores glibc NSS and resolver behavior.
skopeo_buildtags="${SKOPEO_GLIBC_BUILDTAGS:-containers_image_openpgp exclude_graphdriver_btrfs}"
skopeo_extldflags="${SKOPEO_GLIBC_EXTLDFLAGS:--static-libgcc}"
extra_ldflags="${SKOPEO_GLIBC_EXTRA_LDFLAGS:--s -w -linkmode=external -extldflags \"${skopeo_extldflags}\"}"

make bin/skopeo \
  BUILDTAGS="${skopeo_buildtags}" \
  EXTRA_LDFLAGS="${extra_ldflags}"

mkdir -p "$(dirname "${OUTPUT}")"
cp bin/skopeo "${OUTPUT}"
chmod 0755 "${OUTPUT}"
build_strip_binary "${OUTPUT}"
build_verify_glibc_elf "${OUTPUT}" "${GLIBC_BASELINE}"
"${OUTPUT}" --version >/dev/null

build_record_provenance \
  "${BUILD_DIR}" \
  skopeo \
  "${SKOPEO_REPO}" \
  "${SKOPEO_VERSION}" \
  "${BUILD_CHECKOUT_SHA}"
printf '%s\n' glibc > "${BUILD_DIR}/.build-metadata/skopeo.linkage"
printf '%s\n' "${GLIBC_BASELINE}" > "${BUILD_DIR}/.build-metadata/skopeo.glibc-baseline"

build_log "published glibc ${GLIBC_BASELINE} Skopeo artifact at ${OUTPUT}"

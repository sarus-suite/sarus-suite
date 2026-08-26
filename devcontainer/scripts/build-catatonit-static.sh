#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
. "${ROOT_DIR}/components.sh"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/catatonit"
PREFIX_DIR="${PODMAN_BUILD_PREFIX:-${BUILD_DIR}/podman-static-root}"
OUTPUT="${PREFIX_DIR}/usr/local/lib/podman/catatonit"

build_require_cmd git
build_require_cmd make
build_checkout_tag "${CATATONIT_REPO}" "${CATATONIT_VERSION}" "${SRC_DIR}"

cd "${SRC_DIR}"
./autogen.sh
./configure \
  --prefix=/ \
  --bindir=/bin \
  CFLAGS="${CATATONIT_CFLAGS:--Os}" \
  LDFLAGS="${CATATONIT_LDFLAGS:--static -s}"
make

mkdir -p "$(dirname "${OUTPUT}")"
cp catatonit "${OUTPUT}"
chmod 0755 "${OUTPUT}"
build_strip_binary "${OUTPUT}"
build_verify_static_elf "${OUTPUT}"
"${OUTPUT}" --version >/dev/null
build_record_provenance "${PREFIX_DIR}" catatonit "${CATATONIT_REPO}" "${CATATONIT_VERSION}" "${BUILD_CHECKOUT_SHA}"

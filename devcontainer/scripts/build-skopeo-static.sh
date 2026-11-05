#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
. "${ROOT_DIR}/components.sh"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/skopeo"
OUTPUT="${SKOPEO_BIN}"

build_require_cmd git
build_require_cmd make
build_require_cmd go
build_require_cmd pkg-config
build_checkout_tag "${SKOPEO_REPO}" "${SKOPEO_VERSION}" "${SRC_DIR}" "${SKOPEO_SHA}"

cd "${SRC_DIR}"

CGO_ENABLED=0 \
GOOS=linux \
GOARCH="${TARGET_ARCH}" \
GOFLAGS="${GOFLAGS:--buildvcs=false -trimpath}" \
make bin/skopeo \
  DISABLE_CGO=1 \
  GO_DYN_FLAGS=

mkdir -p "$(dirname "${OUTPUT}")"
cp bin/skopeo "${OUTPUT}"
chmod 0755 "${OUTPUT}"
build_strip_binary "${OUTPUT}"
build_verify_static_elf "${OUTPUT}"
"${OUTPUT}" --version >/dev/null

build_record_provenance \
  "${BUILD_DIR}" \
  skopeo \
  "${SKOPEO_REPO}" \
  "${SKOPEO_VERSION}" \
  "${BUILD_CHECKOUT_SHA}"

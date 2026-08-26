#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
. "${ROOT_DIR}/components.sh"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/conmon"
PREFIX_DIR="${PODMAN_BUILD_PREFIX:-${BUILD_DIR}/podman-static-root}"
OUTPUT="${PREFIX_DIR}/usr/local/lib/podman/conmon"

build_require_cmd git
build_require_cmd make
build_require_cmd pkg-config
build_checkout_tag "${CONMON_REPO}" "${CONMON_VERSION}" "${SRC_DIR}"

cd "${SRC_DIR}"
make git-vars bin/conmon \
  DISABLE_SYSTEMD=1 \
  PKG_CONFIG="pkg-config --static" \
  CFLAGS="${CONMON_CFLAGS:--std=c99 -Os -Wall -Wextra -Werror -static}" \
  LDFLAGS="${CONMON_LDFLAGS:--s -w -static}"

mkdir -p "$(dirname "${OUTPUT}")"
cp bin/conmon "${OUTPUT}"
chmod 0755 "${OUTPUT}"
build_strip_binary "${OUTPUT}"
build_verify_static_elf "${OUTPUT}"
"${OUTPUT}" --help >/dev/null
build_record_provenance "${PREFIX_DIR}" conmon "${CONMON_REPO}" "${CONMON_VERSION}" "${BUILD_CHECKOUT_SHA}"

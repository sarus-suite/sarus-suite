#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
. "${ROOT_DIR}/components.sh"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/passt"
PREFIX_DIR="${PODMAN_BUILD_PREFIX:-${BUILD_DIR}/podman-static-root}"
OUTPUT="${PREFIX_DIR}/usr/local/bin/pasta"

build_require_cmd git
build_require_cmd make
build_checkout_tag "${PASST_REPO}" "${PASST_VERSION}" "${SRC_DIR}"

cd "${SRC_DIR}"
make -n static >/dev/null 2>&1 || build_die "passt ref does not provide the expected static target"
make static

mkdir -p "$(dirname "${OUTPUT}")"
cp pasta "${OUTPUT}"
chmod 0755 "${OUTPUT}"
build_strip_binary "${OUTPUT}"
build_verify_static_elf "${OUTPUT}"
passt_version_output="$("${OUTPUT}" --version 2>&1)"
printf '%s\n' "${passt_version_output}" | grep -Fqi 'unknown version' \
  && build_die "passt build did not embed its source version"
build_record_provenance "${PREFIX_DIR}" passt "${PASST_REPO}" "${PASST_VERSION}" "${BUILD_CHECKOUT_SHA}"

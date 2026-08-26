#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
. "${ROOT_DIR}/components.sh"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/crun"
PREFIX_DIR="${PODMAN_BUILD_PREFIX:-${BUILD_DIR}/podman-static-root}"
OUTPUT="${PREFIX_DIR}/usr/local/bin/crun"

build_require_cmd git
build_require_cmd make
build_require_cmd pkg-config
build_checkout_tag "${CRUN_REPO}" "${CRUN_VERSION}" "${SRC_DIR}"

cd "${SRC_DIR}"
git submodule update --init --recursive
./autogen.sh
PKG_CONFIG="pkg-config --static" ./configure \
  --disable-systemd \
  --disable-shared \
  --enable-embedded-yajl
make \
  LDFLAGS="${CRUN_LDFLAGS:--static-libgcc -all-static}" \
  EXTRA_LDFLAGS="${CRUN_EXTRA_LDFLAGS:--s -w}"

mkdir -p "$(dirname "${OUTPUT}")"
cp crun "${OUTPUT}"
chmod 0755 "${OUTPUT}"
build_strip_binary "${OUTPUT}"
build_verify_static_elf "${OUTPUT}"
crun_version_output="$("${OUTPUT}" --version 2>&1)"
printf '%s\n' "${crun_version_output}" | grep -Eq '^crun version UNKNOWN$' \
  && build_die "crun build did not embed its source version"
build_record_provenance "${PREFIX_DIR}" crun "${CRUN_REPO}" "${CRUN_VERSION}" "${BUILD_CHECKOUT_SHA}"

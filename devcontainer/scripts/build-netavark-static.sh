#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
. "${ROOT_DIR}/devcontainer/scripts/lib/build-common.sh"
. "${ROOT_DIR}/components.sh"

build_require_native_target
build_make_workdir
SRC_DIR="${BUILD_WORKDIR}/netavark"
PREFIX_DIR="${PODMAN_BUILD_PREFIX:-${BUILD_DIR}/podman-static-root}"
OUTPUT="${PREFIX_DIR}/usr/local/lib/podman/netavark"

build_require_cmd git
build_require_cmd cargo
build_checkout_tag "${NETAVARK_REPO}" "${NETAVARK_VERSION}" "${SRC_DIR}"

cd "${SRC_DIR}"
[ -n "${RUST_MUSL_TARGET}" ] || build_die "unsupported TARGET_ARCH for netavark: ${TARGET_ARCH}"
export RUSTFLAGS="${NETAVARK_RUSTFLAGS:--C target-feature=+crt-static -C link-arg=-s}"
CARGO_BUILD_TARGET="${RUST_MUSL_TARGET}" cargo build --locked --release

mkdir -p "$(dirname "${OUTPUT}")"
cp "target/${RUST_MUSL_TARGET}/release/netavark" "${OUTPUT}"
chmod 0755 "${OUTPUT}"
build_strip_binary "${OUTPUT}"
build_verify_static_elf "${OUTPUT}"
"${OUTPUT}" --version >/dev/null
build_record_provenance "${PREFIX_DIR}" netavark "${NETAVARK_REPO}" "${NETAVARK_VERSION}" "${BUILD_CHECKOUT_SHA}"

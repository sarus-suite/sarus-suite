#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  build-rpm.sh [OPTIONS]

Assemble a fixed system payload and package it as an RPM. Additional payload
options are forwarded to assemble-system-payload.sh after --.

Options:
  --bundle-root DIR   Bundle to package (default: current build output)
  --version VERSION   RPM version (default: BUNDLE_VERSION without leading v)
  --release RELEASE   RPM release (default: 1)
  --output-dir DIR    RPM output directory (default: dist/rpm)
  -h, --help          Show this help

Example:
  build-rpm.sh --version 26.8.0 --release 0.emergency.1 -- \
    --import-binary /tmp/sarusctl:sarusctl \
    --import-hook-dir /tmp/hooks
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

BUNDLE_ROOT_ARG="${BUNDLE_ROOT}"
VERSION="${BUNDLE_VERSION#v}"
RELEASE=1
RELEASE_EXPLICIT=0
RPM_OUTPUT_DIR="${DIST_DIR}/rpm"
PAYLOAD_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle-root) [ $# -ge 2 ] || die "--bundle-root requires a directory"; BUNDLE_ROOT_ARG="$2"; shift 2 ;;
    --version) [ $# -ge 2 ] || die "--version requires a value"; VERSION="${2#v}"; shift 2 ;;
    --release) [ $# -ge 2 ] || die "--release requires a value"; RELEASE="$2"; RELEASE_EXPLICIT=1; shift 2 ;;
    --output-dir) [ $# -ge 2 ] || die "--output-dir requires a directory"; RPM_OUTPUT_DIR="$2"; shift 2 ;;
    --) shift; PAYLOAD_ARGS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (payload options must follow --)" ;;
  esac
done

IMPORT_REQUESTED=0
for payload_arg in "${PAYLOAD_ARGS[@]}"; do
  case "$payload_arg" in
    --import-binary|--import-hook-dir) IMPORT_REQUESTED=1 ;;
  esac
done
if [ "$IMPORT_REQUESTED" -eq 1 ]; then
  [ "$RELEASE_EXPLICIT" -eq 1 ] || die "imported components require an explicit nonstandard --release"
  [ "$RELEASE" != 1 ] || die "imported components cannot use the normal release: 1"
fi

command -v rpmbuild >/dev/null 2>&1 || die "missing required command: rpmbuild"
case "$VERSION" in *[!A-Za-z0-9._+~]*) die "invalid RPM version: ${VERSION}" ;; esac
case "$RELEASE" in *[!A-Za-z0-9._+~]*) die "invalid RPM release: ${RELEASE}" ;; esac
[ -d "$BUNDLE_ROOT_ARG" ] || die "bundle root not found: ${BUNDLE_ROOT_ARG}"

case "$TARGET_ARCH" in
  amd64) RPM_ARCH=x86_64 ;;
  arm64) RPM_ARCH=aarch64 ;;
  *) RPM_ARCH="$TARGET_ARCH" ;;
esac

PACKAGE_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sarus-suite-rpm.XXXXXX")"
trap 'rm -rf "${PACKAGE_WORK_DIR}"' EXIT INT TERM
TOP_DIR="${PACKAGE_WORK_DIR}/rpmbuild"
PAYLOAD_DIR="${PACKAGE_WORK_DIR}/payload"
install -d "${TOP_DIR}/BUILD" "${TOP_DIR}/BUILDROOT" "${TOP_DIR}/RPMS" "${TOP_DIR}/SOURCES" "${TOP_DIR}/SPECS" "${TOP_DIR}/SRPMS"

"${ROOT_DIR}/scripts/assemble-system-payload.sh" \
  --bundle-root "$(cd "$BUNDLE_ROOT_ARG" && pwd -P)" \
  --output-dir "$PAYLOAD_DIR" \
  "${PAYLOAD_ARGS[@]}"

COPYFILE_DISABLE=1 tar -C "$PAYLOAD_DIR" -czf "${TOP_DIR}/SOURCES/sarus-suite-system-payload.tar.gz" .
install -m 0644 "${ROOT_DIR}/packaging/rpm/sarus-suite.spec" "${TOP_DIR}/SPECS/sarus-suite.spec"
rpmbuild -bb \
  --target "$RPM_ARCH" \
  --define "_topdir ${TOP_DIR}" \
  --define "sarus_suite_version ${VERSION}" \
  --define "sarus_suite_release ${RELEASE}" \
  "${TOP_DIR}/SPECS/sarus-suite.spec"

install -d "$RPM_OUTPUT_DIR"
while IFS= read -r rpm; do
  install -m 0644 "$rpm" "$RPM_OUTPUT_DIR/"
  printf 'RPM ready at %s/%s\n' "$RPM_OUTPUT_DIR" "$(basename "$rpm")"
done < <(find "${TOP_DIR}/RPMS" -type f -name '*.rpm' -print | sort)

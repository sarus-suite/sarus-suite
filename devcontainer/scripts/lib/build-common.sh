#!/usr/bin/env sh
set -eu

build_log() {
  printf '[build] %s\n' "$*"
}

build_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

build_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || build_die "required command not found: $1"
}

build_resolve_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$(pwd -P)" "$1" ;;
  esac
}

build_prepare_output() {
  output_path="$(build_resolve_path "$1")"
  mkdir -p "$(dirname "${output_path}")"
  printf '%s\n' "${output_path}"
}

build_checkout_tag() {
  repo="$1"
  ref="$2"
  destination="$3"

  mkdir -p "$(dirname "${destination}")"
  git init -q "${destination}"
  git -C "${destination}" remote add origin "${repo}"
  git -C "${destination}" fetch --depth 1 origin "refs/tags/${ref}:refs/tags/${ref}" >/dev/null
  git -C "${destination}" checkout --detach "refs/tags/${ref}" >/dev/null
  BUILD_CHECKOUT_SHA="$(git -C "${destination}" rev-parse HEAD)"
  export BUILD_CHECKOUT_SHA
}

build_require_native_target() {
  case "$(uname -m)" in
    aarch64|arm64) native_arch=arm64 ;;
    x86_64|amd64) native_arch=amd64 ;;
    *) build_die "unsupported native build architecture: $(uname -m)" ;;
  esac

  [ "${TARGET_ARCH:-}" = "${native_arch}" ] \
    || build_die "TARGET_ARCH=${TARGET_ARCH:-unset} does not match native build architecture ${native_arch}; cross-compilation is not supported"
}

build_record_provenance() {
  prefix="$1"
  component="$2"
  repo="$3"
  ref="$4"
  sha="$5"
  metadata_dir="${prefix}/.build-metadata"

  mkdir -p "${metadata_dir}"
  printf '%s\n' "${repo}" > "${metadata_dir}/${component}.repo"
  printf '%s\n' "${ref}" > "${metadata_dir}/${component}.ref"
  printf '%s\n' "${sha}" > "${metadata_dir}/${component}.sha"
}

build_strip_binary() {
  binary="$1"
  build_require_cmd strip
  strip "${binary}"
}

build_verify_static_elf() {
  binary="$1"

  [ -x "${binary}" ] || build_die "expected executable: ${binary}"
  build_require_cmd file
  build_require_cmd readelf

  file_output="$(file -b "${binary}")"
  printf '%s\n' "${file_output}" | grep -Eq 'ELF .*executable|ELF .*shared object' \
    || build_die "not an ELF executable: ${binary}"

  case "${TARGET_ARCH:-}" in
    amd64)
      printf '%s\n' "${file_output}" | grep -Eq 'x86-64|x86_64' \
        || build_die "binary does not match TARGET_ARCH=amd64: ${binary}: ${file_output}"
      ;;
    arm64)
      printf '%s\n' "${file_output}" | grep -Eq 'ARM aarch64|aarch64' \
        || build_die "binary does not match TARGET_ARCH=arm64: ${binary}: ${file_output}"
      ;;
    *)
      build_die "unsupported TARGET_ARCH for ELF verification: ${TARGET_ARCH:-unset}"
      ;;
  esac

  if readelf -l "${binary}" | grep -q 'Requesting program interpreter'; then
    build_die "binary is dynamically linked: ${binary}"
  fi
}

build_cleanup_workdir() {
  if [ "${KEEP_WORKDIR:-0}" = "1" ]; then
    build_log "keeping build workspace at ${BUILD_WORKDIR}"
    return
  fi

  rm -rf "${BUILD_WORKDIR}"
}

build_make_workdir() {
  BUILD_WORKDIR="$(mktemp -d)"
  trap build_cleanup_workdir EXIT HUP INT TERM
}

build_jobs() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n'
}

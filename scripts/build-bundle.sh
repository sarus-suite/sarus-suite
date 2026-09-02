#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

# shellcheck source=vendor/clack-bash/clack-build-ui.sh
source "${ROOT_DIR}/scripts/vendor/clack-bash/clack-build-ui.sh"

BUILD_LOG_TAIL="${BUILD_LOG_TAIL:-100}"
BUILD_UI_ENABLED=0
BUILD_LOG_DIR="${BUILD_LOG_DIR:-}"
BUILD_STAGE=""
BUILD_STAGE_INDEX=0

log() {
  printf '[build-bundle] %s\n' "$*"
}

build_ui_enabled() {
  [ -t 2 ] && [ "${CI:-}" != 1 ] && [ "${VERBOSE:-0}" != 1 ] && [ -z "${NO_COLOR:-}" ]
}

stage_log_name() {
  printf '%s' "$1" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]._-'
}

show_stage_failure() {
  local status="$1"
  local log_file="$2"

  printf '[build-bundle] %s failed (exit %s)\n' "${BUILD_STAGE}" "${status}" >&2
  printf '[build-bundle] last %s lines: %s\n' "${BUILD_LOG_TAIL}" "${log_file}" >&2
  tail -n "${BUILD_LOG_TAIL}" "${log_file}" >&2 || true
  printf '[build-bundle] full log: %s\n' "${log_file}" >&2
}

run_stage() {
  local label="$1"
  local log_file status slug
  shift

  BUILD_STAGE="${label}"
  BUILD_STAGE_INDEX=$((BUILD_STAGE_INDEX + 1))
  slug="$(stage_log_name "${label}")"
  log_file="${BUILD_LOG_DIR}/$(printf '%02d' "${BUILD_STAGE_INDEX}")-${slug}.log"

  if [ "${BUILD_UI_ENABLED}" -eq 1 ]; then
    clack_spinner_start "${label}" timer
    if "$@" >"${log_file}" 2>&1; then
      clack_spinner_stop "${label}"
      return 0
    else
      status=$?
      clack_spinner_error "${label} failed"
      show_stage_failure "${status}" "${log_file}"
      return "${status}"
    fi
  fi

  log "running ${label} (log: ${log_file})"
  if "$@" 2>&1 | tee "${log_file}"; then
    status="${PIPESTATUS[0]}"
  else
    status="${PIPESTATUS[0]}"
  fi
  if [ "${status}" -eq 0 ]; then
    return 0
  else
    show_stage_failure "${status}" "${log_file}"
    return "${status}"
  fi
}

on_interrupt() {
  if [ "${BUILD_UI_ENABLED}" -eq 1 ] && [ -n "${BUILD_STAGE}" ]; then
    clack_spinner_cancel "${BUILD_STAGE} cancelled"
  fi
  printf '[build-bundle] interrupted; logs: %s\n' "${BUILD_LOG_DIR:-unavailable}" >&2
  exit 130
}

require_build_environment() {
  local podman_mode="${PODMAN_MODE:-glibc}"

  case "${podman_mode}" in
    glibc|static) ;;
    *)
      printf 'error: unsupported PODMAN_MODE=%s (expected glibc or static)\n' "${podman_mode}" >&2
      exit 2
      ;;
  esac

  if command -v devcontainer >/dev/null 2>&1; then
    return 0
  fi

  if [ "${podman_mode}" = static ] && [ -f /etc/alpine-release ]; then
    return 0
  fi

  if [ "${podman_mode}" = glibc ]; then
    cat >&2 <<'EOF'
error: the default glibc Podman bundle build requires the devcontainer CLI
with a working Docker or Podman backend.

Use PODMAN_MODE=static only when building natively in the supported Alpine
build environment.
EOF
  else
    cat >&2 <<'EOF'
error: the static Podman bundle build requires either:
  - devcontainer CLI with a working Docker or Podman backend, or
  - an Alpine build environment
EOF
  fi
  exit 1
}

tar_supports_flag() {
  local flag="$1"
  local tmp_dir
  local probe_tar

  tmp_dir="$(mktemp -d)"
  probe_tar="$(mktemp)"
  rm -f "${probe_tar}"

  if tar "${flag}" -cf "${probe_tar}" -C "${tmp_dir}" . >/dev/null 2>&1; then
    rm -rf "${tmp_dir}" "${probe_tar}"
    return 0
  fi

  rm -rf "${tmp_dir}" "${probe_tar}"
  return 1
}

require_build_environment

mkdir -p "${WORK_DIR}/logs"
if [ -n "${BUILD_LOG_DIR:-}" ]; then
  mkdir -p "${BUILD_LOG_DIR}"
else
  BUILD_LOG_DIR="$(mktemp -d "${WORK_DIR}/logs/build-bundle.XXXXXX")"
fi
if build_ui_enabled; then
  BUILD_UI_ENABLED=1
  printf 'Sarus Suite bundle build\n' >&2
fi
trap on_interrupt INT TERM

run_stage 'Fetching components' "${ROOT_DIR}/scripts/fetch-components.sh"
run_stage 'Building Podman' "${ROOT_DIR}/scripts/build-podman.sh"
run_stage 'Building Parallax' "${ROOT_DIR}/scripts/build-parallax.sh"
run_stage 'Building sarusctl' "${ROOT_DIR}/scripts/build-sarusctl.sh"
run_stage 'Building performance extensions' "${ROOT_DIR}/scripts/build-performance-extensions.sh"
run_stage 'Building helpers' "${ROOT_DIR}/scripts/build-helpers.sh"
run_stage 'Assembling bundle' "${ROOT_DIR}/scripts/assemble-bundle.sh"
run_stage 'Verifying bundle' "${ROOT_DIR}/scripts/verify-bundle.sh"

tarball="${OUT_DIR}.tar.gz"
rm -f "${tarball}"
# macOS local builds use these flags/env to avoid AppleDouble files and xattrs;
# GNU tar on Linux CI does not support every flag, so probe before using them.
tar_args=()
for flag in --no-xattrs --disable-copyfile; do
  if tar_supports_flag "${flag}"; then
    tar_args+=("${flag}")
  fi
done

run_stage 'Creating tarball' env COPYFILE_DISABLE=1 tar "${tar_args[@]}" -C "${OUT_DIR}" -czf "${tarball}" "${BUNDLE_NAME}"

printf 'Bundle ready under %s\n' "${BUNDLE_ROOT}"
printf 'Tarball ready at %s\n' "${tarball}"
printf 'Build logs: %s\n' "${BUILD_LOG_DIR}"

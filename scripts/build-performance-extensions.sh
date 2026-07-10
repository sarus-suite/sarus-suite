#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

log() {
  printf '[build-performance-extensions] %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

resolve_target_triple() {
  case "${TARGET_ARCH}" in
    amd64)
      printf '%s\n' 'x86_64-unknown-linux-musl'
      ;;
    arm64)
      printf '%s\n' 'aarch64-unknown-linux-musl'
      ;;
    *)
      die "unsupported TARGET_ARCH for performance-extensions build: ${TARGET_ARCH}"
      ;;
  esac
}

verify_linux_binary_arch() {
  local path="$1"
  local info

  command -v file >/dev/null 2>&1 || return 0
  info="$(file "${path}")"
  case "${TARGET_ARCH}" in
    amd64)
      printf '%s\n' "${info}" | grep -Eq 'ELF .*x86-64|ELF .*x86_64' || die "performance-extensions binary does not match TARGET_ARCH=${TARGET_ARCH}: ${info}"
      ;;
    arm64)
      printf '%s\n' "${info}" | grep -Eq 'ELF .*ARM aarch64|ELF .*arm64' || die "performance-extensions binary does not match TARGET_ARCH=${TARGET_ARCH}: ${info}"
      ;;
  esac
}

mkdir -p "${PERFEXT_BUILD_DIR}"

if [ ! -d "${PERFEXT_SRC_DIR}/.git" ]; then
  "${ROOT_DIR}/scripts/fetch-components.sh"
fi

[ -d "${PERFEXT_SRC_DIR}" ] || die "performance-extensions source directory not found: ${PERFEXT_SRC_DIR}"

[ -f "${PERFEXT_SRC_DIR}/${PERFEXT_DEVCONTAINER_CONFIG}" ] || die "performance-extensions devcontainer config not found: ${PERFEXT_SRC_DIR}/${PERFEXT_DEVCONTAINER_CONFIG}"
target_triple="$(resolve_target_triple)"

build_cmd=$(cat <<BUILD
set -euo pipefail
mkdir -p dist
cargo build --release --target "${target_triple}" --bins
cp -f "target/${target_triple}/release/ldcache_hook" dist/ldcache_hook
cp -f "target/${target_triple}/release/mps_hook" dist/mps_hook
cp -f "target/${target_triple}/release/pce_hook" dist/pce_hook
cp -f "target/${target_triple}/release/pc_injection_hook" dist/pc_injection_hook
cp -f "target/${target_triple}/release/mkhomedir" dist/mkhomedir
cp -f "target/${target_triple}/release/sethomevar" dist/sethomevar
BUILD
)

case "${PERFEXT_BUILD_MODE}" in
  devcontainer)
    command -v devcontainer >/dev/null 2>&1 || die "need devcontainer CLI to build performance-extensions"
    (
      cd "${PERFEXT_SRC_DIR}"
      log "running devcontainer up"
      devcontainer up \
        --workspace-folder . \
        --config "${PERFEXT_SRC_DIR}/${PERFEXT_DEVCONTAINER_CONFIG}" >/dev/null
      log "running devcontainer exec"
      cd /
      devcontainer exec \
        --workspace-folder "${PERFEXT_SRC_DIR}" \
        --config "${PERFEXT_SRC_DIR}/${PERFEXT_DEVCONTAINER_CONFIG}" \
        bash -lc "cd /workspaces/\$(basename \"${PERFEXT_SRC_DIR}\") && ${build_cmd}"
    )
    ;;
  host)
    (
      cd "${PERFEXT_SRC_DIR}"
      bash -lc "${build_cmd}"
    )
    ;;
  *)
    die "unsupported PERFEXT_BUILD_MODE: ${PERFEXT_BUILD_MODE}"
    ;;
esac

install -Dm0755 "${PERFEXT_SRC_DIR}/dist/ldcache_hook" "${PERFEXT_LDCACHE_HOOK_BIN}"
install -Dm0755 "${PERFEXT_SRC_DIR}/dist/mps_hook" "${PERFEXT_MPS_HOOK_BIN}"
install -Dm0755 "${PERFEXT_SRC_DIR}/dist/pce_hook" "${PERFEXT_PCE_HOOK_BIN}"
install -Dm0755 "${PERFEXT_SRC_DIR}/dist/pc_injection_hook" "${PERFEXT_PC_INJECTION_HOOK_BIN}"
install -Dm0755 "${PERFEXT_SRC_DIR}/dist/mkhomedir" "${PERFEXT_MKHOMEDIR_BIN}"
install -Dm0755 "${PERFEXT_SRC_DIR}/dist/sethomevar" "${PERFEXT_SETHOMEVAR_BIN}"

for bin in \
  "${PERFEXT_LDCACHE_HOOK_BIN}" \
  "${PERFEXT_MPS_HOOK_BIN}" \
  "${PERFEXT_PCE_HOOK_BIN}" \
  "${PERFEXT_PC_INJECTION_HOOK_BIN}" \
  "${PERFEXT_MKHOMEDIR_BIN}" \
  "${PERFEXT_SETHOMEVAR_BIN}"
do
  [ -x "${bin}" ] || die "missing performance-extensions binary: ${bin}"
  verify_linux_binary_arch "${bin}"
done

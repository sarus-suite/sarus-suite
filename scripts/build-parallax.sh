#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

log() {
  printf '[build-parallax] %s\n' "$*"
}

if [ ! -d "${PARALLAX_SRC_DIR}/.git" ]; then
  "${ROOT_DIR}/scripts/fetch-components.sh"
fi

resolve_devcontainer_config() {
  local candidate

  for candidate in \
    "${PARALLAX_DEVCONTAINER_CONFIG}" \
    ".devcontainer/devcontainer.json" \
    ".devcontainer/alpine/devcontainer.json"
  do
    [ -n "${candidate}" ] || continue
    if [ -f "${PARALLAX_SRC_DIR}/${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf 'error: no Parallax devcontainer config found under %s\n' "${PARALLAX_SRC_DIR}" >&2
  exit 1
}

resolve_build_cmd() {
  if [ -n "${PARALLAX_BUILD_SCRIPT:-}" ] && [ -f "${PARALLAX_SRC_DIR}/${PARALLAX_BUILD_SCRIPT}" ]; then
    cat <<BUILD
set -euo pipefail
mkdir -p "$(dirname "${PARALLAX_OUT_REL}")"
OUT="${PARALLAX_OUT_REL}" sh "${PARALLAX_BUILD_SCRIPT}"
BUILD
    return 0
  fi

  cat <<BUILD
set -euo pipefail
mkdir -p "$(dirname "${PARALLAX_OUT_REL}")"
CGO_ENABLED="${PARALLAX_CGO_ENABLED:-1}" GOOS=linux GOARCH="${TARGET_ARCH}" go build -trimpath -o "${PARALLAX_OUT_REL}" .
BUILD
}

devcontainer_config="$(resolve_devcontainer_config)"
build_cmd="$(resolve_build_cmd)"
devcontainer_config_path="${PARALLAX_SRC_DIR}/${devcontainer_config}"

log "source dir: ${PARALLAX_SRC_DIR}"
log "devcontainer config: ${devcontainer_config_path}"
log "output binary: ${PARALLAX_BIN}"

if command -v devcontainer >/dev/null 2>&1; then
  (
    cd "${PARALLAX_SRC_DIR}"
    log "host pwd before devcontainer up: $(pwd -P)"
    log "running devcontainer up"
    devcontainer up \
      --workspace-folder . \
      --config "${devcontainer_config_path}" >/dev/null

    log "running devcontainer exec"
    cd /
    log "host pwd before devcontainer exec: $(pwd -P)"
    devcontainer exec \
      --workspace-folder "${PARALLAX_SRC_DIR}" \
      --config "${devcontainer_config_path}" \
      bash -lc "cd /workspaces/\$(basename \"${PARALLAX_SRC_DIR}\") && ${build_cmd}"
  )
elif [ -f /etc/alpine-release ]; then
  (
    cd "${PARALLAX_SRC_DIR}"
    bash -lc "${build_cmd}"
  )
else
  printf '%s\n' 'error: need devcontainer CLI or Alpine build environment to build parallax' >&2
  exit 1
fi

[ -x "${PARALLAX_BIN}" ] || {
  printf 'error: missing parallax binary: %s\n' "${PARALLAX_BIN}" >&2
  exit 1
}

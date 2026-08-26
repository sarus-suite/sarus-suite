#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

[ "$#" -eq 1 ] || {
  printf 'usage: %s <shell command>\n' "${BASH_SOURCE[0]}" >&2
  exit 2
}

build_cmd="$1"

if command -v devcontainer >/dev/null 2>&1; then
  devcontainer up \
    --workspace-folder "${ROOT_DIR}" \
    --config "${ROOT_DIR}/devcontainer/alpine/devcontainer.json" >/dev/null

  workspace_name="$(basename "${ROOT_DIR}")"
  devcontainer exec \
    --workspace-folder "${ROOT_DIR}" \
    --config "${ROOT_DIR}/devcontainer/alpine/devcontainer.json" \
    bash -lc "cd /workspaces/${workspace_name} && ${build_cmd}"
elif [ -f /etc/alpine-release ]; then
  bash -lc "cd '${ROOT_DIR}' && ${build_cmd}"
else
  printf '%s\n' 'error: need devcontainer CLI or Alpine build environment' >&2
  exit 1
fi

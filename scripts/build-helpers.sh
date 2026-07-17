#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

mkdir -p "${BUILD_DIR}"

build_cmd=$(cat <<'BUILD'
set -euo pipefail
source ./components.sh
mkdir -p "${BUILD_DIR}"

OUT="${MKSQUASHFS_BIN}" SQUASHFS_TOOLS_VERSION="${MKSQUASHFS_VERSION}" sh ./devcontainer/scripts/build-mksquashfs-static.sh
OUT_DIR="$(dirname "${RSYNC_BIN}")" RSYNC_VERSION="${RSYNC_VERSION}" sh ./devcontainer/scripts/build-rsync-static.sh
OUT="${INOTIFYWAIT_BIN}" INOTIFY_TOOLS_VERSION="${INOTIFY_TOOLS_VERSION}" sh ./devcontainer/scripts/build-inotifywait-static.sh
OUT="${SQUASHFUSE_LL_BIN}" SQUASHFUSE_VERSION="${SQUASHFUSE_VERSION}" sh ./devcontainer/scripts/build-squashfuse-ll-static.sh
OUT="${FUSE_OVERLAYFS_BIN}" FUSE_OVERLAYFS_VERSION="${FUSE_OVERLAYFS_VERSION}" sh ./devcontainer/scripts/build-fuse-overlayfs-static.sh
OUT="${FUSERMOUNT3_BIN}" LIBFUSE_VERSION="${LIBFUSE_VERSION}" sh ./devcontainer/scripts/build-fusermount3-static.sh
OUT="${BWRAP_BIN}" BUBBLEWRAP_VERSION="${BUBBLEWRAP_VERSION}" BUBBLEWRAP_REPO="${BUBBLEWRAP_REPO}" sh ./devcontainer/scripts/build-bwrap-static.sh
BUILD
)

if command -v devcontainer >/dev/null 2>&1; then
  devcontainer up \
    --workspace-folder "${ROOT_DIR}" \
    --config "${ROOT_DIR}/devcontainer/alpine/devcontainer.json" >/dev/null

  devcontainer exec \
    --workspace-folder "${ROOT_DIR}" \
    --config "${ROOT_DIR}/devcontainer/alpine/devcontainer.json" \
    bash -lc "${build_cmd}"
elif [ -f /etc/alpine-release ]; then
  bash -lc "${build_cmd}"
else
  printf '%s\n' 'error: need devcontainer CLI or Alpine build environment to build helpers' >&2
  exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUNDLE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
FORWARD_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-root)
      [ "$#" -ge 2 ] || {
        printf 'error: --bundle-root requires a directory\n' >&2
        exit 1
      }
      BUNDLE_ROOT="$2"
      shift 2
      ;;
    *)
      FORWARD_ARGS+=("$1")
      shift
      ;;
  esac
done

INSTALLER="${BUNDLE_ROOT}/libexec/sarus-suite/install.sh"

[ -x "$INSTALLER" ] || {
  printf 'error: bundled installer not found: %s\n' "$INSTALLER" >&2
  exit 1
}

exec "$INSTALLER" user-uninstall "${FORWARD_ARGS[@]}"

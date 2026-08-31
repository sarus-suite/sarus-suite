#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible build entry point. New callers should use install.sh
# directly so staging and live application share one payload renderer.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${SCRIPT_DIR}/install.sh" stage "$@"

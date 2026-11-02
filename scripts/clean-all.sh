#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

# shellcheck source=vendor/clack-bash/clack-build-ui.sh
source "${ROOT_DIR}/scripts/vendor/clack-bash/clack-build-ui.sh"

CI_CACHE_DIR="${CI_CACHE_DIR:-${ROOT_DIR}/.ci-cache}"

rm -rf "${WORK_DIR}" "${CACHE_DIR}" "${DIST_DIR}" "${CI_CACHE_DIR}"

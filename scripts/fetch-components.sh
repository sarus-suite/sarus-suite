#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

mkdir -p "${SRC_DIR}"
require_cmd git

fetch_repo() {
  local repo="$1"
  local ref="$2"
  local dest="$3"
  local checkout_ref="$ref"

  if [ ! -d "${dest}/.git" ]; then
    git clone "${repo}" "${dest}"
  fi

  git -C "${dest}" fetch --tags origin
  if git -C "${dest}" show-ref --verify --quiet "refs/remotes/origin/${ref}"; then
    checkout_ref="refs/remotes/origin/${ref}"
  fi

  git -C "${dest}" checkout --detach "${checkout_ref}"
}

fetch_repo "${PARALLAX_REPO}" "${PARALLAX_REF}" "${PARALLAX_SRC_DIR}"
printf '%s\n' "Fetched parallax at $(git -C "${PARALLAX_SRC_DIR}" rev-parse --short HEAD)"

fetch_repo "${SARUSCTL_REPO}" "${SARUSCTL_REF}" "${SARUSCTL_SRC_DIR}"
printf '%s\n' "Fetched cluster-tooling at $(git -C "${SARUSCTL_SRC_DIR}" rev-parse --short HEAD)"

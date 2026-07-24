#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

log() {
  printf '[build-sarusctl] %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

resolve_devcontainer_config() {
  local candidate

  for candidate in \
    "${SARUSCTL_DEVCONTAINER_CONFIG}" \
    ".devcontainer/alpine/devcontainer.json" \
    ".devcontainer/ubuntu/devcontainer.json" \
    ".devcontainer/opensuse/devcontainer.json"
  do
    [ -n "${candidate}" ] || continue
    if [ -f "${SARUSCTL_SRC_DIR}/${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  die "no sarusctl devcontainer config found under ${SARUSCTL_SRC_DIR}"
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
      die "unsupported TARGET_ARCH for sarusctl build: ${TARGET_ARCH}"
      ;;
  esac
}

docker_cli_is_podman() {
  local runtime="${SARUSCTL_DEVCONTAINER_RUNTIME:-auto}"
  local docker_path
  local docker_realpath
  local output

  case "${runtime}" in
    podman)
      return 0
      ;;
    docker)
      return 1
      ;;
    auto)
      ;;
    *)
      die "unsupported SARUSCTL_DEVCONTAINER_RUNTIME: ${runtime}"
      ;;
  esac

  docker_path="$(command -v docker 2>/dev/null || true)"
  if [ -n "${docker_path}" ]; then
    docker_realpath="$(realpath "${docker_path}" 2>/dev/null || printf '%s\n' "${docker_path}")"
    case "${docker_path}:${docker_realpath}" in
      *podman*)
        return 0
        ;;
    esac
  fi

  output="$(
    {
      docker --version
      docker version
      docker info
    } 2>&1 || true
  )"
  printf '%s\n' "${output}" | grep -Eiq 'podman|Emulate Docker CLI using podman'
}

prepare_devcontainer_config() {
  local config_rel="$1"
  local config_path="${SARUSCTL_SRC_DIR}/${config_rel}"
  local config_dir
  local generated_dir
  local generated_path

  config_dir="$(dirname "${config_path}")"
  generated_dir="${config_dir}/sarus-suite-build"
  generated_path="${generated_dir}/devcontainer.json"

  if docker_cli_is_podman && grep -q '"--userns=host"' "${config_path}"; then
    mkdir -p "${generated_dir}"
    sed \
      -e 's/"dockerfile"[[:space:]]*:[[:space:]]*"Containerfile"/"dockerfile": "..\/Containerfile"/' \
      -e 's/"context"[[:space:]]*:[[:space:]]*"\.\.\/\.\."/"context": "..\/..\/.."/' \
      -e 's/"runArgs"[[:space:]]*:[[:space:]]*\["--userns=host"\]/"runArgs": ["--group-add=keep-groups"]/' \
      "${config_path}" > "${generated_path}"
    log "using Podman devcontainer config with keep-groups: ${generated_path}" >&2
    printf '%s\n' "${generated_path}"
    return 0
  fi

  printf '%s\n' "${config_path}"
}

verify_linux_binary_arch() {
  local path="$1"
  local info

  command -v file >/dev/null 2>&1 || return 0
  info="$(file "${path}")"
  case "${TARGET_ARCH}" in
    amd64)
      printf '%s\n' "${info}" | grep -Eq 'ELF .*x86-64|ELF .*x86_64' || die "sarusctl binary does not match TARGET_ARCH=${TARGET_ARCH}: ${info}"
      ;;
    arm64)
      printf '%s\n' "${info}" | grep -Eq 'ELF .*ARM aarch64|ELF .*arm64' || die "sarusctl binary does not match TARGET_ARCH=${TARGET_ARCH}: ${info}"
      ;;
  esac
}

[ -d "${SARUSCTL_SRC_DIR}" ] || die "cluster-tooling source directory not found: ${SARUSCTL_SRC_DIR}"
mkdir -p "${BUILD_DIR}"

if [ -n "${SARUSCTL_PREBUILT_BIN}" ]; then
  [ -x "${SARUSCTL_PREBUILT_BIN}" ] || die "SARUSCTL_PREBUILT_BIN is not executable: ${SARUSCTL_PREBUILT_BIN}"
  install -m0755 "${SARUSCTL_PREBUILT_BIN}" "${SARUSCTL_BIN}"
  verify_linux_binary_arch "${SARUSCTL_BIN}"
  exit 0
fi

if [ ! -d "${SARUSCTL_SRC_DIR}/.git" ]; then
  "${ROOT_DIR}/scripts/fetch-components.sh"
fi

devcontainer_config="$(resolve_devcontainer_config)"
devcontainer_config_path="$(prepare_devcontainer_config "${devcontainer_config}")"
target_triple="$(resolve_target_triple)"
devcontainer_uid="${SARUSCTL_DEVCONTAINER_UID:-$(id -u)}"
devcontainer_gid="${SARUSCTL_DEVCONTAINER_GID:-1000}"
if docker_cli_is_podman; then
  devcontainer_gid="${SARUSCTL_DEVCONTAINER_GID:-$(id -g)}"
fi
devcontainer_env=(
  env
  "USER=${USER:-$(id -un)}"
  "UID=${devcontainer_uid}"
  "GID=${devcontainer_gid}"
)

build_cmd=$(cat <<BUILD
set -euo pipefail
mkdir -p dist
cargo build --locked -p sarusctl --release --target "${target_triple}"
cargo test --locked -p sarusctl --test cli --target "${target_triple}"
cp -f "\${CARGO_TARGET_DIR:-target}/${target_triple}/release/sarusctl" "${SARUSCTL_OUT_REL}"
BUILD
)

case "${SARUSCTL_BUILD_MODE}" in
  devcontainer)
    command -v devcontainer >/dev/null 2>&1 || die "need devcontainer CLI to build sarusctl"
    (
      cd "${SARUSCTL_SRC_DIR}"
      "${devcontainer_env[@]}" devcontainer up \
        --workspace-folder . \
        --config "${devcontainer_config_path}" >/dev/null
      cd /
      "${devcontainer_env[@]}" devcontainer exec \
        --workspace-folder "${SARUSCTL_SRC_DIR}" \
        --config "${devcontainer_config_path}" \
        bash -lc "cd /workspaces/\$(basename \"${SARUSCTL_SRC_DIR}\") && ${build_cmd}"
    )
    ;;
  host)
    (
      cd "${SARUSCTL_SRC_DIR}"
      bash -lc "${build_cmd}"
    )
    ;;
  *)
    die "unsupported SARUSCTL_BUILD_MODE: ${SARUSCTL_BUILD_MODE}"
    ;;
esac

install -Dm0755 "${SARUSCTL_SRC_DIR}/${SARUSCTL_OUT_REL}" "${SARUSCTL_BIN}"
[ -x "${SARUSCTL_BIN}" ] || die "missing sarusctl binary: ${SARUSCTL_BIN}"
verify_linux_binary_arch "${SARUSCTL_BIN}"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

log() {
  printf '[build-skybox] %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

resolve_devcontainer_config() {
  local candidate

  for candidate in \
    "${SKYBOX_DEVCONTAINER_CONFIG}" \
    ".devcontainer/skybox/devcontainer.json" 
  do
    [ -n "${candidate}" ] || continue
    if [ -f "${SKYBOX_SRC_DIR}/${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  die "no skybox devcontainer config found under ${SKYBOX_SRC_DIR}"
}

resolve_target_triple() {
  case "${TARGET_ARCH}" in
    amd64)
      printf '%s\n' 'x86_64-unknown-linux-gnu'
      ;;
    arm64)
      printf '%s\n' 'aarch64-unknown-linux-gnu'
      ;;
    *)
      die "unsupported TARGET_ARCH for skybox build: ${TARGET_ARCH}"
      ;;
  esac
}

docker_cli_is_podman() {
  local runtime="${SKYBOX_DEVCONTAINER_RUNTIME:-auto}"
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
      die "unsupported SKYBOX_DEVCONTAINER_RUNTIME: ${runtime}"
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

repair_stale_podman_volumes() {
  local volume mountpoint

  docker_cli_is_podman || return 0

  # Rootless Podman can retain a named volume in its database after the
  # backing directory has disappeared (for example when the rootless store
  # is on a temporary filesystem).  A subsequent container start then fails
  # while Podman tries to read the volume for copy-up.  These volumes only
  # contain disposable Cargo caches, so recreate only entries whose recorded
  # mountpoint is no longer present.
  for volume in \
    skybox-static-cargo-registry \
    skybox-static-cargo-git \
    skybox-static-rustup
  do
    mountpoint="$(docker volume inspect --format '{{.Mountpoint}}' "${volume}" 2>/dev/null || true)"
    [ -n "${mountpoint}" ] || continue
    [ -d "${mountpoint}" ] && continue

    log "removing stale Podman volume: ${volume} (${mountpoint})" >&2
    docker volume rm --force "${volume}" >/dev/null
  done
}

prepare_devcontainer_config() {
  local config_rel="$1"
  local config_path="${SKYBOX_SRC_DIR}/${config_rel}"
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
      printf '%s\n' "${info}" | grep -Eq 'ELF .*x86-64|ELF .*x86_64' || die "skybox library does not match TARGET_ARCH=${TARGET_ARCH}: ${info}"
      ;;
    arm64)
      printf '%s\n' "${info}" | grep -Eq 'ELF .*ARM aarch64|ELF .*arm64' || die "skybox library does not match TARGET_ARCH=${TARGET_ARCH}: ${info}"
      ;;
  esac
}

build_single_skybox() {
  local SLURM_VERSION="$1"	
  [ -n "${SLURM_VERSION}" ] || die "Missing SLURM_VERSION"

  SLURM_MAJOR_VERSION=$(echo $SLURM_VERSION | awk -F. '{printf "%02d.%02d\n",$1,$2}')
  SKYBOX_LIB="${SKYBOX_LIB_NAME}-slurm-${SLURM_MAJOR_VERSION}.${SKYBOX_LIB_EXT}"
  SKYBOX_BUILD_LIB="${SKYBOX_BUILD_DIR}/${SKYBOX_LIB}"
  SKYBOX_OUT_REL="${SKYBOX_OUT_REL_DIR}/${SKYBOX_LIB}"
  export CARGO_TARGET_DIR="target.slurm-${SLURM_MAJOR_VERSION}"

  [ -d "${SKYBOX_SRC_DIR}" ] || die "cluster-tooling source directory not found: ${SKYBOX_SRC_DIR}"
  mkdir -p "${BUILD_DIR}"

  #if [ -n "${SKYBOX_PREBUILT_LIB}" ]; then
  #  [ -x "${SKYBOX_PREBUILT_LIB}" ] || die "SKYBOX_PREBUILT_LIB is not executable: ${SKYBOX_PREBUILT_LIB}"
  #  install -m0755 "${SKYBOX_PREBUILT_LIB}" "${SKYBOX_LIB}"
  #  verify_linux_binary_arch "${SKYBOX_LIB}"
  #  exit 0
  #fi

  repair_stale_podman_volumes

  if [ ! -d "${SKYBOX_SRC_DIR}/.git" ]; then
    "${ROOT_DIR}/scripts/fetch-components.sh"
  fi

  devcontainer_config="$(resolve_devcontainer_config)"
  devcontainer_config_path="$(prepare_devcontainer_config "${devcontainer_config}")"
  target_triple="$(resolve_target_triple)"
  devcontainer_uid="${SKYBOX_DEVCONTAINER_UID:-$(id -u)}"
  devcontainer_gid="${SKYBOX_DEVCONTAINER_GID:-1000}"
  if docker_cli_is_podman; then
    devcontainer_gid="${SKYBOX_DEVCONTAINER_GID:-$(id -g)}"
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
cargo build --locked -p skybox --release --target "${target_triple}"
# cargo test --locked -p skybox --test cli --target "${target_triple}"
cp -f "\${CARGO_TARGET_DIR:-target}/${target_triple}/release/libskybox.so" "${SKYBOX_OUT_REL}"
BUILD
  )

  case "${SKYBOX_BUILD_MODE}" in
    devcontainer)
      command -v devcontainer >/dev/null 2>&1 || die "need devcontainer CLI to build sarusctl"
      (
        cd "${SKYBOX_SRC_DIR}"
        "${devcontainer_env[@]}" devcontainer up \
          --remove-existing-container \
          --workspace-folder . \
          --config "${devcontainer_config_path}" >/dev/null
        cd /
        "${devcontainer_env[@]}" devcontainer exec \
          --workspace-folder "${SKYBOX_SRC_DIR}" \
          --config "${devcontainer_config_path}" \
          bash -lc "cd /workspaces/\$(basename \"${SKYBOX_SRC_DIR}\") && ${build_cmd}"
      )
      ;;
    host)
      (
        cd "${SKYBOX_SRC_DIR}"
        bash -lc "${build_cmd}"
      )
      ;;
    *)
      die "unsupported SKYBOX_BUILD_MODE: ${SKYBOX_BUILD_MODE}"
      ;;
  esac

  mkdir -p ${SKYBOX_BUILD_DIR}

  install -Dm0755 "${SKYBOX_SRC_DIR}/${SKYBOX_OUT_REL}" "${SKYBOX_BUILD_LIB}"
  [ -x "${SKYBOX_BUILD_LIB}" ] || die "missing skybox library: ${SKYBOX_BUILD_LIB}"
  verify_linux_binary_arch "${SKYBOX_BUILD_LIB}"
}

for VERSION in ${SKYBOX_SLURM_VERSIONS}
do
  export SLURM_VERSION="${VERSION}"
  echo "Building skybox for slurm ${SLURM_VERSION}"
  build_single_skybox ${SLURM_VERSION}
done

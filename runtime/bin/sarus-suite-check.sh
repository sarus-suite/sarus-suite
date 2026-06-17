#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[sarus-suite-check] %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_file() {
  [ -f "$1" ] || die "missing required file: $1"
}

check_cmd_path() {
  local name="$1"
  local resolved

  resolved="$(command -v "${name}")" || die "missing required command on PATH: ${name}"
  log "command ${name}: ${resolved}"
}

check_podman_info() {
  local info_output conmon_path runtime_name driver_name network_backend

  info_output="$(podman info --format '{{.Host.Conmon.Path}}|{{.Host.OCIRuntime.Name}}|{{.Store.GraphDriverName}}|{{.Host.NetworkBackend}}' 2>&1)" \
    || die "podman info failed: ${info_output}"

  IFS='|' read -r conmon_path runtime_name driver_name network_backend <<EOF
${info_output}
EOF

  log "podman conmon: ${conmon_path}"
  log "podman runtime: ${runtime_name}"
  log "podman storage driver: ${driver_name}"
  log "podman network backend: ${network_backend}"
}

main() {
  require_cmd podman
  require_cmd parallax
  require_cmd sarusctl

  : "${SARUS_SUITE_ROOT:?run this inside sarus-suite-shell or via 'sarus-suite-shell -- sarus-suite-check'}"
  : "${SARUS_SUITE_BIN:?missing SARUS_SUITE_BIN}"
  : "${XDG_CONFIG_HOME:?missing XDG_CONFIG_HOME}"
  : "${CONTAINERS_POLICY:?missing CONTAINERS_POLICY}"
  : "${PARALLAX_MP_CONFIG:?missing PARALLAX_MP_CONFIG}"
  : "${SARUSCTL_CONFIG_DIR:?missing SARUSCTL_CONFIG_DIR}"

  log "bundle root: ${SARUS_SUITE_ROOT}"
  log "bundle bin: ${SARUS_SUITE_BIN}"
  log "config home: ${XDG_CONFIG_HOME}"
  log "containers policy: ${CONTAINERS_POLICY}"
  log "parallax mount config: ${PARALLAX_MP_CONFIG}"
  log "sarusctl config dir: ${SARUSCTL_CONFIG_DIR}"

  require_file "${XDG_CONFIG_HOME}/containers/containers.conf"
  require_file "${XDG_CONFIG_HOME}/containers/storage.conf"
  require_file "${XDG_CONFIG_HOME}/containers/registries.conf"
  require_file "${XDG_CONFIG_HOME}/containers/containers.conf.modules/hpc"
  require_file "${CONTAINERS_POLICY}"
  require_file "${XDG_CONFIG_HOME}/containers/seccomp.json"
  require_file "${PARALLAX_MP_CONFIG}"
  require_file "${SARUSCTL_CONFIG_DIR}/90-sarus-suite-bundle.conf"

  check_cmd_path podman
  check_cmd_path parallax
  check_cmd_path sarusctl
  check_cmd_path crun
  check_cmd_path conmon
  check_cmd_path pasta
  check_cmd_path netavark
  check_cmd_path aardvark-dns
  check_cmd_path rootlessport
  check_cmd_path catatonit
  check_cmd_path mksquashfs
  check_cmd_path squashfuse_ll
  check_cmd_path fuse-overlayfs
  check_cmd_path fusermount3
  check_cmd_path inotifywait
  check_cmd_path rsync

  log "podman version: $(podman --version)"
  check_podman_info
  parallax --help >/dev/null
  log "parallax help: OK"
  sarusctl images >/dev/null
  log "sarusctl images: OK"
  log "check passed"
}

main "$@"

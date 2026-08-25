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

require_dir() {
  [ -d "$1" ] || die "missing required directory: $1"
}

require_executable() {
  [ -x "$1" ] || die "missing required executable: $1"
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
  local install_mode containers_config_dir sarusctl_config_file script_path

  # The system package has a fixed layout. Shell mode continues to provide
  # SARUS_SUITE_* through its environment, so no generated layout file is
  # needed for either installation mode.
  script_path=""
  if command -v readlink >/dev/null 2>&1; then
    script_path="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
  fi
  # In case this is an RPM install, we need to set the SARUS_SUITE_* env vars as needed by the shell
  if [ -z "${SARUS_SUITE_ROOT:-}" ] && [ "$script_path" = /opt/sarus-suite/bin/sarus-suite-check ]; then
    SARUS_SUITE_INSTALL_MODE=system
    SARUS_SUITE_ROOT=/opt/sarus-suite
    SARUS_SUITE_BIN=/opt/sarus-suite/bin
    SARUS_SUITE_HOOK_BIN=/opt/sarus-suite/libexec/oci/hooks
    SARUS_SUITE_ETC=/etc
  fi

  # we exit on error for missing settings
  : "${SARUS_SUITE_ROOT:?run inside sarus-suite-shell or install the Sarus Suite system package}"
  : "${SARUS_SUITE_BIN:?missing SARUS_SUITE_BIN}"
  : "${SARUS_SUITE_HOOK_BIN:?missing SARUS_SUITE_HOOK_BIN}"

  # setup if it is a system install/RPM vs shell via XDG
  install_mode="${SARUS_SUITE_INSTALL_MODE:-shell}"
  if [ "$install_mode" = "system" ]; then
    PATH="${SARUS_SUITE_BIN}:${PATH:-/usr/bin:/bin}"
    export PATH
    : "${SARUS_SUITE_ETC:?missing SARUS_SUITE_ETC for system installation}"
    containers_config_dir="${SARUS_SUITE_ETC}/containers"
    CONTAINERS_POLICY="${CONTAINERS_POLICY:-${containers_config_dir}/policy.json}"
    PARALLAX_MP_CONFIG="${PARALLAX_MP_CONFIG:-${SARUS_SUITE_ETC}/parallax-mount.conf}"
    SARUSCTL_CONFIG_DIR="${SARUSCTL_CONFIG_DIR:-${SARUS_SUITE_ETC}/sarus-suite}"
    sarusctl_config_file="${SARUSCTL_CONFIG_DIR}/90-sarusctl.conf"
  else
    : "${XDG_CONFIG_HOME:?missing XDG_CONFIG_HOME}"
    : "${CONTAINERS_POLICY:?missing CONTAINERS_POLICY}"
    : "${PARALLAX_MP_CONFIG:?missing PARALLAX_MP_CONFIG}"
    : "${SARUSCTL_CONFIG_DIR:?missing SARUSCTL_CONFIG_DIR}"
    containers_config_dir="${XDG_CONFIG_HOME}/containers"
    sarusctl_config_file="${SARUSCTL_CONFIG_DIR}/90-sarus-suite-bundle.conf"
  fi

  require_cmd podman
  require_cmd parallax
  require_cmd sarusctl
  require_cmd grep

  log "install mode: ${install_mode}"
  log "bundle root: ${SARUS_SUITE_ROOT}"
  log "bundle bin: ${SARUS_SUITE_BIN}"
  log "hook bin: ${SARUS_SUITE_HOOK_BIN}"
  log "containers config dir: ${containers_config_dir}"
  log "containers policy: ${CONTAINERS_POLICY}"
  log "parallax mount config: ${PARALLAX_MP_CONFIG}"
  log "sarusctl config dir: ${SARUSCTL_CONFIG_DIR}"

  require_file "${containers_config_dir}/containers.conf"
  require_file "${containers_config_dir}/storage.conf"
  require_file "${containers_config_dir}/registries.conf"
  require_file "${containers_config_dir}/containers.conf.modules/hpc"
  require_file "${CONTAINERS_POLICY}"
  require_file "${containers_config_dir}/seccomp.json"
  require_dir "${containers_config_dir}/oci/hooks.d"
  require_file "${containers_config_dir}/oci/hooks.d/10-ldcache.json"
  require_file "${containers_config_dir}/oci/hooks.d/20-mps.json"
  require_file "${containers_config_dir}/oci/hooks.d/30-pce.json"
  require_file "${containers_config_dir}/oci/hooks.d/40-pc-injection.json"
  require_file "${containers_config_dir}/oci/hooks.d/50-mkhomedir.json"
  require_file "${containers_config_dir}/oci/hooks.d/60-sethomevar.json"
  require_file "${PARALLAX_MP_CONFIG}"
  require_file "${sarusctl_config_file}"
  require_executable "${SARUS_SUITE_HOOK_BIN}/ldcache_hook"
  require_executable "${SARUS_SUITE_HOOK_BIN}/mps_hook"
  require_executable "${SARUS_SUITE_HOOK_BIN}/pce_hook"
  require_executable "${SARUS_SUITE_HOOK_BIN}/pc_injection_hook"
  require_executable "${SARUS_SUITE_HOOK_BIN}/mkhomedir"
  require_executable "${SARUS_SUITE_HOOK_BIN}/sethomevar"
  grep -Fq "\"path\": \"${SARUS_SUITE_HOOK_BIN}/ldcache_hook\"" "${containers_config_dir}/oci/hooks.d/10-ldcache.json" || die "ldcache hook config does not reference ${SARUS_SUITE_HOOK_BIN}/ldcache_hook"
  grep -Fq "\"path\": \"${SARUS_SUITE_HOOK_BIN}/mps_hook\"" "${containers_config_dir}/oci/hooks.d/20-mps.json" || die "mps hook config does not reference ${SARUS_SUITE_HOOK_BIN}/mps_hook"
  grep -Fq "\"path\": \"${SARUS_SUITE_HOOK_BIN}/pce_hook\"" "${containers_config_dir}/oci/hooks.d/30-pce.json" || die "pce hook config does not reference ${SARUS_SUITE_HOOK_BIN}/pce_hook"
  grep -Fq "\"path\": \"${SARUS_SUITE_HOOK_BIN}/pc_injection_hook\"" "${containers_config_dir}/oci/hooks.d/40-pc-injection.json" || die "pc-injection hook config does not reference ${SARUS_SUITE_HOOK_BIN}/pc_injection_hook"
  grep -Fq "\"path\": \"${SARUS_SUITE_HOOK_BIN}/mkhomedir\"" "${containers_config_dir}/oci/hooks.d/50-mkhomedir.json" || die "mkhomedir hook config does not reference ${SARUS_SUITE_HOOK_BIN}/mkhomedir"
  grep -Fq "\"path\": \"${SARUS_SUITE_HOOK_BIN}/sethomevar\"" "${containers_config_dir}/oci/hooks.d/60-sethomevar.json" || die "sethomevar hook config does not reference ${SARUS_SUITE_HOOK_BIN}/sethomevar"

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
  check_cmd_path bwrap
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

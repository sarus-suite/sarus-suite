#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  sarus-suite-shell [--parallax-store PATH] [--state-root PATH] [--bundle-root PATH] [-- COMMAND [ARGS...]]

Launch a subshell (or one command) with a private XDG config tree pointing
Podman and Parallax at the sarus-suite bundle and its helper binaries.
USAGE
}

log() {
  printf '[sarus-suite-shell] %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

render_template() {
  local src="$1"
  local dest="$2"
  local cdi_spec_dirs_line=""

  if [ -d "${BUNDLE_CDI_DIR}" ]; then
    cdi_spec_dirs_line="cdi_spec_dirs = [\"${BUNDLE_CDI_DIR}\"]"
  fi

  sed \
    -e "s|@@SARUS_SUITE_BIN@@|$(escape_sed_replacement "${SARUS_SUITE_BIN}")|g" \
    -e "s|@@SARUS_SUITE_HOOK_BIN@@|$(escape_sed_replacement "${SARUS_SUITE_HOOK_BIN}")|g" \
    -e "s|@@SARUS_SUITE_STATE@@|$(escape_sed_replacement "${SARUS_SUITE_STATE}")|g" \
    -e "s|@@SARUS_SUITE_RUNTIME@@|$(escape_sed_replacement "${SARUS_SUITE_RUNTIME}")|g" \
    -e "s|@@SARUS_SUITE_CONFIG@@|$(escape_sed_replacement "${SARUS_SUITE_CONFIG_HOME}")|g" \
    -e "s|@@SARUS_SUITE_PODMAN_ROOT@@|$(escape_sed_replacement "${SARUS_SUITE_PODMAN_ROOT}")|g" \
    -e "s|@@SARUS_SUITE_PODMAN_RUNROOT@@|$(escape_sed_replacement "${SARUS_SUITE_PODMAN_RUNROOT}")|g" \
    -e "s|@@SARUS_SUITE_PARALLAX_STORE@@|$(escape_sed_replacement "${SARUS_SUITE_PARALLAX_STORE}")|g" \
    -e "s|@@SARUS_SUITE_CDI_SPEC_DIRS@@|$(escape_sed_replacement "${cdi_spec_dirs_line}")|g" \
    "$src" > "$dest"
}

copy_if_present() {
  local src="$1"
  local dest="$2"

  if [ -f "$src" ]; then
    install -Dm0644 "$src" "$dest"
  fi
}

render_dir_templates_if_present() {
  local src="$1"
  local dest="$2"
  local entry
  local name

  if [ -d "$src" ]; then
    for entry in "$src"/*; do
      [ -f "$entry" ] || continue
      name="$(basename "$entry")"
      render_template "$entry" "$dest/$name"
    done
  fi
}

copy_tree_if_present() {
  local src="$1"
  local dest="$2"

  if [ -d "$src" ]; then
    install -d -m 0700 "$dest"
    cp -R "$src/." "$dest/"
  fi
}

write_rcfile() {
  local rcfile="$1"

  cat > "$rcfile" <<'RCFILE'
if [ -n "${SARUS_SUITE_OLD_PS1:-}" ]; then
  PS1="(sarus-suite) ${SARUS_SUITE_OLD_PS1}"
else
  PS1="(sarus-suite) \u@\h:\w\\$ "
fi

echo "sarus-suite shell active"
echo "  root:  ${SARUS_SUITE_ROOT}"
echo "  state: ${SARUS_SUITE_STATE}"
echo "  store: ${SARUS_SUITE_PARALLAX_STORE}"
RCFILE
}

PARALLAX_STORE_OVERRIDE=""
STATE_ROOT_OVERRIDE=""
BUNDLE_ROOT_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --parallax-store)
      [ $# -ge 2 ] || die "--parallax-store requires a path"
      PARALLAX_STORE_OVERRIDE="$2"
      shift 2
      ;;
    --state-root)
      [ $# -ge 2 ] || die "--state-root requires a path"
      STATE_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    --bundle-root)
      [ $# -ge 2 ] || die "--bundle-root requires a path"
      BUNDLE_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

require_cmd basename
require_cmd bash
require_cmd install
require_cmd sed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SARUS_SUITE_ROOT="${BUNDLE_ROOT_OVERRIDE:-$(cd "${SCRIPT_DIR}/.." && pwd -P)}"
SARUS_SUITE_BIN="${SARUS_SUITE_ROOT}/bin"
SARUS_SUITE_HOOK_BIN="${SARUS_SUITE_ROOT}/libexec/oci/hooks"
SARUS_SUITE_ETC="${SARUS_SUITE_ROOT}/etc"
BUNDLE_CDI_DIR="${SARUS_SUITE_ETC}/cdi"
BUNDLE_CONTAINERS_HOOKS_DIR="${SARUS_SUITE_ETC}/containers/oci/hooks.d"
BUNDLE_CONTAINERS_REGISTRIES_D_DIR="${SARUS_SUITE_ETC}/containers/registries.d"

[ -d "${SARUS_SUITE_BIN}" ] || die "bundle bin directory not found: ${SARUS_SUITE_BIN}"
[ -d "${SARUS_SUITE_ETC}/containers" ] || die "bundle containers config directory not found"
[ -d "${SARUS_SUITE_ETC}/parallax" ] || die "bundle parallax config directory not found"
[ -d "${SARUS_SUITE_ETC}/sarus-suite" ] || die "bundle sarus-suite config directory not found"

STATE_HOME_DEFAULT="${XDG_STATE_HOME:-${HOME}/.local/state}"
STATE_HOME="${STATE_ROOT_OVERRIDE:-${STATE_HOME_DEFAULT}/sarus-suite}"
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  RUNTIME_PARENT="${XDG_RUNTIME_DIR}"
  EFFECTIVE_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
else
  RUNTIME_PARENT="/tmp"
  EFFECTIVE_XDG_RUNTIME_DIR="/tmp/sarus-suite-${UID}/xdg-runtime"
fi

SARUS_SUITE_STATE="${STATE_HOME}"
SARUS_SUITE_RUNTIME="${RUNTIME_PARENT}/sarus-suite-${UID}"
SARUS_SUITE_CONFIG_HOME="${SARUS_SUITE_STATE}/config-home"
SARUS_SUITE_PODMAN_ROOT="${SARUS_SUITE_PODMAN_ROOT:-${SARUS_SUITE_STATE}/podman/root}"
SARUS_SUITE_PODMAN_RUNROOT="${SARUS_SUITE_PODMAN_RUNROOT:-${SARUS_SUITE_RUNTIME}/podman/runroot}"
SARUS_SUITE_PARALLAX_STORE="${PARALLAX_STORE_OVERRIDE:-${SARUS_SUITE_PARALLAX_STORE:-${SARUS_SUITE_STATE}/parallax/ro-store}}"
SARUS_SUITE_TMPDIR="${SARUS_SUITE_RUNTIME}/tmp"
SARUS_SUITE_OVERRIDE_BIN="${SARUS_SUITE_OVERRIDE_BIN:-}"

CONTAINERS_CONFIG_DIR="${SARUS_SUITE_CONFIG_HOME}/containers"
CONTAINERS_MODULES_DIR="${CONTAINERS_CONFIG_DIR}/containers.conf.modules"
CONTAINERS_HOOKS_DIR="${CONTAINERS_CONFIG_DIR}/oci/hooks.d"
CONTAINERS_REGISTRIES_D_DIR="${CONTAINERS_CONFIG_DIR}/registries.d"
PARALLAX_CONFIG_DIR="${SARUS_SUITE_CONFIG_HOME}/parallax"
SARUSCTL_PRIVATE_CONFIG_DIR="${SARUS_SUITE_CONFIG_HOME}/sarus-suite"
LEGACY_CONTAINERS_CONFIG_DIR="${HOME}/.config/containers"
LEGACY_CONTAINERS_MODULES_DIR="${LEGACY_CONTAINERS_CONFIG_DIR}/containers.conf.modules"
LEGACY_CONTAINERS_REGISTRIES_D_DIR="${LEGACY_CONTAINERS_CONFIG_DIR}/registries.d"
LEGACY_SARUSCTL_CONFIG_DIR="${HOME}/.config/sarus-suite"
RCFILE_PATH="${SARUS_SUITE_RUNTIME}/bashrc"

install -d -m 0700 "${SARUS_SUITE_STATE}" "${SARUS_SUITE_CONFIG_HOME}" "${CONTAINERS_CONFIG_DIR}" "${CONTAINERS_MODULES_DIR}" "${CONTAINERS_HOOKS_DIR}" "${CONTAINERS_REGISTRIES_D_DIR}" "${PARALLAX_CONFIG_DIR}" "${SARUSCTL_PRIVATE_CONFIG_DIR}"
install -d -m 0700 "${SARUS_SUITE_RUNTIME}" "${SARUS_SUITE_TMPDIR}" "${SARUS_SUITE_PODMAN_RUNROOT}"
install -d -m 0700 "$(dirname "${SARUS_SUITE_PODMAN_ROOT}")" "${SARUS_SUITE_PODMAN_ROOT}" "${SARUS_SUITE_PARALLAX_STORE}" "${SARUS_SUITE_STATE}/logs"
install -d -m 0700 "${LEGACY_CONTAINERS_CONFIG_DIR}" "${LEGACY_CONTAINERS_MODULES_DIR}" "${LEGACY_CONTAINERS_REGISTRIES_D_DIR}" "${LEGACY_SARUSCTL_CONFIG_DIR}"

if [ "${EFFECTIVE_XDG_RUNTIME_DIR}" = "${SARUS_SUITE_RUNTIME}/xdg-runtime" ]; then
  install -d -m 0700 "${EFFECTIVE_XDG_RUNTIME_DIR}"
fi

render_template "${SARUS_SUITE_ETC}/containers/containers.conf" "${CONTAINERS_CONFIG_DIR}/containers.conf"
render_template "${SARUS_SUITE_ETC}/containers/storage.conf" "${CONTAINERS_CONFIG_DIR}/storage.conf"
render_template "${SARUS_SUITE_ETC}/parallax/parallax-mount.conf" "${PARALLAX_CONFIG_DIR}/parallax-mount.conf"
render_template "${SARUS_SUITE_ETC}/sarus-suite/90-sarusctl.conf" "${SARUSCTL_PRIVATE_CONFIG_DIR}/90-sarusctl.conf"

copy_if_present "${SARUS_SUITE_ETC}/containers/registries.conf" "${CONTAINERS_CONFIG_DIR}/registries.conf"
copy_if_present "${SARUS_SUITE_ETC}/containers/policy.json" "${CONTAINERS_CONFIG_DIR}/policy.json"
copy_if_present "${SARUS_SUITE_ETC}/containers/seccomp.json" "${CONTAINERS_CONFIG_DIR}/seccomp.json"
copy_if_present "${SARUS_SUITE_ETC}/containers/containers.conf.modules/hpc" "${CONTAINERS_MODULES_DIR}/hpc"
copy_tree_if_present "${BUNDLE_CONTAINERS_REGISTRIES_D_DIR}" "${CONTAINERS_REGISTRIES_D_DIR}"
render_dir_templates_if_present "${BUNDLE_CONTAINERS_HOOKS_DIR}" "${CONTAINERS_HOOKS_DIR}"

# Some Podman code paths still consult ~/.config/containers directly for policy.json.
copy_if_present "${CONTAINERS_CONFIG_DIR}/registries.conf" "${LEGACY_CONTAINERS_CONFIG_DIR}/registries.conf"
copy_if_present "${CONTAINERS_CONFIG_DIR}/seccomp.json" "${LEGACY_CONTAINERS_CONFIG_DIR}/seccomp.json"
copy_if_present "${CONTAINERS_MODULES_DIR}/hpc" "${LEGACY_CONTAINERS_MODULES_DIR}/hpc"
copy_tree_if_present "${CONTAINERS_REGISTRIES_D_DIR}" "${LEGACY_CONTAINERS_REGISTRIES_D_DIR}"
copy_if_present "${SARUSCTL_PRIVATE_CONFIG_DIR}/90-sarusctl.conf" "${LEGACY_SARUSCTL_CONFIG_DIR}/90-sarus-suite-bundle.conf"
if [ ! -f "${LEGACY_CONTAINERS_CONFIG_DIR}/policy.json" ] && [ ! -f /etc/containers/policy.json ]; then
  copy_if_present "${CONTAINERS_CONFIG_DIR}/policy.json" "${LEGACY_CONTAINERS_CONFIG_DIR}/policy.json"
  log "injected compatibility policy.json into ${LEGACY_CONTAINERS_CONFIG_DIR}"
fi

write_rcfile "${RCFILE_PATH}"

if [ -n "${SARUS_SUITE_OVERRIDE_BIN}" ]; then
  PATH="${SARUS_SUITE_OVERRIDE_BIN}:${SARUS_SUITE_BIN}:${PATH}"
else
  PATH="${SARUS_SUITE_BIN}:${PATH}"
fi

export SARUS_SUITE_ROOT
export SARUS_SUITE_BIN
export SARUS_SUITE_HOOK_BIN
export SARUS_SUITE_ETC
export SARUS_SUITE_STATE
export SARUS_SUITE_RUNTIME
export SARUS_SUITE_CONFIG_HOME
export SARUS_SUITE_PODMAN_ROOT
export SARUS_SUITE_PODMAN_RUNROOT
export SARUS_SUITE_PARALLAX_STORE
export SARUS_SUITE_OVERRIDE_BIN
export PARALLAX_MP_CONFIG="${PARALLAX_CONFIG_DIR}/parallax-mount.conf"
export CONTAINERS_POLICY="${CONTAINERS_CONFIG_DIR}/policy.json"
export SARUSCTL_CONFIG_DIR="${LEGACY_SARUSCTL_CONFIG_DIR}"
export XDG_CONFIG_HOME="${SARUS_SUITE_CONFIG_HOME}"
export XDG_RUNTIME_DIR="${EFFECTIVE_XDG_RUNTIME_DIR}"
export TMPDIR="${SARUS_SUITE_TMPDIR}"
export PATH
export SARUS_SUITE_OLD_PS1="${PS1-}"

if [ $# -gt 0 ]; then
  exec "$@"
fi

log "entering bash with private XDG_CONFIG_HOME=${XDG_CONFIG_HOME}"
exec bash --noprofile --rcfile "${RCFILE_PATH}" -i

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  sarus-suite-system-install [OPTIONS]

Install a sarus-suite bundle into system locations. Writing requires root; a
dry run may be performed as an unprivileged user. The installer preflights all
destination collisions and prints a complete change report when it finishes.

Options:
  --bundle-root DIR       Bundle to install (default: parent of this script)
  --prefix DIR            Installation prefix (default: /usr/local)
  --bin-dir DIR           Command directory (default: PREFIX/bin)
  --libexec-dir DIR       OCI hook directory
                          (default: PREFIX/libexec/sarus-suite/oci/hooks)
  --state-dir DIR         Use DIR/parallax/ro-store as a legacy shared store
                          unless --parallax-store is also supplied
  --parallax-store PATH   Parallax image store. The default is per-user:
                          $HOME/.sarus-suite/ro-store
  --report FILE           Persistent install report
                          (default: /var/log/sarus-suite-install-report.txt)
  --install-root DIR      Prepend DIR to destinations for staging/testing
  --force                 Replace differing regular files
  --dry-run               Validate and report without changing the system
  -h, --help              Show this help

System configuration is installed below /etc. A profile fragment adds BIN_DIR
to PATH for future login shells; the runtime itself uses native system config
locations and does not require sarus-suite-shell.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_absolute_path() {
  local name="$1"
  local path="$2"

  case "$path" in
    /*) ;;
    *) die "${name} must be an absolute path: ${path}" ;;
  esac
  case "$path" in
    *$'\n'*|*/../*|*/..) die "unsafe ${name}: ${path}" ;;
  esac
}

is_per_user_store_path() {
  case "$1" in
    '$HOME/'*|'${HOME}/'*) return 0 ;;
    *) return 1 ;;
  esac
}

strip_trailing_slash() {
  local path="$1"

  while [ "$path" != "/" ] && [ "${path%/}" != "$path" ]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

stage_path() {
  local logical_path="$1"

  if [ -n "${INSTALL_ROOT}" ]; then
    printf '%s%s\n' "${INSTALL_ROOT}" "${logical_path}"
  else
    printf '%s\n' "${logical_path}"
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

shell_quote() {
  local escaped

  escaped="$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  printf "'%s'" "$escaped"
}

render_template() {
  local src="$1"
  local dest="$2"
  local cdi_spec_dirs_line=""

  if [ -d "${BUNDLE_ROOT}/etc/cdi" ]; then
    cdi_spec_dirs_line="cdi_spec_dirs = [\"/etc/cdi\"]"
  fi

  sed \
    -e "s|@@SARUS_SUITE_BIN@@|$(escape_sed_replacement "${BIN_DIR}")|g" \
    -e "s|@@SARUS_SUITE_HOOK_BIN@@|$(escape_sed_replacement "${LIBEXEC_DIR}")|g" \
    -e "s|@@SARUS_SUITE_CONFIG@@|/etc|g" \
    -e "s|@@SARUS_SUITE_PARALLAX_STORE@@|$(escape_sed_replacement "${PARALLAX_STORE}")|g" \
    -e "s|@@SARUS_SUITE_CDI_SPEC_DIRS@@|$(escape_sed_replacement "${cdi_spec_dirs_line}")|g" \
    "$src" > "$dest"
}

record() {
  printf '%-14s %s\n' "$1" "$2" >> "${WORK_REPORT}"
}

add_file() {
  SOURCES+=("$1")
  DESTINATIONS+=("$(stage_path "$2")")
  MODES+=("$3")
}

add_tree() {
  local src_root="$1"
  local dest_root="$2"
  local mode="$3"
  local src
  local relative

  [ -d "$src_root" ] || return 0
  while IFS= read -r src; do
    relative="${src#${src_root}/}"
    add_file "$src" "${dest_root}/${relative}" "$mode"
  done < <(find "$src_root" -type f -print | sort)
}

check_parent_chain() {
  local path="$1"
  local parent

  parent="$(dirname "$path")"
  [ "$parent" = "/" ] && return 0
  if [ -e "$parent" ] || [ -L "$parent" ]; then
    [ -d "$parent" ] || die "destination parent is not a directory: ${parent}"
    return 0
  fi
  check_parent_chain "$parent"
}

file_mode() {
  stat -c '%a' "$1"
}

preflight_file() {
  local src="$1"
  local dest="$2"
  local mode="$3"
  local desired_mode="${mode#0}"

  check_parent_chain "$dest"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    [ -f "$dest" ] && [ ! -L "$dest" ] || die "refusing to replace non-regular path: ${dest}"
    if ! cmp -s "$src" "$dest" || [ "$(file_mode "$dest")" != "$desired_mode" ]; then
      [ "${FORCE}" -eq 1 ] || die "destination differs (use --force to replace): ${dest}"
    fi
  fi
}

ensure_directory() {
  local path="$1"
  local mode="${2:-0755}"
  local parent

  if [ -n "${REPORTED_DIRS[$path]+present}" ]; then
    return 0
  fi
  REPORTED_DIRS["$path"]=1

  if [ -d "$path" ]; then
    record "UNCHANGED" "directory ${path}"
    return 0
  fi
  [ ! -e "$path" ] && [ ! -L "$path" ] || die "cannot create directory over existing path: ${path}"
  parent="$(dirname "$path")"
  if [ "$parent" != "$path" ] && [ ! -d "$parent" ]; then
    ensure_directory "$parent" 0755
  fi
  if [ "${DRY_RUN}" -eq 1 ]; then
    record "WOULD_CREATE" "directory ${path} mode=${mode}"
  else
    install -d -m "$mode" "$path"
    record "CREATED" "directory ${path} mode=${mode}"
  fi
}

install_file() {
  local src="$1"
  local dest="$2"
  local mode="$3"
  local desired_mode="${mode#0}"
  local action="CREATED"

  ensure_directory "$(dirname "$dest")" 0755
  if [ -f "$dest" ]; then
    if cmp -s "$src" "$dest" && [ "$(file_mode "$dest")" = "$desired_mode" ]; then
      record "UNCHANGED" "file ${dest} mode=${mode}"
      return 0
    fi
    action="UPDATED"
  fi

  if [ "${DRY_RUN}" -eq 1 ]; then
    if [ "$action" = "CREATED" ]; then
      record "WOULD_CREATE" "file ${dest} mode=${mode}"
    else
      record "WOULD_UPDATE" "file ${dest} mode=${mode}"
    fi
  else
    install -m "$mode" "$src" "$dest"
    record "$action" "file ${dest} mode=${mode}"
  fi
}

BUNDLE_ROOT_OVERRIDE=""
PREFIX="/usr/local"
BIN_DIR_OVERRIDE=""
LIBEXEC_DIR_OVERRIDE=""
STATE_DIR="/var/lib/sarus-suite"
STATE_DIR_SET=0
PARALLAX_STORE='${HOME}/.sarus-suite/ro-store'
PARALLAX_STORE_SET=0
REPORT_FILE="/var/log/sarus-suite-install-report.txt"
INSTALL_ROOT=""
FORCE=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle-root)
      [ $# -ge 2 ] || die "--bundle-root requires a directory"
      BUNDLE_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    --prefix)
      [ $# -ge 2 ] || die "--prefix requires a directory"
      PREFIX="$2"
      shift 2
      ;;
    --bin-dir)
      [ $# -ge 2 ] || die "--bin-dir requires a directory"
      BIN_DIR_OVERRIDE="$2"
      shift 2
      ;;
    --libexec-dir)
      [ $# -ge 2 ] || die "--libexec-dir requires a directory"
      LIBEXEC_DIR_OVERRIDE="$2"
      shift 2
      ;;
    --state-dir)
      [ $# -ge 2 ] || die "--state-dir requires a directory"
      STATE_DIR="$2"
      STATE_DIR_SET=1
      shift 2
      ;;
    --parallax-store)
      [ $# -ge 2 ] || die "--parallax-store requires a directory"
      PARALLAX_STORE="$2"
      PARALLAX_STORE_SET=1
      shift 2
      ;;
    --report)
      [ $# -ge 2 ] || die "--report requires a file"
      REPORT_FILE="$2"
      shift 2
      ;;
    --install-root)
      [ $# -ge 2 ] || die "--install-root requires a directory"
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

require_cmd basename
require_cmd cmp
require_cmd date
require_cmd dirname
require_cmd find
require_cmd install
require_cmd mktemp
require_cmd sed
require_cmd sort
require_cmd stat

[ "$(uname -s)" = "Linux" ] || die "system installation is supported only on Linux"
if [ "${EUID}" -ne 0 ] && [ "${DRY_RUN}" -ne 1 ]; then
  die "sarus-suite-system-install must run as root"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUNDLE_ROOT="$(strip_trailing_slash "${BUNDLE_ROOT_OVERRIDE:-$(cd "${SCRIPT_DIR}/.." && pwd -P)}")"
PREFIX="$(strip_trailing_slash "$PREFIX")"
if [ "$PREFIX" = "/" ]; then
  DEFAULT_BIN_DIR="/bin"
  DEFAULT_LIBEXEC_DIR="/libexec/sarus-suite/oci/hooks"
else
  DEFAULT_BIN_DIR="${PREFIX}/bin"
  DEFAULT_LIBEXEC_DIR="${PREFIX}/libexec/sarus-suite/oci/hooks"
fi
BIN_DIR="$(strip_trailing_slash "${BIN_DIR_OVERRIDE:-${DEFAULT_BIN_DIR}}")"
LIBEXEC_DIR="$(strip_trailing_slash "${LIBEXEC_DIR_OVERRIDE:-${DEFAULT_LIBEXEC_DIR}}")"
STATE_DIR="$(strip_trailing_slash "$STATE_DIR")"
if [ "$STATE_DIR_SET" -eq 1 ] && [ "$PARALLAX_STORE_SET" -eq 0 ]; then
  PARALLAX_STORE="${STATE_DIR}/parallax/ro-store"
fi
PARALLAX_STORE="$(strip_trailing_slash "$PARALLAX_STORE")"
REPORT_FILE="$(strip_trailing_slash "$REPORT_FILE")"
if [ -n "$INSTALL_ROOT" ]; then
  INSTALL_ROOT="$(strip_trailing_slash "$INSTALL_ROOT")"
  [ "$INSTALL_ROOT" != "/" ] || INSTALL_ROOT=""
fi

require_absolute_path --bundle-root "$BUNDLE_ROOT"
require_absolute_path --prefix "$PREFIX"
require_absolute_path --bin-dir "$BIN_DIR"
require_absolute_path --libexec-dir "$LIBEXEC_DIR"
require_absolute_path --state-dir "$STATE_DIR"
if ! is_per_user_store_path "$PARALLAX_STORE"; then
  require_absolute_path --parallax-store "$PARALLAX_STORE"
fi
require_absolute_path --report "$REPORT_FILE"
[ -z "$INSTALL_ROOT" ] || require_absolute_path --install-root "$INSTALL_ROOT"
[ "$BIN_DIR" != "/" ] || die "--bin-dir cannot be the filesystem root"
[ "$LIBEXEC_DIR" != "/" ] || die "--libexec-dir cannot be the filesystem root"
[ "$STATE_DIR" != "/" ] || die "--state-dir cannot be the filesystem root"
[ "$PARALLAX_STORE" != "/" ] || die "--parallax-store cannot be the filesystem root"
[ "$REPORT_FILE" != "/" ] || die "--report cannot be the filesystem root"

BUNDLE_BIN="${BUNDLE_ROOT}/bin"
BUNDLE_ETC="${BUNDLE_ROOT}/etc"
BUNDLE_HOOK_BIN="${BUNDLE_ROOT}/libexec/oci/hooks"
SYSTEM_TEMPLATE_DIR="${BUNDLE_ETC}/system"
[ -d "$BUNDLE_BIN" ] || die "bundle bin directory not found: ${BUNDLE_BIN}"
[ -d "$BUNDLE_HOOK_BIN" ] || die "bundle hook directory not found: ${BUNDLE_HOOK_BIN}"
[ -f "${SYSTEM_TEMPLATE_DIR}/containers/containers.conf" ] || die "system templates not found in bundle"
[ -f "${BUNDLE_ETC}/containers/policy.json" ] || die "bundle policy.json not found"
[ -f "${BUNDLE_ETC}/containers/seccomp.json" ] || die "bundle seccomp.json not found"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sarus-suite-system-install.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT INT TERM
WORK_REPORT="${WORK_DIR}/install-report.txt"
mkdir -p "${WORK_DIR}/rendered/containers/oci/hooks.d" "${WORK_DIR}/rendered/sarus-suite"

cat > "$WORK_REPORT" <<REPORT_HEADER
Sarus Suite system install report
timestamp_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
bundle_root=${BUNDLE_ROOT}
install_root=${INSTALL_ROOT:-/}
prefix=${PREFIX}
bin_dir=${BIN_DIR}
libexec_dir=${LIBEXEC_DIR}
state_dir=${STATE_DIR}
parallax_store=${PARALLAX_STORE}
dry_run=${DRY_RUN}

Changes:
REPORT_HEADER

render_template "${SYSTEM_TEMPLATE_DIR}/containers/containers.conf" "${WORK_DIR}/rendered/containers/containers.conf"
render_template "${SYSTEM_TEMPLATE_DIR}/containers/storage.conf" "${WORK_DIR}/rendered/containers/storage.conf"
render_template "${SYSTEM_TEMPLATE_DIR}/parallax-mount.conf" "${WORK_DIR}/rendered/parallax-mount.conf"
render_template "${SYSTEM_TEMPLATE_DIR}/90-sarusctl.conf" "${WORK_DIR}/rendered/sarus-suite/90-sarusctl.conf"
for template in "${BUNDLE_ETC}/containers/oci/hooks.d"/*; do
  [ -f "$template" ] || continue
  render_template "$template" "${WORK_DIR}/rendered/containers/oci/hooks.d/$(basename "$template")"
done

quoted_bin_dir="$(shell_quote "$BIN_DIR")"
cat > "${WORK_DIR}/profile.sh" <<PROFILE
# Installed by sarus-suite-system-install.
_sarus_suite_bin=${quoted_bin_dir}
case ":\${PATH:-}:" in
  *":\${_sarus_suite_bin}:"*) ;;
  *) PATH="\${_sarus_suite_bin}\${PATH:+:\${PATH}}"; export PATH ;;
esac
unset _sarus_suite_bin
PROFILE

quoted_prefix="$(shell_quote "$PREFIX")"
quoted_bin_dir="$(shell_quote "$BIN_DIR")"
quoted_libexec_dir="$(shell_quote "$LIBEXEC_DIR")"
quoted_state_dir="$(shell_quote "$STATE_DIR")"
quoted_store="$(shell_quote "$PARALLAX_STORE")"
cat > "${WORK_DIR}/install-layout" <<LAYOUT
# Installed by sarus-suite-system-install; sourced by sarus-suite-check.
SARUS_SUITE_INSTALL_MODE=system
SARUS_SUITE_ROOT=${quoted_prefix}
SARUS_SUITE_BIN=${quoted_bin_dir}
SARUS_SUITE_HOOK_BIN=${quoted_libexec_dir}
SARUS_SUITE_ETC=/etc
SARUS_SUITE_STATE=${quoted_state_dir}
SARUS_SUITE_PARALLAX_STORE=${quoted_store}
LAYOUT

SOURCES=()
DESTINATIONS=()
MODES=()
declare -A REPORTED_DIRS=()

for src in "${BUNDLE_BIN}"/*; do
  [ -f "$src" ] || continue
  [ -x "$src" ] || die "bundle bin entry is not executable: ${src}"
  mode=0755
  [ "$(basename "$src")" != "fusermount3" ] || mode=4755
  add_file "$src" "${BIN_DIR}/$(basename "$src")" "$mode"
done
add_tree "$BUNDLE_HOOK_BIN" "$LIBEXEC_DIR" 0755
add_file "${WORK_DIR}/rendered/containers/containers.conf" /etc/containers/containers.conf 0644
add_file "${WORK_DIR}/rendered/containers/storage.conf" /etc/containers/storage.conf 0644
add_file "${BUNDLE_ETC}/containers/registries.conf" /etc/containers/registries.conf 0644
add_file "${BUNDLE_ETC}/containers/policy.json" /etc/containers/policy.json 0644
add_file "${BUNDLE_ETC}/containers/seccomp.json" /etc/containers/seccomp.json 0644
add_file "${BUNDLE_ETC}/containers/containers.conf.modules/hpc" /etc/containers/containers.conf.modules/hpc 0644
add_tree "${WORK_DIR}/rendered/containers/oci/hooks.d" /etc/containers/oci/hooks.d 0644
add_tree "${BUNDLE_ETC}/containers/registries.d" /etc/containers/registries.d 0644
add_tree "${BUNDLE_ETC}/cdi" /etc/cdi 0644
add_file "${WORK_DIR}/rendered/parallax-mount.conf" /etc/parallax-mount.conf 0644
add_file "${WORK_DIR}/rendered/sarus-suite/90-sarusctl.conf" /etc/sarus-suite/90-sarusctl.conf 0644
add_file "${WORK_DIR}/install-layout" /etc/sarus-suite/install-layout 0644
add_file "${WORK_DIR}/profile.sh" /etc/profile.d/sarus-suite.sh 0644
add_tree "${BUNDLE_ROOT}/examples" "${PREFIX}/share/sarus-suite/examples" 0644
add_tree "${BUNDLE_ROOT}/share" "${PREFIX}/share/sarus-suite" 0644

for ((i = 0; i < ${#SOURCES[@]}; i++)); do
  preflight_file "${SOURCES[$i]}" "${DESTINATIONS[$i]}" "${MODES[$i]}"
done

report_dest="$(stage_path "$REPORT_FILE")"
check_parent_chain "$report_dest"
if [ -e "$report_dest" ] || [ -L "$report_dest" ]; then
  [ -f "$report_dest" ] && [ ! -L "$report_dest" ] || die "refusing to replace non-regular report path: ${report_dest}"
fi

if is_per_user_store_path "$PARALLAX_STORE"; then
  record "DEFERRED" "per-user Parallax store ${PARALLAX_STORE} (created by sarusctl for each user)"
else
  ensure_directory "$(stage_path "$PARALLAX_STORE")" 0755
fi
for ((i = 0; i < ${#SOURCES[@]}; i++)); do
  install_file "${SOURCES[$i]}" "${DESTINATIONS[$i]}" "${MODES[$i]}"
done

ensure_directory "$(dirname "$report_dest")" 0755
if [ "${DRY_RUN}" -eq 1 ]; then
  record "WOULD_WRITE" "report ${report_dest} mode=0644"
else
  if [ -f "$report_dest" ]; then
    record "UPDATED" "report ${report_dest} mode=0644"
  else
    record "CREATED" "report ${report_dest} mode=0644"
  fi
  install -m 0644 "$WORK_REPORT" "$report_dest"
fi

printf '\n'
cat "$WORK_REPORT"
if [ "${DRY_RUN}" -eq 0 ]; then
  if [ -n "$INSTALL_ROOT" ]; then
    printf '\nInstallation staged below %s; the live system was not activated.\n' "$INSTALL_ROOT"
  else
    printf '\nInstallation complete. Start a new login shell or add %s to the current PATH.\n' "$BIN_DIR"
  fi
  printf 'Persistent report: %s\n' "$report_dest"
else
  printf '\nDry run complete; no system files were changed.\n'
fi

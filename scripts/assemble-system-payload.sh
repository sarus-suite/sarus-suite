#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  assemble-system-payload.sh --bundle-root DIR --output-dir DIR [OPTIONS]

Converts a portable bundle into the exact directory tree that an RPM will own.
This is a step needed prior building the RPM, and builds
an unprivileged, fixed-layout filesystem tree suitable for packaging.
Paths written into configuration are logical target paths; OUTPUT_DIR is only
the staging root.

Options:
  --bundle-root DIR       Assembled Sarus Suite bundle
  --output-dir DIR        New or empty payload directory
  --parallax-store PATH   Per-user image store expression
                          (default: ${HOME}/.sarus-suite/ro-store)
  --import-binary SPEC    Replace PATH[:NAME] in the payload; repeatable
  --import-hook-dir DIR   Replace hooks with executable files from DIR and
                          mirror them into the suite bin directory; repeatable
  -h, --help              Show this help
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

strip_trailing_slash() {
  local path="$1"
  while [ "$path" != "/" ] && [ "${path%/}" != "$path" ]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
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

validate_name() {
  local name="$1"
  [ -n "$name" ] || die "import destination name cannot be empty"
  [ "$name" != "." ] && [ "$name" != ".." ] || die "unsafe import name: ${name}"
  case "$name" in
    */*|*$'\n'*) die "unsafe import name: ${name}" ;;
  esac
}

contains_name() {
  local wanted="$1"
  shift
  local candidate
  for candidate in "$@"; do
    [ "$candidate" != "$wanted" ] || return 0
  done
  return 1
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

stage_path() {
  printf '%s%s\n' "$OUTPUT_DIR" "$1"
}

copy_file() {
  local src="$1"
  local logical_dest="$2"
  local mode="$3"
  local dest
  dest="$(stage_path "$logical_dest")"
  install -d -m 0755 "$(dirname "$dest")"
  install -m "$mode" "$src" "$dest"
  chmod "$mode" "$dest"
}

copy_tree() {
  local src_root="$1"
  local logical_dest="$2"
  local mode="$3"
  local src relative
  [ -d "$src_root" ] || return 0
  while IFS= read -r src; do
    relative="${src#${src_root}/}"
    copy_file "$src" "${logical_dest}/${relative}" "$mode"
  done < <(find "$src_root" -type f -print | sort)
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | sed 's/[[:space:]].*$//'
  else
    shasum -a 256 "$1" | sed 's/[[:space:]].*$//'
  fi
}

canonical_source_path() {
  local path="$1"
  local directory filename canonical

  case "$path" in
    *$'\n'*) die "import source path contains a newline: ${path}" ;;
  esac
  directory="$(dirname "$path")"
  filename="$(basename "$path")"
  canonical="$(cd "$directory" && pwd -P)/${filename}" || die "cannot resolve import source: ${path}"
  case "$canonical" in
    *$'\n'*) die "import source path contains a newline: ${path}" ;;
  esac
  printf '%s\n' "$canonical"
}

render_template() {
  local src="$1"
  local dest="$2"
  local cdi_line=""
  if [ -d "${BUNDLE_ROOT}/etc/cdi" ]; then
    cdi_line='cdi_spec_dirs = ["/etc/cdi"]'
  fi
  install -d -m 0755 "$(dirname "$dest")"
  sed \
    -e "s|@@SARUS_SUITE_BIN@@|$(escape_sed_replacement "$BIN_DIR")|g" \
    -e "s|@@SARUS_SUITE_HOOK_BIN@@|$(escape_sed_replacement "$HOOK_DIR")|g" \
    -e 's|@@SARUS_SUITE_CONFIG@@|/etc|g' \
    -e "s|@@SARUS_SUITE_PARALLAX_STORE@@|$(escape_sed_replacement "$PARALLAX_STORE")|g" \
    -e "s|@@SARUS_SUITE_CDI_SPEC_DIRS@@|$(escape_sed_replacement "$cdi_line")|g" \
    -e 's|@@SARUS_SUITE_PODMAN_GRAPHROOT_LINE@@||g' \
    -e 's|@@SARUS_SUITE_PODMAN_RUNROOT_LINE@@||g' \
    -e 's|@@SARUS_SUITE_PODMAN_STORAGE_OPTIONS_HEADER@@||g' \
    -e 's|@@SARUS_SUITE_PODMAN_ADDITIONAL_IMAGESTORES_LINE@@||g' \
    -e 's|@@SARUS_SUITE_PARALLAX_TMPDIR_LINE@@||g' \
    -e 's|@@SARUS_SUITE_PARALLAX_LOGFILE_LINE@@||g' \
    -e 's|@@SARUS_SUITE_PARALLAX_MP_LOGFILE_LINE@@||g' \
    -e 's|@@SARUS_SUITE_PODMAN_TMP_PATH_LINE@@||g' \
    "$src" > "$dest"
  chmod 0644 "$dest"
}

register_binary() {
  local spec="$1"
  local src name bundled_path
  case "$spec" in
    *:*) src="${spec%%:*}"; name="${spec##*:}" ;;
    *) src="$spec"; name="$(basename "$src")" ;;
  esac
  [ -f "$src" ] || die "import binary not found: ${src}"
  [ -x "$src" ] || die "import binary is not executable: ${src}"
  validate_name "$name"
  bundled_path="${BUNDLE_ROOT}/bin/${name}"
  [ -f "$bundled_path" ] && [ -x "$bundled_path" ] || die "imported binary does not replace a bundled executable: ${name}"
  contains_name "$name" "${IMPORT_BINARY_NAMES[@]}" && die "duplicate imported binary: ${name}"
  contains_name "$name" "${IMPORT_HOOK_NAMES[@]}" && die "imported binary conflicts with hook: ${name}"
  src="$(canonical_source_path "$src")"
  IMPORT_BINARY_NAMES+=("$name")
  IMPORT_BINARY_PATHS+=("$src")
}

register_hook_dir() {
  local dir="$1"
  local src name bundled_hook bundled_binary
  [ -d "$dir" ] || die "import hook dir not found: ${dir}"
  for src in "$dir"/*; do
    [ -f "$src" ] && [ -x "$src" ] || continue
    name="$(basename "$src")"
    validate_name "$name"
    bundled_hook="${BUNDLE_ROOT}/libexec/oci/hooks/${name}"
    bundled_binary="${BUNDLE_ROOT}/bin/${name}"
    [ -f "$bundled_hook" ] && [ -x "$bundled_hook" ] && [ -f "$bundled_binary" ] && [ -x "$bundled_binary" ] || die "imported hook does not replace a bundled hook: ${name}"
    contains_name "$name" "${IMPORT_HOOK_NAMES[@]}" && die "duplicate imported hook: ${name}"
    contains_name "$name" "${IMPORT_BINARY_NAMES[@]}" && die "imported hook conflicts with binary: ${name}"
    src="$(canonical_source_path "$src")"
    IMPORT_HOOK_NAMES+=("$name")
    IMPORT_HOOK_PATHS+=("$src")
  done
}

BUNDLE_ROOT=""
OUTPUT_DIR=""
PREFIX="/opt/sarus-suite"
PARALLAX_STORE='${HOME}/.sarus-suite/ro-store'
IMPORT_BINARY_SPECS=()
IMPORT_HOOK_DIRS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle-root) [ $# -ge 2 ] || die "--bundle-root requires a directory"; BUNDLE_ROOT="$2"; shift 2 ;;
    --output-dir) [ $# -ge 2 ] || die "--output-dir requires a directory"; OUTPUT_DIR="$2"; shift 2 ;;
    --parallax-store) [ $# -ge 2 ] || die "--parallax-store requires a path"; PARALLAX_STORE="$2"; shift 2 ;;
    --import-binary) [ $# -ge 2 ] || die "--import-binary requires PATH[:NAME]"; IMPORT_BINARY_SPECS+=("$2"); shift 2 ;;
    --import-hook-dir) [ $# -ge 2 ] || die "--import-hook-dir requires a directory"; IMPORT_HOOK_DIRS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -n "$BUNDLE_ROOT" ] || die "--bundle-root is required"
[ -n "$OUTPUT_DIR" ] || die "--output-dir is required"
require_cmd basename
require_cmd find
require_cmd grep
require_cmd install
require_cmd sed
require_cmd sort
if ! command -v sha256sum >/dev/null 2>&1; then
  require_cmd shasum
fi

BUNDLE_ROOT="$(strip_trailing_slash "$BUNDLE_ROOT")"
OUTPUT_DIR="$(strip_trailing_slash "$OUTPUT_DIR")"
require_absolute_path --bundle-root "$BUNDLE_ROOT"
require_absolute_path --output-dir "$OUTPUT_DIR"
[ "$OUTPUT_DIR" != "/" ] || die "--output-dir cannot be the filesystem root"
case "$PARALLAX_STORE" in
  '$HOME/'*|'${HOME}/'*) ;;
  *) require_absolute_path --parallax-store "$PARALLAX_STORE" ;;
esac

[ -d "${BUNDLE_ROOT}/bin" ] || die "bundle bin directory not found: ${BUNDLE_ROOT}/bin"
[ -d "${BUNDLE_ROOT}/libexec/oci/hooks" ] || die "bundle hook directory not found"
[ -f "${BUNDLE_ROOT}/etc/containers/containers.conf" ] || die "bundle containers.conf not found"
[ -f "${BUNDLE_ROOT}/etc/containers/storage.conf" ] || die "bundle storage.conf not found"
[ -f "${BUNDLE_ROOT}/etc/parallax/parallax-mount.conf" ] || die "bundle parallax-mount.conf not found"
[ -f "${BUNDLE_ROOT}/etc/sarus-suite/90-sarusctl.conf" ] || die "bundle sarusctl configuration not found"
[ -f "${BUNDLE_ROOT}/etc/containers/policy.json" ] || die "bundle policy.json not found"
if [ -e "$OUTPUT_DIR" ] && [ -n "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
  die "output directory is not empty: ${OUTPUT_DIR}"
fi
install -d -m 0755 "$OUTPUT_DIR"

IMPORT_BINARY_NAMES=()
IMPORT_BINARY_PATHS=()
IMPORT_HOOK_NAMES=()
IMPORT_HOOK_PATHS=()
for spec in "${IMPORT_BINARY_SPECS[@]}"; do register_binary "$spec"; done
for dir in "${IMPORT_HOOK_DIRS[@]}"; do register_hook_dir "$dir"; done

BIN_DIR="${PREFIX}/bin"
HOOK_DIR="${PREFIX}/libexec/oci/hooks"
SHARE_DIR="${PREFIX}/share"
src=""
name=""
mode=""
for src in "${BUNDLE_ROOT}/bin"/*; do
  [ -f "$src" ] || continue
  [ -x "$src" ] || die "bundle bin entry is not executable: ${src}"
  name="$(basename "$src")"
  [ "$name" != "sarus-suite-system-install" ] || continue
  contains_name "$name" "${IMPORT_BINARY_NAMES[@]}" && continue
  contains_name "$name" "${IMPORT_HOOK_NAMES[@]}" && continue
  mode=0755
  [ "$name" != "fusermount3" ] || mode=4755
  copy_file "$src" "${BIN_DIR}/${name}" "$mode"
done
for src in "${BUNDLE_ROOT}/libexec/oci/hooks"/*; do
  [ -f "$src" ] || continue
  [ -x "$src" ] || die "bundle hook entry is not executable: ${src}"
  name="$(basename "$src")"
  contains_name "$name" "${IMPORT_HOOK_NAMES[@]}" && continue
  copy_file "$src" "${HOOK_DIR}/${name}" 0755
done
for ((i = 0; i < ${#IMPORT_BINARY_NAMES[@]}; i++)); do
  name="${IMPORT_BINARY_NAMES[$i]}"
  mode=0755
  [ "$name" != "fusermount3" ] || mode=4755
  copy_file "${IMPORT_BINARY_PATHS[$i]}" "${BIN_DIR}/${name}" "$mode"
done
for ((i = 0; i < ${#IMPORT_HOOK_NAMES[@]}; i++)); do
  name="${IMPORT_HOOK_NAMES[$i]}"
  copy_file "${IMPORT_HOOK_PATHS[$i]}" "${HOOK_DIR}/${name}" 0755
  copy_file "${IMPORT_HOOK_PATHS[$i]}" "${BIN_DIR}/${name}" 0755
done

render_template "${BUNDLE_ROOT}/etc/containers/containers.conf" "$(stage_path /etc/containers/containers.conf)"
render_template "${BUNDLE_ROOT}/etc/containers/storage.conf" "$(stage_path /etc/containers/storage.conf)"
render_template "${BUNDLE_ROOT}/etc/parallax/parallax-mount.conf" "$(stage_path /etc/parallax-mount.conf)"
render_template "${BUNDLE_ROOT}/etc/sarus-suite/90-sarusctl.conf" "$(stage_path /etc/sarus-suite/90-sarusctl.conf)"
copy_file "${BUNDLE_ROOT}/etc/containers/registries.conf" /etc/containers/registries.conf 0644
copy_file "${BUNDLE_ROOT}/etc/containers/policy.json" /etc/containers/policy.json 0644
copy_file "${BUNDLE_ROOT}/etc/containers/seccomp.json" /etc/containers/seccomp.json 0644
copy_file "${BUNDLE_ROOT}/etc/containers/containers.conf.modules/hpc" /etc/containers/containers.conf.modules/hpc 0644
copy_tree "${BUNDLE_ROOT}/etc/containers/registries.d" /etc/containers/registries.d 0644
copy_tree "${BUNDLE_ROOT}/etc/cdi" /etc/cdi 0644
for src in "${BUNDLE_ROOT}/etc/containers/oci/hooks.d"/*; do
  [ -f "$src" ] || continue
  render_template "$src" "$(stage_path "/etc/containers/oci/hooks.d/$(basename "$src")")"
done
copy_tree "${BUNDLE_ROOT}/examples" "${SHARE_DIR}/examples" 0644
copy_tree "${BUNDLE_ROOT}/share" "$SHARE_DIR" 0644

install -d -m 0755 "$(stage_path /etc/sarus-suite)" "$(stage_path /etc/profile.d)"
cat > "$(stage_path /etc/profile.d/sarus-suite.sh)" <<PROFILE
# Generated while building the Sarus Suite system package.
_sarus_suite_bin=${BIN_DIR}
case ":\${PATH:-}:" in
  *":\${_sarus_suite_bin}:"*) ;;
  *) PATH="\${_sarus_suite_bin}\${PATH:+:\${PATH}}"; export PATH ;;
esac
unset _sarus_suite_bin
PROFILE
chmod 0644 "$(stage_path /etc/profile.d/sarus-suite.sh)"

manifest="$(stage_path "${SHARE_DIR}/system-build-manifest.txt")"
install -d -m 0755 "$(dirname "$manifest")"
cat > "$manifest" <<MANIFEST
install_prefix=${PREFIX}
bin_dir=${BIN_DIR}
hook_dir=${HOOK_DIR}
parallax_store=${PARALLAX_STORE}
MANIFEST
for ((i = 0; i < ${#IMPORT_BINARY_NAMES[@]}; i++)); do
  printf 'import_binary.%s.source=%s\n' "${IMPORT_BINARY_NAMES[$i]}" "${IMPORT_BINARY_PATHS[$i]}" >> "$manifest"
  printf 'import_binary.%s.sha256=%s\n' "${IMPORT_BINARY_NAMES[$i]}" "$(sha256_file "${IMPORT_BINARY_PATHS[$i]}")" >> "$manifest"
done
for ((i = 0; i < ${#IMPORT_HOOK_NAMES[@]}; i++)); do
  printf 'import_hook.%s.source=%s\n' "${IMPORT_HOOK_NAMES[$i]}" "${IMPORT_HOOK_PATHS[$i]}" >> "$manifest"
  printf 'import_hook.%s.sha256=%s\n' "${IMPORT_HOOK_NAMES[$i]}" "$(sha256_file "${IMPORT_HOOK_PATHS[$i]}")" >> "$manifest"
done
chmod 0644 "$manifest"

if grep -R '@@SARUS_SUITE_' "$(stage_path /etc)" >/dev/null 2>&1; then
  die "unrendered Sarus Suite placeholder in system configuration"
fi
if grep -R -F "$OUTPUT_DIR" "$(stage_path /etc)" "$manifest" >/dev/null 2>&1; then
  die "staging path leaked into packaged configuration"
fi

printf 'System package payload assembled at %s\n' "$OUTPUT_DIR"

#!/usr/bin/env bash
# Trace sarusctl through the portable shell and verify that generated bundle
# paths are both rendered into configuration and consumed at runtime.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  cat <<'USAGE'
Usage:
  check-configuration-paths.sh [--bundle-root DIR] [--output-dir DIR]
                               [--edf FILE]

The check uses fresh state and Parallax-store directories, runs both
`sarusctl images` and `sarusctl run EDF true` under strace, and retains all
trace, configuration, stdout, and stderr artifacts in the output directory.

Options:
  --bundle-root DIR  Extracted bundle to test (default: BUNDLE_ROOT or the
                     repository's current build output)
  --output-dir DIR   New directory for artifacts (default: a directory under
                     /tmp)
  --edf FILE         EDF used by the run check (default: examples/ubuntu.toml
                     from the selected bundle)
  -h, --help         Show this help
USAGE
}

log() {
  printf '[check-configuration-paths] %s\n' "$*"
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

require_executable() {
  [ -x "$1" ] || die "missing required executable: $1"
}

assert_contains() {
  local label="$1"
  local needle="$2"
  local file="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    printf 'FAIL: %s\n' "$label" >&2
    printf '  expected in %s: %s\n' "$file" "$needle" >&2
    return 1
  fi
  printf 'PASS: %s\n' "$label"
}

# This is how we run traces
run_trace() {
  local name="$1"
  shift

  log "tracing sarusctl ${name}"
  if ! "$SHELL_BIN" \
    --state-root "$STATE_DIR" \
    --parallax-store "$STORE_DIR" \
    -- strace \
      -f \
      -tt \
      -T \
      -yy \
      -s 4096 \
      -e trace=%file,%process \
      -o "$OUTPUT_DIR/sarusctl-${name}.strace" \
      sarusctl "$@" \
      >"$OUTPUT_DIR/sarusctl-${name}.stdout" \
      2>"$OUTPUT_DIR/sarusctl-${name}.stderr"; then
    printf 'FAIL: sarusctl %s failed; stderr follows\n' "$name" >&2
    tail -n 80 "$OUTPUT_DIR/sarusctl-${name}.stderr" >&2 || true
    printf 'Artifacts retained in %s\n' "$OUTPUT_DIR" >&2
    return 1
  fi
}

BUNDLE_ROOT_ARG="${BUNDLE_ROOT:-}"
OUTPUT_DIR_ARG=""
EDF_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-root)
      [ "$#" -ge 2 ] || die "--bundle-root requires a directory"
      BUNDLE_ROOT_ARG="$2"
      shift 2
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || die "--output-dir requires a directory"
      OUTPUT_DIR_ARG="$2"
      shift 2
      ;;
    --edf)
      [ "$#" -ge 2 ] || die "--edf requires a file"
      EDF_ARG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done


# Resolve the bundle
if [ -z "$BUNDLE_ROOT_ARG" ]; then
  # shellcheck source=../components.sh
  source "$ROOT_DIR/components.sh"
  BUNDLE_ROOT_ARG="$BUNDLE_ROOT"
fi

[ -d "$BUNDLE_ROOT_ARG" ] || die "bundle root not found: $BUNDLE_ROOT_ARG"
BUNDLE_ROOT="$(cd "$BUNDLE_ROOT_ARG" && pwd -P)"
SHELL_BIN="$BUNDLE_ROOT/bin/sarus-suite-shell"
EDF_FILE="${EDF_ARG:-$BUNDLE_ROOT/examples/ubuntu.toml}"

# Check we have the minimum to startt
require_cmd grep
require_cmd strace
require_cmd tail
require_executable "$SHELL_BIN"
require_executable "$BUNDLE_ROOT/bin/sarusctl"
require_executable "$BUNDLE_ROOT/bin/podman"
require_executable "$BUNDLE_ROOT/bin/parallax"
require_executable "$BUNDLE_ROOT/bin/crun"
require_file "$EDF_FILE"

# Setup an isolated shell instance
if [ -n "$OUTPUT_DIR_ARG" ]; then
  [ ! -e "$OUTPUT_DIR_ARG" ] || die "output path already exists: $OUTPUT_DIR_ARG"
  mkdir -p "$OUTPUT_DIR_ARG"
  OUTPUT_DIR="$(cd "$OUTPUT_DIR_ARG" && pwd -P)"
else
  OUTPUT_DIR="$(mktemp -d /tmp/sarusctl-config-evaluation.XXXXXX)"
fi

STATE_DIR="$OUTPUT_DIR/state"
STORE_DIR="$OUTPUT_DIR/parallax-store"
mkdir -p "$STATE_DIR" "$STORE_DIR"

log "bundle root: $BUNDLE_ROOT"
log "EDF: $EDF_FILE"
log "artifacts: $OUTPUT_DIR"

# Entering sarus-suite-shell and capture environment info
log "capturing the shell environment and rendered configuration"
"$SHELL_BIN" \
  --state-root "$STATE_DIR" \
  --parallax-store "$STORE_DIR" \
  -- bash -c '
    set -euo pipefail
    output_dir="$1"
    {
      printf "PATH=%s\n" "$PATH"
      printf "HOME=%s\n" "$HOME"
      printf "XDG_CONFIG_HOME=%s\n" "$XDG_CONFIG_HOME"
      printf "XDG_RUNTIME_DIR=%s\n" "$XDG_RUNTIME_DIR"
      printf "SARUSCTL_CONFIG_DIR=%s\n" "$SARUSCTL_CONFIG_DIR"
      printf "PARALLAX_MP_CONFIG=%s\n" "$PARALLAX_MP_CONFIG"
      printf "CONTAINERS_POLICY=%s\n" "$CONTAINERS_POLICY"
      printf "SARUS_SUITE_ROOT=%s\n" "$SARUS_SUITE_ROOT"
      printf "SARUS_SUITE_STATE=%s\n" "$SARUS_SUITE_STATE"
      printf "SARUS_SUITE_PARALLAX_STORE=%s\n" "$SARUS_SUITE_PARALLAX_STORE"
      command -v sarusctl podman parallax crun
    } >"$output_dir/environment.txt"

    cp -a "$XDG_CONFIG_HOME" "$output_dir/xdg-config"
    cp -a "$SARUSCTL_CONFIG_DIR" "$output_dir/sarusctl-config"
  ' bash "$OUTPUT_DIR"


# Check that expected configs are actually there
CONFIG_FILE="$OUTPUT_DIR/xdg-config/sarus-suite/90-sarusctl.conf"
CONTAINERS_FILE="$OUTPUT_DIR/xdg-config/containers/containers.conf"
STORAGE_FILE="$OUTPUT_DIR/xdg-config/containers/storage.conf"
IMAGES_TRACE="$OUTPUT_DIR/sarusctl-images.strace"
RUN_TRACE="$OUTPUT_DIR/sarusctl-run.strace"

require_file "$CONFIG_FILE"
require_file "$CONTAINERS_FILE"
require_file "$STORAGE_FILE"

# Running traces for sarusctl images, sarusctl run EDF
run_trace images images
run_trace run --verbose run "$EDF_FILE" true

failures=0

# Validate sarusctl images trace accessed the XDG confg, podman, podman root dir, RO-store
assert_contains "sarusctl opened the generated XDG config" \
  "$STATE_DIR/config-home/sarus-suite/90-sarusctl.conf" "$IMAGES_TRACE" || failures=$((failures + 1))
assert_contains "images used bundled Podman" \
  "execve(\"$BUNDLE_ROOT/bin/podman\"" "$IMAGES_TRACE" || failures=$((failures + 1))
assert_contains "images used the shell Podman graphroot" \
  "\"--root\", \"$STATE_DIR/podman/root\"" "$IMAGES_TRACE" || failures=$((failures + 1))
assert_contains "images used the shell Parallax store" \
  "additionalimagestore=$STORE_DIR" "$IMAGES_TRACE" || failures=$((failures + 1))

# Validation of sarusctl using bundle rendered configs
assert_contains "sarusctl config rendered parallax_imagestore" \
  "parallax_imagestore = \"$STORE_DIR\"" "$CONFIG_FILE" || failures=$((failures + 1))
assert_contains "sarusctl config rendered bundled Podman" \
  "podman_path = \"$BUNDLE_ROOT/bin/podman\"" "$CONFIG_FILE" || failures=$((failures + 1))
assert_contains "sarusctl config rendered bundled Parallax" \
  "parallax_path = \"$BUNDLE_ROOT/bin/parallax\"" "$CONFIG_FILE" || failures=$((failures + 1))
assert_contains "sarusctl config rendered bundled crun" \
  "runtime_path = \"$BUNDLE_ROOT/bin/crun\"" "$CONFIG_FILE" || failures=$((failures + 1))
assert_contains "sarusctl config rendered the mount program" \
  "parallax_mount_program = \"$BUNDLE_ROOT/bin/parallax-mount-program\"" "$CONFIG_FILE" || failures=$((failures + 1))
assert_contains "sarusctl config rendered squashfuse" \
  "parallax_mp_squashfuse_path = \"$BUNDLE_ROOT/bin/squashfuse_ll\"" "$CONFIG_FILE" || failures=$((failures + 1))

assert_contains "Podman config selected crun" \
  "crun = [\"$BUNDLE_ROOT/bin/crun\"]" "$CONTAINERS_FILE" || failures=$((failures + 1))
assert_contains "storage config selected the mount program" \
  "mount_program = \"$BUNDLE_ROOT/bin/parallax-mount-program\"" "$STORAGE_FILE" || failures=$((failures + 1))

# Validation of sarusctl run (correct use of bundled podman, parallax, hpc module, crun, mount program, squashfuse_ll)
assert_contains "run used bundled Podman" \
  "execve(\"$BUNDLE_ROOT/bin/podman\"" "$RUN_TRACE" || failures=$((failures + 1))
assert_contains "run invoked bundled Parallax" \
  "execve(\"$BUNDLE_ROOT/bin/parallax\"" "$RUN_TRACE" || failures=$((failures + 1))
assert_contains "run selected the hpc Podman module" \
  "\"--module\", \"hpc\"" "$RUN_TRACE" || failures=$((failures + 1))
assert_contains "run passed the configured mount program" \
  "mount_program=$BUNDLE_ROOT/bin/parallax-mount-program" "$RUN_TRACE" || failures=$((failures + 1))
assert_contains "run executed bundled crun" \
  "execve(\"$BUNDLE_ROOT/bin/crun\"" "$RUN_TRACE" || failures=$((failures + 1))
assert_contains "run executed the Parallax mount program" \
  "execve(\"$BUNDLE_ROOT/bin/parallax-mount-program\"" "$RUN_TRACE" || failures=$((failures + 1))
assert_contains "run executed bundled squashfuse" \
  "execve(\"$BUNDLE_ROOT/bin/squashfuse_ll\"" "$RUN_TRACE" || failures=$((failures + 1))

# FAIL CASE
if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %s configuration-path assertion(s) failed\n' "$failures" >&2
  printf 'Artifacts retained in %s\n' "$OUTPUT_DIR" >&2
  exit 1
fi

# PASS CASE
printf 'PASS: sarusctl consumed the sarus-suite-shell configuration for images and run\n'
printf 'Artifacts retained in %s\n' "$OUTPUT_DIR"

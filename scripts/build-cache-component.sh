#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

# Bump this when manifest generation or image-staging semantics change. Build
# recipe files are hashed separately so unrelated component changes do not
# invalidate every cache entry.
SCHEMA_VERSION=1

usage() {
  cat <<'USAGE'
Usage:
  build-cache-component.sh metadata <component> <arch> <output-under-.work>
  build-cache-component.sh prepare  <component> <arch> <output-under-.work>

Commands:
  metadata  Write deterministic input and publication metadata without building.
  prepare   Build one component and prepare a verified scratch-image context.

Supported components:
  podman-glibc podman-static conmon netavark aardvark-dns passt crun catatonit

This script never authenticates to a registry and never pushes an image.
USAGE
}

log() {
  printf '[build-cache] %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die 'need sha256sum or shasum'
  fi
}

normalize_output_dir() {
  local requested="$1"

  case "${requested}" in
    .work/*)
      ;;
    *)
      die "output must be a repository-relative path under .work: ${requested}"
      ;;
  esac
  OUTPUT_REL="${requested%/}"
  OUTPUT_DIR="${ROOT_DIR}/${OUTPUT_REL}"
}

configure_component() {
  COMPONENT="$1"
  ARCH="$(normalize_arch "$2")"
  TARGET_OS=linux
  GO_VERSION=''
  RUST_VERSION=''

  case "${COMPONENT}" in
    podman-glibc)
      SOURCE_NAME=podman
      SOURCE_REPO="${PODMAN_REPO}"
      SOURCE_REF="${PODMAN_VERSION}"
      SOURCE_SHA="${PODMAN_SHA}"
      BUILD_SCRIPT=devcontainer/scripts/build-podman-glibc.sh
      BUILD_RUNNER=scripts/run-glibc-build.sh
      BUILDER_BASE="$(sed -n 's/^FROM[[:space:]]\+//p' "${ROOT_DIR}/devcontainer/glibc/Dockerfile" | head -n 1)"
      GO_VERSION="$(jq -r '.build.args.GO_VERSION' "${ROOT_DIR}/devcontainer/glibc/devcontainer.json")"
      BUILD_MODE=glibc
      BUILD_OPTIONS="GOFLAGS=-buildvcs=false;BUILDTAGS=${PODMAN_GLIBC_BUILDTAGS:-seccomp selinux apparmor exclude_graphdriver_devicemapper containers_image_openpgp btrfs_noversion exclude_graphdriver_btrfs};EXTRA_LDFLAGS=${PODMAN_GLIBC_EXTRA_LDFLAGS:--s -w -linkmode=external -extldflags \"${PODMAN_GLIBC_EXTLDFLAGS:--static-libgcc}\"};GLIBC_BASELINE=${PODMAN_GLIBC_BASELINE:-2.34}"
      RECIPE_FILES=(
        devcontainer/glibc/Dockerfile
        devcontainer/glibc/devcontainer.json
        devcontainer/scripts/install-go.sh
        devcontainer/scripts/lib/build-common.sh
        "${BUILD_SCRIPT}"
        "${BUILD_RUNNER}"
      )
      ;;
    podman-static)
      SOURCE_NAME=podman
      SOURCE_REPO="${PODMAN_REPO}"
      SOURCE_REF="${PODMAN_VERSION}"
      SOURCE_SHA="${PODMAN_SHA}"
      BUILD_SCRIPT=devcontainer/scripts/build-podman-static.sh
      BUILD_RUNNER=scripts/run-alpine-build.sh
      BUILDER_BASE="$(sed -n 's/^FROM[[:space:]]\+//p' "${ROOT_DIR}/devcontainer/alpine/Dockerfile" | head -n 1)"
      GO_VERSION="$(jq -r '.build.args.GO_VERSION' "${ROOT_DIR}/devcontainer/alpine/devcontainer.json")"
      BUILD_MODE=static
      BUILD_OPTIONS="GOFLAGS=-buildvcs=false;BUILDTAGS=${PODMAN_BUILDTAGS};EXTRA_LDFLAGS=${EXTRA_LDFLAGS:--s -w -extldflags=-static}"
      RECIPE_FILES=(
        devcontainer/alpine/Dockerfile
        devcontainer/alpine/devcontainer.json
        devcontainer/scripts/install-go.sh
        devcontainer/scripts/lib/build-common.sh
        "${BUILD_SCRIPT}"
        "${BUILD_RUNNER}"
      )
      ;;
    conmon)
      SOURCE_NAME=conmon
      SOURCE_REPO="${CONMON_REPO}"
      SOURCE_REF="${CONMON_VERSION}"
      SOURCE_SHA="${CONMON_SHA}"
      BUILD_SCRIPT=devcontainer/scripts/build-conmon-static.sh
      BUILD_RUNNER=scripts/run-alpine-build.sh
      BUILD_MODE=static
      BUILD_OPTIONS="DISABLE_SYSTEMD=1;PKG_CONFIG=pkg-config --static;CFLAGS=${CONMON_CFLAGS:--std=c99 -Os -Wall -Wextra -Werror -static};LDFLAGS=${CONMON_LDFLAGS:--s -w -static}"
      ;;
    netavark)
      SOURCE_NAME=netavark
      SOURCE_REPO="${NETAVARK_REPO}"
      SOURCE_REF="${NETAVARK_VERSION}"
      SOURCE_SHA="${NETAVARK_SHA}"
      BUILD_SCRIPT=devcontainer/scripts/build-netavark-static.sh
      BUILD_RUNNER=scripts/run-alpine-build.sh
      BUILD_MODE=static
      BUILD_OPTIONS="cargo=--locked --release;target=${RUST_MUSL_TARGET};RUSTFLAGS=${NETAVARK_RUSTFLAGS:--C target-feature=+crt-static -C link-arg=-s}"
      ;;
    aardvark-dns)
      SOURCE_NAME=aardvark-dns
      SOURCE_REPO="${AARDVARK_DNS_REPO}"
      SOURCE_REF="${AARDVARK_DNS_VERSION}"
      SOURCE_SHA="${AARDVARK_DNS_SHA}"
      BUILD_SCRIPT=devcontainer/scripts/build-aardvark-dns-static.sh
      BUILD_RUNNER=scripts/run-alpine-build.sh
      BUILD_MODE=static
      BUILD_OPTIONS="cargo=--locked --release;target=${RUST_MUSL_TARGET};RUSTFLAGS=${AARDVARK_DNS_RUSTFLAGS:--C target-feature=+crt-static -C link-arg=-s}"
      ;;
    passt)
      SOURCE_NAME=passt
      SOURCE_REPO="${PASST_REPO}"
      SOURCE_REF="${PASST_VERSION}"
      SOURCE_SHA="${PASST_SHA}"
      BUILD_SCRIPT=devcontainer/scripts/build-passt-static.sh
      BUILD_RUNNER=scripts/run-alpine-build.sh
      BUILD_MODE=static
      BUILD_OPTIONS='make static'
      ;;
    crun)
      SOURCE_NAME=crun
      SOURCE_REPO="${CRUN_REPO}"
      SOURCE_REF="${CRUN_VERSION}"
      SOURCE_SHA="${CRUN_SHA}"
      BUILD_SCRIPT=devcontainer/scripts/build-crun-static.sh
      BUILD_RUNNER=scripts/run-alpine-build.sh
      BUILD_MODE=static
      BUILD_OPTIONS="configure=--disable-systemd --disable-shared --enable-embedded-yajl;LDFLAGS=${CRUN_LDFLAGS:--static-libgcc -all-static};EXTRA_LDFLAGS=${CRUN_EXTRA_LDFLAGS:--s -w}"
      ;;
    catatonit)
      SOURCE_NAME=catatonit
      SOURCE_REPO="${CATATONIT_REPO}"
      SOURCE_REF="${CATATONIT_VERSION}"
      SOURCE_SHA="${CATATONIT_SHA}"
      BUILD_SCRIPT=devcontainer/scripts/build-catatonit-static.sh
      BUILD_RUNNER=scripts/run-alpine-build.sh
      BUILD_MODE=static
      BUILD_OPTIONS="configure=--prefix=/ --bindir=/bin;CFLAGS=${CATATONIT_CFLAGS:--Os};LDFLAGS=${CATATONIT_LDFLAGS:--static -s}"
      ;;
    *)
      die "unsupported build-cache component: ${COMPONENT}"
      ;;
  esac

  if [ "${COMPONENT}" != podman-glibc ] && [ "${COMPONENT}" != podman-static ]; then
    BUILDER_BASE="$(sed -n 's/^FROM[[:space:]]\+//p' "${ROOT_DIR}/devcontainer/alpine/Dockerfile" | head -n 1)"
    RECIPE_FILES=(
      devcontainer/alpine/Dockerfile
      devcontainer/alpine/devcontainer.json
      devcontainer/scripts/install-go.sh
      devcontainer/scripts/lib/build-common.sh
      "${BUILD_SCRIPT}"
      "${BUILD_RUNNER}"
    )
  fi

  case "${COMPONENT}" in
    netavark|aardvark-dns)
      RUST_VERSION="$(jq -r '.build.args.RUST_VERSION' "${ROOT_DIR}/devcontainer/alpine/devcontainer.json")"
      ;;
  esac
}

compute_recipe_digest() {
  local inventory file

  inventory="$(mktemp)"
  for file in "${RECIPE_FILES[@]}"; do
    [ -f "${ROOT_DIR}/${file}" ] || die "recipe file not found: ${file}"
    printf '%s %s\n' "$(sha256_file "${ROOT_DIR}/${file}")" "${file}" >> "${inventory}"
  done
  RECIPE_DIGEST="sha256:$(sha256_file "${inventory}")"
  rm -f "${inventory}"
}

write_metadata() {
  local input_file fingerprint_hex short_fingerprint safe_ref tag description

  mkdir -p "${OUTPUT_DIR}"
  input_file="${OUTPUT_DIR}/input-manifest.json"
  compute_recipe_digest

  jq -cS -n \
    --argjson schemaVersion "${SCHEMA_VERSION}" \
    --arg component "${COMPONENT}" \
    --arg sourceName "${SOURCE_NAME}" \
    --arg repository "${SOURCE_REPO}" \
    --arg ref "${SOURCE_REF}" \
    --arg commit "${SOURCE_SHA}" \
    --arg os "${TARGET_OS}" \
    --arg architecture "${ARCH}" \
    --arg base "${BUILDER_BASE}" \
    --arg goVersion "${GO_VERSION}" \
    --arg rustVersion "${RUST_VERSION}" \
    --arg mode "${BUILD_MODE}" \
    --arg options "${BUILD_OPTIONS}" \
    --arg recipeDigest "${RECIPE_DIGEST}" \
    '{
      schemaVersion: $schemaVersion,
      component: $component,
      source: {name: $sourceName, repository: $repository, ref: $ref, commit: $commit},
      target: {os: $os, architecture: $architecture},
      builder: {base: $base, go: $goVersion, rust: $rustVersion},
      build: {mode: $mode, options: $options, recipeDigest: $recipeDigest}
    }' > "${input_file}"

  fingerprint_hex="$(sha256_file "${input_file}")"
  short_fingerprint="${fingerprint_hex:0:20}"
  safe_ref="$(printf '%s' "${SOURCE_REF}" | tr -c 'A-Za-z0-9_.-' '-')"
  tag="${COMPONENT}-${safe_ref}-${short_fingerprint}-${ARCH}"
  description="Sarus Suite build cache: ${COMPONENT} ${SOURCE_REF} for linux/${ARCH} (${short_fingerprint})"

  jq -S -n \
    --arg component "${COMPONENT}" \
    --arg sourceVersion "${SOURCE_REF}" \
    --arg architecture "${ARCH}" \
    --arg fingerprint "sha256:${fingerprint_hex}" \
    --arg shortFingerprint "${short_fingerprint}" \
    --arg tag "${tag}" \
    --arg description "${description}" \
    '{
      component: $component,
      sourceVersion: $sourceVersion,
      architecture: $architecture,
      fingerprint: $fingerprint,
      shortFingerprint: $shortFingerprint,
      tag: $tag,
      description: $description
    }' > "${OUTPUT_DIR}/publication-metadata.json"

  log "${COMPONENT}: ${tag}"
}

copy_artifact() {
  local relative_path="$1"
  local source_path="${BUILD_ROOT}/${relative_path}"
  local destination_path="${CONTEXT_ROOT}/${relative_path}"

  [ -f "${source_path}" ] || die "missing built artifact: ${source_path}"
  mkdir -p "$(dirname "${destination_path}")"
  cp -p "${source_path}" "${destination_path}"
  COPIED_FILES+=("${relative_path}")
}

copy_optional_artifact() {
  [ ! -f "${BUILD_ROOT}/$1" ] || copy_artifact "$1"
}

stage_component() {
  local metadata_prefix

  COPIED_FILES=()
  case "${COMPONENT}" in
    podman-glibc|podman-static)
      metadata_prefix=podman
      copy_artifact usr/local/bin/podman
      copy_optional_artifact usr/local/lib/podman/rootlessport
      copy_artifact etc/containers/seccomp.json
      for name in repo ref sha seccomp selinux apparmor linkage glibc-baseline; do
        copy_artifact ".build-metadata/${metadata_prefix}.${name}"
      done
      copy_artifact .build-metadata/containers-common.ref
      copy_artifact .build-metadata/seccomp.sha256
      ;;
    conmon)
      metadata_prefix=conmon
      copy_artifact usr/local/lib/podman/conmon
      ;;
    netavark)
      metadata_prefix=netavark
      copy_artifact usr/local/lib/podman/netavark
      ;;
    aardvark-dns)
      metadata_prefix=aardvark-dns
      copy_artifact usr/local/lib/podman/aardvark-dns
      ;;
    passt)
      metadata_prefix=passt
      copy_artifact usr/local/bin/pasta
      ;;
    crun)
      metadata_prefix=crun
      copy_artifact usr/local/bin/crun
      ;;
    catatonit)
      metadata_prefix=catatonit
      copy_artifact usr/local/lib/podman/catatonit
      ;;
  esac

  if [ "${metadata_prefix}" != podman ]; then
    for name in repo ref sha; do
      copy_artifact ".build-metadata/${metadata_prefix}.${name}"
    done
  fi

  [ "$(sed -n '1p' "${CONTEXT_ROOT}/.build-metadata/${metadata_prefix}.sha")" = "${SOURCE_SHA}" ] \
    || die "staged source commit does not match the pinned commit for ${COMPONENT}"
}

write_artifact_manifest() {
  local files_json='{}' relative_path digest manifest_dir

  for relative_path in "${COPIED_FILES[@]}"; do
    digest="sha256:$(sha256_file "${CONTEXT_ROOT}/${relative_path}")"
    files_json="$(jq -cS --arg path "${relative_path}" --arg digest "${digest}" \
      '. + {($path): $digest}' <<< "${files_json}")"
  done

  manifest_dir="${CONTEXT_ROOT}/usr/share/sarus-suite"
  mkdir -p "${manifest_dir}"
  cp "${OUTPUT_DIR}/input-manifest.json" "${manifest_dir}/build-cache-input.json"
  jq -S -n \
    --slurpfile input "${OUTPUT_DIR}/input-manifest.json" \
    --argjson schemaVersion "${SCHEMA_VERSION}" \
    --arg artifactType 'sarus-suite-build-cache' \
    --arg fingerprint "$(jq -r '.fingerprint' "${OUTPUT_DIR}/publication-metadata.json")" \
    --argjson files "${files_json}" \
    '{
      schemaVersion: $schemaVersion,
      artifactType: $artifactType,
      fingerprint: $fingerprint,
      input: $input[0],
      files: $files
    }' > "${manifest_dir}/build-cache-artifact.json"
}

prepare_component() {
  local workspace_name container_output build_command

  [ ! -e "${OUTPUT_DIR}/build-root" ] || die "build output already exists: ${OUTPUT_DIR}/build-root"
  [ ! -e "${OUTPUT_DIR}/context" ] || die "image context already exists: ${OUTPUT_DIR}/context"
  BUILD_ROOT="${OUTPUT_DIR}/build-root"
  CONTEXT_ROOT="${OUTPUT_DIR}/context/root"
  mkdir -p "${BUILD_ROOT}" "${CONTEXT_ROOT}"

  workspace_name="$(basename "${ROOT_DIR}")"
  container_output="/workspaces/${workspace_name}/${OUTPUT_REL}/build-root"
  printf -v build_command 'TARGET_ARCH=%q PODMAN_BUILD_PREFIX=%q bash %q' \
    "${ARCH}" "${container_output}" "./${BUILD_SCRIPT}"

  log "building ${COMPONENT} for linux/${ARCH}"
  "${ROOT_DIR}/${BUILD_RUNNER}" "${build_command}"
  stage_component
  write_artifact_manifest
  log "prepared image context at ${OUTPUT_DIR}/context"
}

main() {
  local command component arch output

  [ "$#" -eq 4 ] || { usage >&2; exit 2; }
  command="$1"
  component="$2"
  arch="$3"
  output="$4"

  require_cmd jq
  normalize_output_dir "${output}"
  configure_component "${component}" "${arch}"

  case "${command}" in
    metadata)
      write_metadata
      ;;
    prepare)
      write_metadata
      prepare_component
      ;;
    *)
      usage >&2
      die "unsupported command: ${command}"
      ;;
  esac
}

main "$@"

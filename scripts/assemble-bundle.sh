#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../components.sh
source "${ROOT_DIR}/components.sh"

install_bin() {
  local src="$1"
  local dest_name="$2"
  local mode="${3:-0755}"
  [ -f "${src}" ] || {
    printf 'error: missing source file: %s\n' "${src}" >&2
    exit 1
  }
  install -Dm"${mode}" "${src}" "${RUNTIME_BIN_DIR}/${dest_name}"
}

install_bin_if_present() {
  local src="$1"
  local dest_name="$2"
  local mode="${3:-0755}"

  if [ -f "${src}" ]; then
    install_bin "${src}" "${dest_name}" "${mode}"
  fi
}

rm -rf "${OUT_DIR}"
mkdir -p "${RUNTIME_BIN_DIR}" "${RUNTIME_HOOK_BIN_DIR}" "${RUNTIME_CONTAINERS_ETC_DIR}" "${RUNTIME_CONTAINERS_MODULES_DIR}" "${RUNTIME_CONTAINERS_HOOKS_DIR}" "${RUNTIME_PARALLAX_ETC_DIR}" "${RUNTIME_SARUS_SUITE_ETC_DIR}" "${RUNTIME_LICENSE_DIR}"

install_bin "${PODMAN_STATIC_PREFIX}/usr/local/bin/podman" podman
install_bin "${PODMAN_STATIC_PREFIX}/usr/local/bin/crun" crun
install_bin "${PODMAN_STATIC_PREFIX}/usr/local/bin/pasta" pasta
install_bin_if_present "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/conmon" conmon
install_bin_if_present "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/netavark" netavark
install_bin_if_present "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/aardvark-dns" aardvark-dns
install_bin_if_present "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/rootlessport" rootlessport
install_bin_if_present "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/catatonit" catatonit
install_bin "${PARALLAX_BIN}" parallax
install_bin "${SARUSCTL_BIN}" sarusctl
install_bin "${PERFEXT_LDCACHE_HOOK_BIN}" ldcache_hook
install_bin "${PERFEXT_MPS_HOOK_BIN}" mps_hook
install_bin "${PERFEXT_PCE_HOOK_BIN}" pce_hook
install_bin "${PERFEXT_PC_INJECTION_HOOK_BIN}" pc_injection_hook
install_bin "${PERFEXT_MKHOMEDIR_BIN}" mkhomedir
install_bin "${PERFEXT_SETHOMEVAR_BIN}" sethomevar
install -Dm0755 "${PERFEXT_LDCACHE_HOOK_BIN}" "${RUNTIME_HOOK_BIN_DIR}/ldcache_hook"
install -Dm0755 "${PERFEXT_MPS_HOOK_BIN}" "${RUNTIME_HOOK_BIN_DIR}/mps_hook"
install -Dm0755 "${PERFEXT_PCE_HOOK_BIN}" "${RUNTIME_HOOK_BIN_DIR}/pce_hook"
install -Dm0755 "${PERFEXT_PC_INJECTION_HOOK_BIN}" "${RUNTIME_HOOK_BIN_DIR}/pc_injection_hook"
install -Dm0755 "${PERFEXT_MKHOMEDIR_BIN}" "${RUNTIME_HOOK_BIN_DIR}/mkhomedir"
install -Dm0755 "${PERFEXT_SETHOMEVAR_BIN}" "${RUNTIME_HOOK_BIN_DIR}/sethomevar"
install_bin "${ROOT_DIR}/runtime/support/parallax-mount-program.sh" parallax-mount-program
install_bin "${ROOT_DIR}/runtime/bin/sarus-suite-check.sh" sarus-suite-check
install_bin "${MKSQUASHFS_BIN}" mksquashfs
install_bin "${RSYNC_BIN}" rsync
install_bin "${INOTIFYWAIT_BIN}" inotifywait
install_bin "${SQUASHFUSE_LL_BIN}" squashfuse_ll
install_bin "${FUSE_OVERLAYFS_BIN}" fuse-overlayfs
install_bin "${FUSERMOUNT3_BIN}" fusermount3 4755
install_bin "${ROOT_DIR}/runtime/bin/sarus-suite-shell.sh" sarus-suite-shell

install -Dm0644 "${ROOT_DIR}/runtime/etc/containers/containers.conf" "${RUNTIME_CONTAINERS_ETC_DIR}/containers.conf"
install -Dm0644 "${ROOT_DIR}/runtime/etc/containers/storage.conf" "${RUNTIME_CONTAINERS_ETC_DIR}/storage.conf"
install -Dm0644 "${ROOT_DIR}/runtime/etc/containers/registries.conf" "${RUNTIME_CONTAINERS_ETC_DIR}/registries.conf"
install -Dm0644 "${ROOT_DIR}/runtime/etc/containers/containers.conf.modules/hpc" "${RUNTIME_CONTAINERS_MODULES_DIR}/hpc"
if [ -d "${ROOT_DIR}/runtime/etc/cdi" ]; then
  mkdir -p "${RUNTIME_CDI_ETC_DIR}"
  cp -R "${ROOT_DIR}/runtime/etc/cdi/." "${RUNTIME_CDI_ETC_DIR}/"
fi
if [ -d "${ROOT_DIR}/runtime/etc/containers/oci/hooks.d" ]; then
  install -m0644 "${ROOT_DIR}"/runtime/etc/containers/oci/hooks.d/* "${RUNTIME_CONTAINERS_HOOKS_DIR}/"
fi
if [ -d "${ROOT_DIR}/runtime/etc/containers/registries.d" ]; then
  mkdir -p "${RUNTIME_CONTAINERS_REGISTRIES_D_DIR}"
  cp -R "${ROOT_DIR}/runtime/etc/containers/registries.d/." "${RUNTIME_CONTAINERS_REGISTRIES_D_DIR}/"
fi
install -Dm0644 "${ROOT_DIR}/runtime/etc/parallax/parallax-mount.conf" "${RUNTIME_PARALLAX_ETC_DIR}/parallax-mount.conf"
install -Dm0644 "${ROOT_DIR}/runtime/etc/sarus-suite/90-sarusctl.conf" "${RUNTIME_SARUS_SUITE_ETC_DIR}/90-sarusctl.conf"

if [ -d "${ROOT_DIR}/runtime/examples" ]; then
  mkdir -p "${BUNDLE_ROOT}/examples"
  install -m0644 "${ROOT_DIR}"/runtime/examples/* "${BUNDLE_ROOT}/examples/"
fi

if [ -f "${PODMAN_STATIC_PREFIX}/etc/containers/policy.json" ]; then
  install -Dm0644 "${PODMAN_STATIC_PREFIX}/etc/containers/policy.json" "${RUNTIME_CONTAINERS_ETC_DIR}/policy.json"
fi
if [ -f "${PODMAN_STATIC_PREFIX}/etc/containers/seccomp.json" ]; then
  install -Dm0644 "${PODMAN_STATIC_PREFIX}/etc/containers/seccomp.json" "${RUNTIME_CONTAINERS_ETC_DIR}/seccomp.json"
fi
if [ -f "${PARALLAX_SRC_DIR}/LICENSE" ]; then
  install -Dm0644 "${PARALLAX_SRC_DIR}/LICENSE" "${RUNTIME_LICENSE_DIR}/parallax-LICENSE"
fi

parallax_sha='unknown'
if [ -d "${PARALLAX_SRC_DIR}/.git" ]; then
  parallax_sha="$(git -C "${PARALLAX_SRC_DIR}" rev-parse HEAD)"
fi

sarusctl_sha='unknown'
if [ -d "${SARUSCTL_SRC_DIR}/.git" ]; then
  sarusctl_sha="$(git -C "${SARUSCTL_SRC_DIR}" rev-parse HEAD)"
fi

perfext_sha='unknown'
if [ -d "${PERFEXT_SRC_DIR}/.git" ]; then
  perfext_sha="$(git -C "${PERFEXT_SRC_DIR}" rev-parse HEAD)"
fi

cat > "${RUNTIME_MANIFEST}" <<MANIFEST
bundle_name=${BUNDLE_NAME}
bundle_version=${BUNDLE_VERSION}
target_arch=${TARGET_ARCH}
parallax_repo=${PARALLAX_REPO}
parallax_ref=${PARALLAX_REF}
parallax_sha=${parallax_sha}
sarusctl_repo=${SARUSCTL_REPO}
sarusctl_ref=${SARUSCTL_REF}
sarusctl_src_dir=${SARUSCTL_SRC_DIR}
sarusctl_sha=${sarusctl_sha}
perfext_repo=${PERFEXT_REPO}
perfext_ref=${PERFEXT_REF}
perfext_sha=${perfext_sha}
podman_mode=${PODMAN_MODE}
podman_static_version=${PODMAN_STATIC_VERSION}
mksquashfs_version=${MKSQUASHFS_VERSION}
rsync_version=${RSYNC_VERSION}
inotify_tools_version=${INOTIFY_TOOLS_VERSION}
squashfuse_version=${SQUASHFUSE_VERSION}
fuse_overlayfs_version=${FUSE_OVERLAYFS_VERSION}
libfuse_version=${LIBFUSE_VERSION}
MANIFEST

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
install_bin "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/conmon" conmon
install_bin "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/netavark" netavark
install_bin "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/aardvark-dns" aardvark-dns
install_bin_if_present "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/rootlessport" rootlessport
install_bin "${PODMAN_STATIC_PREFIX}/usr/local/lib/podman/catatonit" catatonit
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
install_bin "${BWRAP_BIN}" bwrap
install_bin "${ROOT_DIR}/runtime/bin/sarus-suite-shell.sh" sarus-suite-shell
install_bin "${ROOT_DIR}/runtime/bin/sarus-suite-system-install.sh" sarus-suite-system-install
install -Dm0755 "${ROOT_DIR}/scripts/install.sh" "${RUNTIME_LIBEXEC_DIR}/sarus-suite/install.sh"

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
mkdir -p "${BUNDLE_ROOT}/etc/system/containers"
install -Dm0644 "${ROOT_DIR}/runtime/etc/system/containers/containers.conf" "${BUNDLE_ROOT}/etc/system/containers/containers.conf"
install -Dm0644 "${ROOT_DIR}/runtime/etc/system/containers/storage.conf" "${BUNDLE_ROOT}/etc/system/containers/storage.conf"
install -Dm0644 "${ROOT_DIR}/runtime/etc/system/parallax-mount.conf" "${BUNDLE_ROOT}/etc/system/parallax-mount.conf"
install -Dm0644 "${ROOT_DIR}/runtime/etc/system/90-sarusctl.conf" "${BUNDLE_ROOT}/etc/system/90-sarusctl.conf"

if [ -d "${ROOT_DIR}/runtime/examples" ]; then
  mkdir -p "${BUNDLE_ROOT}/examples"
  install -m0644 "${ROOT_DIR}"/runtime/examples/* "${BUNDLE_ROOT}/examples/"
fi

install -Dm0644 "${ROOT_DIR}/runtime/etc/containers/policy.json" "${RUNTIME_CONTAINERS_ETC_DIR}/policy.json"
podman_linkage_metadata="${PODMAN_STATIC_PREFIX}/.build-metadata/podman.linkage"
[ -s "${podman_linkage_metadata}" ] || {
  printf 'error: missing Podman linkage metadata: %s\n' "${podman_linkage_metadata}" >&2
  exit 1
}
podman_linkage="$(sed -n '1p' "${podman_linkage_metadata}")"
case "${podman_linkage}" in
  static|glibc) ;;
  *) printf 'error: invalid Podman linkage metadata: %s\n' "${podman_linkage}" >&2; exit 1 ;;
esac
podman_seccomp_metadata="${PODMAN_STATIC_PREFIX}/.build-metadata/podman.seccomp"
[ -s "${podman_seccomp_metadata}" ] || {
  printf 'error: missing Podman seccomp metadata: %s\n' "${podman_seccomp_metadata}" >&2
  exit 1
}
podman_seccomp="$(sed -n '1p' "${podman_seccomp_metadata}")"
[ "${podman_seccomp}" = enabled ] || {
  printf 'error: Podman seccomp support is required\n' >&2
  exit 1
}
install -Dm0644 "${PODMAN_STATIC_PREFIX}/etc/containers/seccomp.json" "${RUNTIME_CONTAINERS_ETC_DIR}/seccomp.json"
if [ -f "${PARALLAX_SRC_DIR}/LICENSE" ]; then
  install -Dm0644 "${PARALLAX_SRC_DIR}/LICENSE" "${RUNTIME_LICENSE_DIR}/parallax-LICENSE"
fi
install -Dm0644 "${ROOT_DIR}/LICENSE" "${RUNTIME_LICENSE_DIR}/sarus-suite-LICENSE"

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

read_podman_build_metadata() {
  local component="$1"
  local field="$2"
  local path="${PODMAN_STATIC_PREFIX}/.build-metadata/${component}.${field}"

  [ -s "${path}" ] || {
    printf 'error: missing Podman build metadata: %s\n' "${path}" >&2
    exit 1
  }
  sed -n '1p' "${path}"
}

podman_linkage=$(read_podman_build_metadata podman linkage)
podman_glibc_baseline=$(read_podman_build_metadata podman glibc-baseline)
podman_seccomp=$(read_podman_build_metadata podman seccomp)
podman_selinux=$(read_podman_build_metadata podman selinux)
podman_apparmor=$(read_podman_build_metadata podman apparmor)
seccomp_sha256=$(read_podman_build_metadata seccomp sha256)

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
rootlessport_bundled=$(if [ -x "${RUNTIME_BIN_DIR}/rootlessport" ]; then printf 'true'; else printf 'false'; fi)
podman_repo=$(read_podman_build_metadata podman repo)
podman_ref=$(read_podman_build_metadata podman ref)
podman_sha=$(read_podman_build_metadata podman sha)
podman_version=${PODMAN_VERSION}
podman_linkage=${podman_linkage}
podman_glibc_baseline=${podman_glibc_baseline}
podman_seccomp=${podman_seccomp}
podman_selinux=${podman_selinux}
podman_apparmor=${podman_apparmor}
conmon_repo=$(read_podman_build_metadata conmon repo)
conmon_ref=$(read_podman_build_metadata conmon ref)
conmon_sha=$(read_podman_build_metadata conmon sha)
conmon_version=${CONMON_VERSION}
netavark_repo=$(read_podman_build_metadata netavark repo)
netavark_ref=$(read_podman_build_metadata netavark ref)
netavark_sha=$(read_podman_build_metadata netavark sha)
netavark_version=${NETAVARK_VERSION}
aardvark_dns_repo=$(read_podman_build_metadata aardvark-dns repo)
aardvark_dns_ref=$(read_podman_build_metadata aardvark-dns ref)
aardvark_dns_sha=$(read_podman_build_metadata aardvark-dns sha)
aardvark_dns_version=${AARDVARK_DNS_VERSION}
passt_repo=$(read_podman_build_metadata passt repo)
passt_ref=$(read_podman_build_metadata passt ref)
passt_sha=$(read_podman_build_metadata passt sha)
passt_version=${PASST_VERSION}
crun_repo=$(read_podman_build_metadata crun repo)
crun_ref=$(read_podman_build_metadata crun ref)
crun_sha=$(read_podman_build_metadata crun sha)
crun_version=${CRUN_VERSION}
catatonit_repo=$(read_podman_build_metadata catatonit repo)
catatonit_ref=$(read_podman_build_metadata catatonit ref)
catatonit_sha=$(read_podman_build_metadata catatonit sha)
catatonit_version=${CATATONIT_VERSION}
containers_common_ref=$(read_podman_build_metadata containers-common ref)
seccomp_sha256=${seccomp_sha256}
mksquashfs_version=${MKSQUASHFS_VERSION}
rsync_version=${RSYNC_VERSION}
inotify_tools_version=${INOTIFY_TOOLS_VERSION}
squashfuse_version=${SQUASHFUSE_VERSION}
fuse_overlayfs_version=${FUSE_OVERLAYFS_VERSION}
libfuse_version=${LIBFUSE_VERSION}
bubblewrap_version=${BUBBLEWRAP_VERSION}
MANIFEST

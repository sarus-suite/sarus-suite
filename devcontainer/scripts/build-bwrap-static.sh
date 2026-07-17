#!/usr/bin/env sh
set -eu

OUT="${OUT:-dist/bubblewrap-static/bwrap}"
BUBBLEWRAP_VERSION="${BUBBLEWRAP_VERSION:-v0.11.2}"
BUBBLEWRAP_REPO="${BUBBLEWRAP_REPO:-https://github.com/containers/bubblewrap.git}"
LIBCAP_REPO="${LIBCAP_REPO:-https://git.kernel.org/pub/scm/libs/libcap/libcap.git}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
root_dir="$(pwd -P)"

case "${OUT}" in
  /*) out_path="${OUT}" ;;
  *) out_path="${root_dir}/${OUT}" ;;
esac

workdir="$(mktemp -d)"
src_dir="${workdir}/bubblewrap"
build_dir="${workdir}/build"
prefix_dir="${workdir}/prefix"
libcap_dir="${workdir}/libcap"
pkg_config_wrapper="${workdir}/pkg-config-static"

cleanup() {
  if [ "${KEEP_WORKDIR}" = "1" ]; then
    printf '%s\n' "Keeping build workspace at ${workdir}"
    return
  fi

  rm -rf "${workdir}"
}

trap cleanup EXIT HUP INT TERM

ensure_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    return
  fi

  printf '%s\n' "error: required command not found: $1" >&2
  exit 1
}

mkdir -p "$(dirname "${out_path}")"

ensure_cmd git
ensure_cmd make
ensure_cmd meson
ensure_cmd ninja
ensure_cmd pkg-config

if [ -z "${CC:-}" ]; then
  if command -v musl-gcc >/dev/null 2>&1; then
    export CC="musl-gcc"
  elif command -v gcc >/dev/null 2>&1; then
    export CC="gcc"
  else
    export CC="cc"
  fi
fi

ensure_cmd "${CC}"

export CFLAGS="${CFLAGS:--O2 -pipe}"
export CPPFLAGS="${CPPFLAGS:-}"
export LDFLAGS="${LDFLAGS:--static}"

git init "${src_dir}" >/dev/null
git -C "${src_dir}" remote add origin "${BUBBLEWRAP_REPO}"
git -C "${src_dir}" fetch --depth 1 origin "refs/tags/${BUBBLEWRAP_VERSION}"
git -C "${src_dir}" checkout --detach FETCH_HEAD >/dev/null

git clone --depth 1 "${LIBCAP_REPO}" "${libcap_dir}" >/dev/null 2>&1
make -C "${libcap_dir}/libcap" -j"${JOBS}" libcap.a

mkdir -p "${prefix_dir}/include/sys" "${prefix_dir}/lib/pkgconfig"
cp "${libcap_dir}/libcap/libcap.a" "${prefix_dir}/lib/"
cp "${libcap_dir}/libcap/../libcap/include/sys/capability.h" "${prefix_dir}/include/sys/"

cat > "${prefix_dir}/lib/pkgconfig/libcap.pc" <<EOF
prefix=${prefix_dir}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libcap
Description: Minimal static libcap metadata for bubblewrap builds
Version: 0
Libs: -L\${libdir} -lcap
Cflags: -I\${includedir}
EOF

cat > "${pkg_config_wrapper}" <<EOF
#!/usr/bin/env sh
set -eu

export PKG_CONFIG_PATH="${prefix_dir}/lib/pkgconfig\${PKG_CONFIG_PATH:+:\${PKG_CONFIG_PATH}}"
exec pkg-config --static "\$@"
EOF
chmod 0755 "${pkg_config_wrapper}"

export PKG_CONFIG="${pkg_config_wrapper}"
export PKG_CONFIG_ALL_STATIC=1
export PKG_CONFIG_PATH="${prefix_dir}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export CPPFLAGS="${CPPFLAGS} -I${prefix_dir}/include"
export LDFLAGS="${LDFLAGS} -L${prefix_dir}/lib"

meson setup "${build_dir}" "${src_dir}" \
  --buildtype=release \
  --default-library=static \
  -Dselinux=disabled \
  -Dc_args="${CFLAGS}${CPPFLAGS:+ ${CPPFLAGS}}" \
  -Dc_link_args="${LDFLAGS}"

ninja -C "${build_dir}" -j "${JOBS}" bwrap

cp "${build_dir}/bwrap" "${out_path}"
chmod 0755 "${out_path}"

if command -v strip >/dev/null 2>&1; then
  strip "${out_path}" || true
fi

printf '%s\n' "Built static bwrap at ${out_path}"

if command -v file >/dev/null 2>&1; then
  file "${out_path}"
fi

if command -v readelf >/dev/null 2>&1; then
  readelf -l "${out_path}" | grep interpreter || true
fi

if command -v scanelf >/dev/null 2>&1; then
  scanelf -n "${out_path}" || true
fi

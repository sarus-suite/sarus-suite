#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install.sh stage --bundle-root DIR --output-dir DIR [OPTIONS]
  install.sh apply --bundle-root DIR [OPTIONS]
  install.sh user --bundle-root DIR [OPTIONS]
  install.sh user-uninstall [--user-root DIR] [OPTIONS]

Sets up Sarus Suite system or persistent per-user layouts.
`stage` writes the layout into OUTPUT_DIR without mutating the host;
RPM packaging can then consume that tree.
`apply` stages privately, dry-run collision check, and copies the same tree into the system.
`user` installs a private runtime and XDG tree below ~/.sarus-suite.
`user-uninstall` removes that private runtime while retaining image stores outside it.

Options:
  --bundle-root DIR       Assembled Sarus Suite bundle
  --output-dir DIR        New or empty payload directory
  --parallax-store PATH   Per-user image store expression
                          (default: ${HOME}/.sarus-suite/ro-store)
  --podman-graphroot PATH User-mode Podman persistent storage root
                          (default: Podman's XDG data default)
  --podman-runroot PATH   User-mode Podman runtime storage root
                          (default: Podman's XDG runtime default)
  --import-binary SPEC    Replace PATH[:NAME] in the payload; repeatable
  --import-hook-dir DIR   Replace hooks with executable files from DIR and
                          mirror them into the suite bin directory; repeatable
  --install-root DIR      Apply below DIR instead of the live system
  --report FILE           Apply report (default: /var/log/sarus-suite-install-report.txt)
  --user-root DIR         User installation root (default: $HOME/.sarus-suite)
  --shell-init TARGET     Update TARGET with a guarded PATH entry; TARGET may
                          be "auto" (default), "none", or an absolute file
  --force                 Replace differing regular files during apply/user
  --dry-run               Preview apply/user/user-uninstall without changes
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

payload_path() {
  printf '%s%s\n' "$OUTPUT_DIR" "$1"
}

copy_file() {
  local src="$1"
  local logical_dest="$2"
  local mode="$3"
  local dest
  dest="$(payload_path "$logical_dest")"
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

require_apply_target() {
  [ "$(uname -s)" = Linux ] || die "system installation is supported only on Linux"
  if [ "${EUID}" -ne 0 ] && [ -z "$INSTALL_ROOT" ] && [ "$DRY_RUN" -ne 1 ]; then
    die "install.sh apply must run as root"
  fi
}

apply_path() {
  printf '%s%s\n' "$1" "$2"
}

check_parent_chain() {
  local path="$1"
  local parent

  parent="$(dirname "$path")"
  [ "$parent" = / ] && return 0
  if [ -e "$parent" ] || [ -L "$parent" ]; then
    [ -d "$parent" ] || die "destination parent is not a directory: ${parent}"
    return 0
  fi
  check_parent_chain "$parent"
}

file_mode() {
  stat -c '%a' "$1"
}

apply_staged_payload() {
  local stage_root="$1"
  local report_root report_dest src logical_dest dest mode action
  local -a staged_files

  mapfile -t staged_files < <(find "$stage_root" -type f -print | sort)
  [ "${#staged_files[@]}" -gt 0 ] || die "staged payload is empty"

  for src in "${staged_files[@]}"; do
    logical_dest="/${src#${stage_root}/}"
    dest="$(apply_path "$INSTALL_ROOT" "$logical_dest")"
    check_parent_chain "$dest"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      [ -f "$dest" ] && [ ! -L "$dest" ] || die "refusing to replace non-regular path: ${dest}"
      if ! cmp -s "$src" "$dest" || [ "$(file_mode "$src")" != "$(file_mode "$dest")" ]; then
        [ "$FORCE" -eq 1 ] || die "destination differs (use --force to replace): ${dest}"
      fi
    fi
  done

  report_dest="$(apply_path "$INSTALL_ROOT" "$REPORT_FILE")"
  check_parent_chain "$report_dest"
  if [ -e "$report_dest" ] || [ -L "$report_dest" ]; then
    [ -f "$report_dest" ] && [ ! -L "$report_dest" ] || die "refusing to replace non-regular report path: ${report_dest}"
  fi

  # Dry-run only prints
  if [ "$DRY_RUN" -eq 1 ]; then
    for src in "${staged_files[@]}"; do
      logical_dest="/${src#${stage_root}/}"
      dest="$(apply_path "$INSTALL_ROOT" "$logical_dest")"
      if [ -e "$dest" ]; then action=WOULD_UPDATE; else action=WOULD_CREATE; fi
      printf '%-14s %s\n' "$action" "file ${dest}"
    done
    printf '%-14s %s\n' WOULD_WRITE "report ${report_dest}"
    return 0
  fi

  # Install staged and write report
  report_root="$(mktemp "${TMPDIR:-/tmp}/sarus-suite-install-report.XXXXXX")"
  trap 'rm -f "${report_root}"' RETURN
  {
    printf 'Sarus Suite system install report\n'
    printf 'bundle_root=%s\ninstall_root=%s\n\nChanges:\n' "$BUNDLE_ROOT" "${INSTALL_ROOT:-/}"
  } > "$report_root"

  for src in "${staged_files[@]}"; do
    logical_dest="/${src#${stage_root}/}"
    dest="$(apply_path "$INSTALL_ROOT" "$logical_dest")"
    mode="$(file_mode "$src")"
    install -d -m 0755 "$(dirname "$dest")"
    if [ -f "$dest" ] && cmp -s "$src" "$dest" && [ "$(file_mode "$dest")" = "$mode" ]; then
      printf '%-14s %s\n' UNCHANGED "file ${dest} mode=${mode}" >> "$report_root"
      continue
    fi
    action=CREATED
    [ -e "$dest" ] && action=UPDATED
    install -m "$mode" "$src" "$dest"
    printf '%-14s %s\n' "$action" "file ${dest} mode=${mode}" >> "$report_root"
  done

  install -d -m 0755 "$(dirname "$report_dest")"
  install -m 0644 "$report_root" "$report_dest"
  cat "$report_root"
  printf 'Installation complete. Persistent report: %s\n' "$report_dest"
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

render_user_template() {
  local src="$1"
  local dest="$2"
  local cdi_line=""
  local parallax_tmpdir_line parallax_logfile_line parallax_mp_logfile_line podman_tmp_path_line
  local podman_graphroot_line="" podman_runroot_line=""

  if [ -d "${BUNDLE_ROOT}/etc/cdi" ]; then
    cdi_line="cdi_spec_dirs = [\"${USER_CONFIG_HOME}/cdi\"]"
  fi
  parallax_tmpdir_line='PARALLAX_MP_TMPDIR="${XDG_RUNTIME_DIR}/parallax-mount"'
  parallax_logfile_line="PARALLAX_MP_LOGFILE=\"${USER_STATE_DIR}/logs/parallax-mount.log\""
  parallax_mp_logfile_line="parallax_mp_logfile = \"${USER_STATE_DIR}/logs/parallax-mount.log\""
  podman_tmp_path_line='podman_tmp_path = "${XDG_RUNTIME_DIR}/tmp"'
  if [ -n "$PODMAN_GRAPHROOT" ]; then
    podman_graphroot_line="graphroot = \"${PODMAN_GRAPHROOT}\""
  fi
  if [ -n "$PODMAN_RUNROOT" ]; then
    podman_runroot_line="runroot = \"${PODMAN_RUNROOT}\""
  fi

  install -d -m 0755 "$(dirname "$dest")"
  sed \
    -e "s|@@SARUS_SUITE_BIN@@|$(escape_sed_replacement "$USER_PAYLOAD_BIN")|g" \
    -e "s|@@SARUS_SUITE_HOOK_BIN@@|$(escape_sed_replacement "$USER_HOOK_DIR")|g" \
    -e "s|@@SARUS_SUITE_CONFIG@@|$(escape_sed_replacement "$USER_CONFIG_HOME")|g" \
    -e "s|@@SARUS_SUITE_PARALLAX_STORE@@|$(escape_sed_replacement "$PARALLAX_STORE")|g" \
    -e "s|@@SARUS_SUITE_CDI_SPEC_DIRS@@|$(escape_sed_replacement "$cdi_line")|g" \
    -e "s|@@SARUS_SUITE_PODMAN_GRAPHROOT_LINE@@|$(escape_sed_replacement "$podman_graphroot_line")|g" \
    -e "s|@@SARUS_SUITE_PODMAN_RUNROOT_LINE@@|$(escape_sed_replacement "$podman_runroot_line")|g" \
    -e 's|@@SARUS_SUITE_PODMAN_STORAGE_OPTIONS_HEADER@@|[storage.options]|g' \
    -e "s|@@SARUS_SUITE_PODMAN_ADDITIONAL_IMAGESTORES_LINE@@|additionalimagestores = [\"$(escape_sed_replacement "$PARALLAX_STORE")\"]|g" \
    -e "s|@@SARUS_SUITE_PARALLAX_TMPDIR_LINE@@|$(escape_sed_replacement "$parallax_tmpdir_line")|g" \
    -e "s|@@SARUS_SUITE_PARALLAX_LOGFILE_LINE@@|$(escape_sed_replacement "$parallax_logfile_line")|g" \
    -e "s|@@SARUS_SUITE_PARALLAX_MP_LOGFILE_LINE@@|$(escape_sed_replacement "$parallax_mp_logfile_line")|g" \
    -e "s|@@SARUS_SUITE_PODMAN_TMP_PATH_LINE@@|$(escape_sed_replacement "$podman_tmp_path_line")|g" \
    "$src" > "$dest"
  chmod 0644 "$dest"
}

write_user_command_wrapper() {
  local dest="$1"
  local tool="$2"

  install -d -m 0755 "$(dirname "$dest")"
  cat > "$dest" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd -P)"
exec "\${SCRIPT_DIR}/../libexec/sarus-suite/launch" ${tool} "\$@"
WRAPPER
  chmod 0755 "$dest"
}

write_user_uninstall_wrapper() {
  local dest="$1"

  install -d -m 0755 "$(dirname "$dest")"
  cat > "$dest" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
USER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
exec "${USER_ROOT}/libexec/sarus-suite/install.sh" user-uninstall \
  --user-root "${USER_ROOT}" "$@"
WRAPPER
  chmod 0755 "$dest"
}

resolve_shell_init() {
  case "$SHELL_INIT" in
    none) printf '\n' ;;
    auto)
      case "${SHELL:-}" in
        */zsh) printf '%s/.zshrc\n' "$HOME" ;;
        */bash) printf '%s/.bashrc\n' "$HOME" ;;
        *) printf '%s/.profile\n' "$HOME" ;;
      esac
      ;;
    *) printf '%s\n' "$SHELL_INIT" ;;
  esac
}

validate_user_shell_init() {
  local rcfile="$1"
  local marker='# >>> sarus-suite user install >>>'
  local expected_assignment

  [ -n "$rcfile" ] || return 0
  printf -v expected_assignment '_sarus_suite_bin=%q' "${USER_ROOT}/bin"
  if [ -e "$rcfile" ] || [ -L "$rcfile" ]; then
    [ -f "$rcfile" ] || die "shell init target is not a regular file: ${rcfile}"
    if grep -Fq "$marker" "$rcfile"; then
      grep -Fq "$expected_assignment" "$rcfile" || die "shell init already contains a Sarus Suite entry for another installation: ${rcfile}"
    fi
  fi
}

write_user_shell_init() {
  local rcfile="$1"
  local marker='# >>> sarus-suite user install >>>'
  local expected_assignment

  validate_user_shell_init "$rcfile"
  printf -v expected_assignment '_sarus_suite_bin=%q' "${USER_ROOT}/bin"

  [ -n "$rcfile" ] || return 0
  if [ -e "$rcfile" ] || [ -L "$rcfile" ]; then
    if grep -Fq "$marker" "$rcfile"; then
      printf '%-14s %s\n' UNCHANGED "shell init ${rcfile}"
      return 0
    fi
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%-14s %s\n' WOULD_UPDATE "shell init ${rcfile}"
    return 0
  fi

  install -d -m 0755 "$(dirname "$rcfile")"
  {
    printf '\n%s\n' "$marker"
    printf '%s\n' "$expected_assignment"
    printf 'if [ -d "${_sarus_suite_bin}" ]; then\n'
    printf '  case ":${PATH:-}:" in\n'
    printf '    *":${_sarus_suite_bin}:"*) ;;\n'
    printf '    *) PATH="${_sarus_suite_bin}${PATH:+:${PATH}}"; export PATH ;;\n'
    printf '  esac\n'
    printf 'fi\n'
    printf 'unset _sarus_suite_bin\n'
    printf '# <<< sarus-suite user install <<<\n'
  } >> "$rcfile"
  printf '%-14s %s\n' UPDATED "shell init ${rcfile}"
}

manifest_value() {
  local key="$1"
  local manifest="$2"

  sed -n "s/^${key}=//p" "$manifest" | sed -n '1p'
}

remove_user_shell_init() {
  local rcfile="$1"
  local start_marker='# >>> sarus-suite user install >>>'
  local end_marker='# <<< sarus-suite user install <<<'
  local start_count end_count mode tmp

  [ -n "$rcfile" ] || return 0
  if [ ! -e "$rcfile" ] && [ ! -L "$rcfile" ]; then
    printf '%-14s %s\n' UNCHANGED "shell init ${rcfile} (not found)"
    return 0
  fi
  [ -f "$rcfile" ] || die "shell init target is not a regular file: ${rcfile}"
  start_count="$(grep -Fc "$start_marker" "$rcfile" || true)"
  end_count="$(grep -Fc "$end_marker" "$rcfile" || true)"
  if [ "$start_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
    printf '%-14s %s\n' UNCHANGED "shell init ${rcfile} (entry not found)"
    return 0
  fi
  [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ] || \
    die "shell init contains an invalid Sarus Suite entry: ${rcfile}"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%-14s %s\n' WOULD_UPDATE "shell init ${rcfile}"
    return 0
  fi

  mode="$(file_mode "$rcfile")"
  tmp="$(mktemp "${TMPDIR:-/tmp}/sarus-suite-shell-init.XXXXXX")"
  sed "/^# >>> sarus-suite user install >>>$/,/^# <<< sarus-suite user install <<<$/{d;}" \
    "$rcfile" > "$tmp"
  cat "$tmp" > "$rcfile"
  chmod "$mode" "$rcfile"
  rm -f "$tmp"
  printf '%-14s %s\n' UPDATED "shell init ${rcfile}"
}

uninstall_user_payload() {
  local manifest="${USER_ROOT}/install/manifest.txt"
  local installed_root shell_init_file parallax_store podman_graphroot podman_runroot path running_containers

  [ -d "$USER_ROOT" ] && [ ! -L "$USER_ROOT" ] || die "user installation not found: ${USER_ROOT}"
  [ -O "$USER_ROOT" ] || die "user root is not owned by the current user: ${USER_ROOT}"
  [ -f "$manifest" ] && [ ! -L "$manifest" ] || die "user install manifest not found: ${manifest}"
  [ "$(manifest_value install_mode "$manifest")" = user ] || die "not a Sarus Suite user installation: ${USER_ROOT}"
  installed_root="$(manifest_value install_root "$manifest")"
  [ "$installed_root" = "$USER_ROOT" ] || die "install manifest belongs to another user root: ${installed_root}"

  shell_init_file="$(manifest_value shell_init "$manifest")"
  if ! grep -q '^shell_init=' "$manifest"; then
    shell_init_file="$(resolve_shell_init)"
  fi
  parallax_store="$(manifest_value parallax_store "$manifest")"
  podman_graphroot="$(manifest_value podman_graphroot "$manifest")"
  podman_runroot="$(manifest_value podman_runroot "$manifest")"
  [ "$podman_graphroot" != 'XDG default' ] || podman_graphroot="${USER_ROOT}/xdg/data/containers/storage"

  printf 'Sarus Suite user uninstall\n'
  printf 'user_root=%s\n' "$USER_ROOT"
  for path in "$parallax_store" "$podman_graphroot" "$podman_runroot"; do
    [ -n "$path" ] && [ "$path" != 'XDG default' ] || continue
    case "$path" in
      "$USER_ROOT"|"$USER_ROOT"/*) ;;
      *) printf '%-14s %s\n' RETAINED "external storage ${path}" ;;
    esac
  done
  if [ -e "${HOME}/.config/containers/policy.json" ] || [ -L "${HOME}/.config/containers/policy.json" ]; then
    printf '%-14s %s\n' RETAINED "user policy ${HOME}/.config/containers/policy.json"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    remove_user_shell_init "$shell_init_file"
    printf '%-14s %s\n' WOULD_REMOVE "directory ${USER_ROOT}"
    return 0
  fi

  if ! running_containers="$("${USER_ROOT}/bin/podman" ps -q)"; then
    die "cannot check for running Sarus Suite containers; installation was not removed"
  fi
  [ -z "$running_containers" ] || die "running Sarus Suite containers must be stopped before uninstalling"

  remove_user_shell_init "$shell_init_file"
  # Podman bind-mounts graphroot/overlay inside unshare. Remove namespace-owned
  # entries there, but leave directories that are mountpoints for the host pass.
  "${USER_ROOT}/bin/podman" unshare sh -c '
    find "$1" -depth -mindepth 1 ! -type d -delete &&
    find "$1" -depth -mindepth 1 -type d ! -path "$2/overlay" -empty -delete
  ' sh "$USER_ROOT" "$podman_graphroot"
  rm -rf -- "$USER_ROOT"
  printf '%-14s %s\n' REMOVED "directory ${USER_ROOT}"
}

apply_user_payload() {
  local stage_root="$1"
  local report_dest="${USER_ROOT}/install/report.txt"
  local report_tmp src relative dest mode action dir
  local user_policy="${HOME}/.config/containers/policy.json"
  local system_policy=/etc/containers/policy.json
  local -a staged_files

  mapfile -t staged_files < <(find "$stage_root" -type f -print | sort)
  [ "${#staged_files[@]}" -gt 0 ] || die "staged user payload is empty"

  if [ -e "$USER_ROOT" ] || [ -L "$USER_ROOT" ]; then
    [ -d "$USER_ROOT" ] && [ ! -L "$USER_ROOT" ] || die "user root is not a directory: ${USER_ROOT}"
  fi
  if [ -e "$PARALLAX_STORE" ] || [ -L "$PARALLAX_STORE" ]; then
    [ -d "$PARALLAX_STORE" ] || die "Parallax store is not a directory: ${PARALLAX_STORE}"
    [ -w "$PARALLAX_STORE" ] || die "Parallax store is not writable: ${PARALLAX_STORE}"
  fi
  for path in "$PODMAN_GRAPHROOT" "$PODMAN_RUNROOT"; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -d "$path" ] && [ ! -L "$path" ] || die "Podman storage path is not a directory: ${path}"
      [ -w "$path" ] || die "Podman storage path is not writable: ${path}"
    fi
  done
  if [ -e "$report_dest" ] || [ -L "$report_dest" ]; then
    [ -f "$report_dest" ] && [ ! -L "$report_dest" ] || die "refusing to replace non-regular report path: ${report_dest}"
  fi

  for src in "${staged_files[@]}"; do
    relative="${src#${stage_root}/}"
    dest="${USER_ROOT}/${relative}"
    check_parent_chain "$dest"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      [ -f "$dest" ] && [ ! -L "$dest" ] || die "refusing to replace non-regular path: ${dest}"
      if ! cmp -s "$src" "$dest" || [ "$(file_mode "$src")" != "$(file_mode "$dest")" ]; then
        [ "$FORCE" -eq 1 ] || die "destination differs (use --force to replace): ${dest}"
      fi
    fi
  done

  if [ "$DRY_RUN" -eq 1 ]; then
    for src in "${staged_files[@]}"; do
      relative="${src#${stage_root}/}"
      dest="${USER_ROOT}/${relative}"
      if [ -e "$dest" ]; then action=WOULD_UPDATE; else action=WOULD_CREATE; fi
      printf '%-14s %s\n' "$action" "file ${dest}"
    done
    printf '%-14s %s\n' WOULD_WRITE "report ${report_dest}"
    for path in "$PODMAN_GRAPHROOT" "$PODMAN_RUNROOT"; do
      [ -z "$path" ] || [ -d "$path" ] || printf '%-14s %s\n' WOULD_CREATE "directory ${path}"
    done
    if [ -e "$user_policy" ] || [ -L "$user_policy" ]; then
      printf '%-14s %s\n' USING "existing user policy ${user_policy}"
    elif [ -e "$system_policy" ] || [ -L "$system_policy" ]; then
      printf '%-14s %s\n' USING "existing system policy ${system_policy}"
    else
      printf '%-14s %s\n' WOULD_CREATE "user policy ${user_policy} (image signatures not required)"
    fi
    return 0
  fi

  install -d -m 0700 "$USER_ROOT"
  report_tmp="$(mktemp "${TMPDIR:-/tmp}/sarus-suite-user-install-report.XXXXXX")"
  {
    printf 'Sarus Suite user install report\n'
    printf 'bundle_root=%s\n' "$BUNDLE_ROOT"
    printf 'user_root=%s\n' "$USER_ROOT"
    printf 'podman_graphroot=%s\n' "$PODMAN_GRAPHROOT"
    printf 'parallax_store=%s\n\nChanges:\n' "$PARALLAX_STORE"
  } > "$report_tmp"

  for src in "${staged_files[@]}"; do
    relative="${src#${stage_root}/}"
    dest="${USER_ROOT}/${relative}"
    mode="$(file_mode "$src")"
    install -d -m 0755 "$(dirname "$dest")"
    if [ -f "$dest" ] && cmp -s "$src" "$dest" && [ "$(file_mode "$dest")" = "$mode" ]; then
      printf '%-14s %s\n' UNCHANGED "file ${dest} mode=${mode}" >> "$report_tmp"
      continue
    fi
    action=CREATED
    [ -e "$dest" ] && action=UPDATED
    install -m "$mode" "$src" "$dest"
    printf '%-14s %s\n' "$action" "file ${dest} mode=${mode}" >> "$report_tmp"
  done

  install -d -m 0700 \
    "${USER_ROOT}/install" \
    "${USER_ROOT}/xdg/config" \
    "${USER_ROOT}/xdg/data" \
    "${USER_ROOT}/xdg/state/sarus-suite/logs" \
    "${USER_ROOT}/xdg/cache"
  if [ -e "$PARALLAX_STORE" ] || [ -L "$PARALLAX_STORE" ]; then
    [ -d "$PARALLAX_STORE" ] || die "Parallax store is not a directory: ${PARALLAX_STORE}"
    [ -w "$PARALLAX_STORE" ] || die "Parallax store is not writable: ${PARALLAX_STORE}"
  else
    install -d -m 0700 "$PARALLAX_STORE"
  fi
  for path in "$PODMAN_GRAPHROOT" "$PODMAN_RUNROOT"; do
    [ -z "$path" ] || [ -d "$path" ] || install -d -m 0700 "$path"
  done
  if [ -e "$user_policy" ] || [ -L "$user_policy" ]; then
    printf '%-14s %s\n' USING "existing user policy ${user_policy}" >> "$report_tmp"
  elif [ -e "$system_policy" ] || [ -L "$system_policy" ]; then
    printf '%-14s %s\n' USING "existing system policy ${system_policy}" >> "$report_tmp"
  else
    check_parent_chain "$user_policy"
    for dir in "${HOME}/.config" "${HOME}/.config/containers"; do
      [ -d "$dir" ] || install -d -m 0700 "$dir"
    done
    install -m 0644 "${stage_root}/xdg/config/containers/policy.json" "$user_policy"
    printf '%-14s %s\n' CREATED "user policy ${user_policy} (image signatures not required)" >> "$report_tmp"
  fi
  install -m 0600 "$report_tmp" "$report_dest"
  rm -f "$report_tmp"
  cat "$report_dest"
  printf 'Installation complete. Persistent report: %s\n' "$report_dest"
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

#####################################
# PARSE MODE AND OPTIONS
#####################################
# Init the runtime state and defaults
BUNDLE_ROOT=""
OUTPUT_DIR=""
PREFIX="/opt/sarus-suite"
PARALLAX_STORE='${HOME}/.sarus-suite/ro-store'
PARALLAX_STORE_SET=0
PODMAN_GRAPHROOT=""
PODMAN_RUNROOT=""
IMPORT_BINARY_SPECS=()
IMPORT_HOOK_DIRS=()
MODE="stage"
INSTALL_ROOT=""
REPORT_FILE="/var/log/sarus-suite-install-report.txt"
USER_ROOT="${HOME:-}/.sarus-suite"
SHELL_INIT="auto"
FORCE=0
DRY_RUN=0

# Select exec mode (default: stage)
if [ "$#" -gt 0 ]; then
  case "$1" in
    stage|apply|user|user-uninstall) MODE="$1"; shift ;;
  esac
fi

# parse command line args
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle-root) [ $# -ge 2 ] || die "--bundle-root requires a directory"; BUNDLE_ROOT="$2"; shift 2 ;;
    --output-dir) [ $# -ge 2 ] || die "--output-dir requires a directory"; OUTPUT_DIR="$2"; shift 2 ;;
    --parallax-store) [ $# -ge 2 ] || die "--parallax-store requires a path"; PARALLAX_STORE="$2"; PARALLAX_STORE_SET=1; shift 2 ;;
    --podman-graphroot) [ $# -ge 2 ] || die "--podman-graphroot requires a path"; PODMAN_GRAPHROOT="$2"; shift 2 ;;
    --podman-runroot) [ $# -ge 2 ] || die "--podman-runroot requires a path"; PODMAN_RUNROOT="$2"; shift 2 ;;
    --import-binary) [ $# -ge 2 ] || die "--import-binary requires PATH[:NAME]"; IMPORT_BINARY_SPECS+=("$2"); shift 2 ;;
    --import-hook-dir) [ $# -ge 2 ] || die "--import-hook-dir requires a directory"; IMPORT_HOOK_DIRS+=("$2"); shift 2 ;;
    --install-root) [ $# -ge 2 ] || die "--install-root requires a directory"; INSTALL_ROOT="$2"; shift 2 ;;
    --report) [ $# -ge 2 ] || die "--report requires a file"; REPORT_FILE="$2"; shift 2 ;;
    --user-root) [ $# -ge 2 ] || die "--user-root requires a directory"; USER_ROOT="$2"; shift 2 ;;
    --shell-init) [ $# -ge 2 ] || die "--shell-init requires auto, none, or a file"; SHELL_INIT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

# argument validation and required host commands
[ "$MODE" = user-uninstall ] || [ -n "$BUNDLE_ROOT" ] || die "--bundle-root is required"
[ "$MODE" != stage ] || [ -n "$OUTPUT_DIR" ] || die "--output-dir is required for stage"
[ "$MODE" = stage ] || [ -z "$OUTPUT_DIR" ] || die "--output-dir is only valid for stage"
require_cmd basename
require_cmd find
require_cmd grep
require_cmd install
require_cmd cmp
require_cmd mktemp
require_cmd sed
require_cmd sort
require_cmd stat
if ! command -v sha256sum >/dev/null 2>&1; then
  require_cmd shasum
fi

# Bundle coherency check
BUNDLE_ROOT="$(strip_trailing_slash "$BUNDLE_ROOT")"
if [ -n "$OUTPUT_DIR" ]; then OUTPUT_DIR="$(strip_trailing_slash "$OUTPUT_DIR")"; fi
if [ -n "$INSTALL_ROOT" ]; then INSTALL_ROOT="$(strip_trailing_slash "$INSTALL_ROOT")"; fi
USER_ROOT="$(strip_trailing_slash "$USER_ROOT")"
REPORT_FILE="$(strip_trailing_slash "$REPORT_FILE")"
if [ -n "$PODMAN_GRAPHROOT" ]; then PODMAN_GRAPHROOT="$(strip_trailing_slash "$PODMAN_GRAPHROOT")"; fi
if [ -n "$PODMAN_RUNROOT" ]; then PODMAN_RUNROOT="$(strip_trailing_slash "$PODMAN_RUNROOT")"; fi
[ "$MODE" = user-uninstall ] || require_absolute_path --bundle-root "$BUNDLE_ROOT"
if [ "$MODE" = stage ]; then
  require_absolute_path --output-dir "$OUTPUT_DIR"
  [ "$OUTPUT_DIR" != "/" ] || die "--output-dir cannot be the filesystem root"
fi
[ -z "$INSTALL_ROOT" ] || require_absolute_path --install-root "$INSTALL_ROOT"
require_absolute_path --report "$REPORT_FILE"
if [ "$MODE" = user ]; then
  [ "$(uname -s)" = Linux ] || die "user installation is supported only on Linux"
  [ "${EUID}" -ne 0 ] || die "user installation must not run as root"
  [ -n "${HOME:-}" ] || die "HOME is required for user installation"
  [ -z "$INSTALL_ROOT" ] || die "--install-root is not valid for user installation"
  [ "$REPORT_FILE" = /var/log/sarus-suite-install-report.txt ] || die "--report is not valid for user installation"
  require_absolute_path --user-root "$USER_ROOT"
  [ "$USER_ROOT" != / ] || die "--user-root cannot be the filesystem root"
  if [ "$PARALLAX_STORE_SET" -eq 0 ]; then
    PARALLAX_STORE="${USER_ROOT}/xdg/data/sarus-suite/parallax/ro-store"
  fi
  if [ -z "$PODMAN_GRAPHROOT" ]; then
    PODMAN_GRAPHROOT="${USER_ROOT}/xdg/data/containers/storage"
  fi
  require_absolute_path --parallax-store "$PARALLAX_STORE"
  for path in "$PODMAN_GRAPHROOT" "$PODMAN_RUNROOT"; do
    [ -n "$path" ] || continue
    require_absolute_path "Podman storage path" "$path"
    [ "$path" != / ] || die "Podman storage path cannot be the filesystem root"
  done
  [ -z "$PODMAN_GRAPHROOT" ] || [ "$PODMAN_GRAPHROOT" != "$PODMAN_RUNROOT" ] || die "--podman-graphroot and --podman-runroot must differ"
  case "$SHELL_INIT" in
    auto|none) ;;
    *) require_absolute_path --shell-init "$SHELL_INIT" ;;
  esac
elif [ "$MODE" = user-uninstall ]; then
  [ "$(uname -s)" = Linux ] || die "user uninstallation is supported only on Linux"
  [ "${EUID}" -ne 0 ] || die "user uninstallation must not run as root"
  [ -n "${HOME:-}" ] || die "HOME is required for user uninstallation"
  [ -z "$INSTALL_ROOT" ] || die "--install-root is not valid for user uninstallation"
  [ "$REPORT_FILE" = /var/log/sarus-suite-install-report.txt ] || die "--report is not valid for user uninstallation"
  require_absolute_path --user-root "$USER_ROOT"
  [ "$USER_ROOT" != / ] || die "--user-root cannot be the filesystem root"
  [ "$USER_ROOT" != "$HOME" ] || die "--user-root cannot be the home directory"
  case "$SHELL_INIT" in
    auto|none) ;;
    *) require_absolute_path --shell-init "$SHELL_INIT" ;;
  esac
  [ "$PARALLAX_STORE_SET" -eq 0 ] || die "--parallax-store is not valid for user uninstallation"
  [ -z "$PODMAN_GRAPHROOT" ] || die "--podman-graphroot is not valid for user uninstallation"
  [ -z "$PODMAN_RUNROOT" ] || die "--podman-runroot is not valid for user uninstallation"
  uninstall_user_payload
  exit 0
else
  [ "$USER_ROOT" = "${HOME:-}/.sarus-suite" ] || die "--user-root is only valid for user installation"
  [ "$SHELL_INIT" = auto ] || die "--shell-init is only valid for user installation"
  [ -z "$PODMAN_GRAPHROOT" ] || die "--podman-graphroot is only valid for user installation"
  [ -z "$PODMAN_RUNROOT" ] || die "--podman-runroot is only valid for user installation"
  case "$PARALLAX_STORE" in
    '$HOME/'*|'${HOME}/'*) ;;
    *) require_absolute_path --parallax-store "$PARALLAX_STORE" ;;
  esac
fi

[ -d "${BUNDLE_ROOT}/bin" ] || die "bundle bin directory not found: ${BUNDLE_ROOT}/bin"
[ -d "${BUNDLE_ROOT}/libexec/oci/hooks" ] || die "bundle hook directory not found"
[ -f "${BUNDLE_ROOT}/etc/containers/containers.conf" ] || die "bundle containers.conf not found"
[ -f "${BUNDLE_ROOT}/etc/containers/storage.conf" ] || die "bundle storage.conf not found"
[ -f "${BUNDLE_ROOT}/etc/parallax/parallax-mount.conf" ] || die "bundle parallax-mount.conf not found"
[ -f "${BUNDLE_ROOT}/etc/sarus-suite/90-sarusctl.conf" ] || die "bundle sarusctl configuration not found"
[ -f "${BUNDLE_ROOT}/etc/containers/policy.json" ] || die "bundle policy.json not found"
[ -f "${BUNDLE_ROOT}/etc/containers/seccomp.json" ] || die "bundle seccomp.json not found"
[ -x "${BUNDLE_ROOT}/libexec/sarus-suite/install.sh" ] || die "bundle installer not found"
[ "$MODE" != user ] || [ -x "${BUNDLE_ROOT}/libexec/sarus-suite/user-launch.sh" ] || die "bundle user launcher not found"
if [ "$MODE" = stage ]; then
  if [ -e "$OUTPUT_DIR" ] && [ -n "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    die "output directory is not empty: ${OUTPUT_DIR}"
  fi
  install -d -m 0755 "$OUTPUT_DIR"
fi

## Setup look-up table for binary import mechanism with (binary name, binary_path)
IMPORT_BINARY_NAMES=()
IMPORT_BINARY_PATHS=()
IMPORT_HOOK_NAMES=()
IMPORT_HOOK_PATHS=()
for spec in "${IMPORT_BINARY_SPECS[@]}"; do register_binary "$spec"; done
for dir in "${IMPORT_HOOK_DIRS[@]}"; do register_hook_dir "$dir"; done


#####################################
# USER MODE
#####################################
if [ "$MODE" = user ]; then
  ## Setup of staging area for user-mode install
  USER_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sarus-suite-user-install.XXXXXX")"
  trap 'rm -rf "${USER_WORK_DIR}"' EXIT INT TERM
  OUTPUT_DIR="${USER_WORK_DIR}/payload"
  install -d -m 0755 "$OUTPUT_DIR"

  USER_PAYLOAD_BIN="${USER_ROOT}/libexec/sarus-suite/bin"
  USER_HOOK_DIR="${USER_ROOT}/libexec/sarus-suite/oci/hooks"
  USER_CONFIG_HOME="${USER_ROOT}/xdg/config"
  USER_STATE_DIR="${USER_ROOT}/xdg/state/sarus-suite"

  ## Copy bundle binary resources
  for src in "${BUNDLE_ROOT}/bin"/*; do
    [ -f "$src" ] || continue
    [ -x "$src" ] || die "bundle bin entry is not executable: ${src}"
    name="$(basename "$src")"
    case "$name" in
      sarus-suite-shell|sarus-suite-system-install|sarus-suite-user-install|sarus-suite-user-uninstall) continue ;;
    esac
    contains_name "$name" "${IMPORT_BINARY_NAMES[@]}" && continue
    contains_name "$name" "${IMPORT_HOOK_NAMES[@]}" && continue
    copy_file "$src" "/libexec/sarus-suite/bin/${name}" 0755
  done
  for src in "${BUNDLE_ROOT}/libexec/oci/hooks"/*; do
    [ -f "$src" ] || continue
    [ -x "$src" ] || die "bundle hook entry is not executable: ${src}"
    name="$(basename "$src")"
    contains_name "$name" "${IMPORT_HOOK_NAMES[@]}" && continue
    copy_file "$src" "/libexec/sarus-suite/oci/hooks/${name}" 0755
  done
  for ((i = 0; i < ${#IMPORT_BINARY_NAMES[@]}; i++)); do
    copy_file "${IMPORT_BINARY_PATHS[$i]}" "/libexec/sarus-suite/bin/${IMPORT_BINARY_NAMES[$i]}" 0755
  done
  for ((i = 0; i < ${#IMPORT_HOOK_NAMES[@]}; i++)); do
    name="${IMPORT_HOOK_NAMES[$i]}"
    copy_file "${IMPORT_HOOK_PATHS[$i]}" "/libexec/sarus-suite/oci/hooks/${name}" 0755
    copy_file "${IMPORT_HOOK_PATHS[$i]}" "/libexec/sarus-suite/bin/${name}" 0755
  done

  ## Install launched and public command thin wrappers
  copy_file "${BUNDLE_ROOT}/libexec/sarus-suite/user-launch.sh" /libexec/sarus-suite/launch 0755
  copy_file "${BUNDLE_ROOT}/libexec/sarus-suite/install.sh" /libexec/sarus-suite/install.sh 0755
  for name in sarusctl podman parallax sarus-suite-check; do
    [ -x "${BUNDLE_ROOT}/bin/${name}" ] || die "bundle public command not found: ${name}"
    write_user_command_wrapper "$(payload_path "/bin/${name}")" "$name"
  done
  write_user_uninstall_wrapper "$(payload_path /bin/sarus-suite-user-uninstall)"

  ## Render the private bundle XDG
  render_user_template "${BUNDLE_ROOT}/etc/containers/containers.conf" "$(payload_path /xdg/config/containers/containers.conf)"
  render_user_template "${BUNDLE_ROOT}/etc/containers/storage.conf" "$(payload_path /xdg/config/containers/storage.conf)"
  render_user_template "${BUNDLE_ROOT}/etc/parallax/parallax-mount.conf" "$(payload_path /xdg/config/parallax/parallax-mount.conf)"
  render_user_template "${BUNDLE_ROOT}/etc/sarus-suite/90-sarusctl.conf" "$(payload_path /xdg/config/sarus-suite/90-sarusctl.conf)"

  ## Copy bundle config resources
  copy_file "${BUNDLE_ROOT}/etc/containers/registries.conf" /xdg/config/containers/registries.conf 0644
  copy_file "${BUNDLE_ROOT}/etc/containers/policy.json" /xdg/config/containers/policy.json 0644
  copy_file "${BUNDLE_ROOT}/etc/containers/seccomp.json" /xdg/config/containers/seccomp.json 0644
  copy_file "${BUNDLE_ROOT}/etc/containers/containers.conf.modules/hpc" /xdg/config/containers/containers.conf.modules/hpc 0644
  copy_tree "${BUNDLE_ROOT}/etc/containers/registries.d" /xdg/config/containers/registries.d 0644
  copy_tree "${BUNDLE_ROOT}/etc/cdi" /xdg/config/cdi 0644
  for src in "${BUNDLE_ROOT}/etc/containers/oci/hooks.d"/*; do
    [ -f "$src" ] || continue
    render_user_template "$src" "$(payload_path "/xdg/config/containers/oci/hooks.d/$(basename "$src")")"
  done
  copy_tree "${BUNDLE_ROOT}/examples" /share/examples 0644
  copy_tree "${BUNDLE_ROOT}/share" /share 0644

  ## Resolve and validate user shell before recording installation metadata
  shell_init_file="$(resolve_shell_init)"
  validate_user_shell_init "$shell_init_file"

  ## Write environment metadata and install manifest
  manifest="$(payload_path /install/manifest.txt)"
  install -d -m 0755 "$(dirname "$manifest")"
  {
    printf 'SARUS_SUITE_INSTALLED_PARALLAX_STORE=%q\n' "$PARALLAX_STORE"
    printf 'SARUS_SUITE_INSTALLED_PODMAN_GRAPHROOT=%q\n' "$PODMAN_GRAPHROOT"
    printf 'SARUS_SUITE_INSTALLED_PODMAN_RUNROOT=%q\n' "$PODMAN_RUNROOT"
  } > "$(payload_path /install/environment.sh)"
  chmod 0644 "$(payload_path /install/environment.sh)"
  {
    printf 'install_mode=user\n'
    printf 'install_root=%s\n' "$USER_ROOT"
    printf 'bin_dir=%s\n' "$USER_PAYLOAD_BIN"
    printf 'hook_dir=%s\n' "$USER_HOOK_DIR"
    printf 'config_home=%s\n' "$USER_CONFIG_HOME"
    printf 'state_dir=%s\n' "$USER_STATE_DIR"
    printf 'shell_init=%s\n' "$shell_init_file"
    printf 'parallax_store=%s\n' "$PARALLAX_STORE"
    printf 'podman_graphroot=%s\n' "$PODMAN_GRAPHROOT"
    printf 'podman_runroot=%s\n' "${PODMAN_RUNROOT:-XDG default}"
  } > "$manifest"
  for ((i = 0; i < ${#IMPORT_BINARY_NAMES[@]}; i++)); do
    printf 'import_binary.%s.source=%s\n' "${IMPORT_BINARY_NAMES[$i]}" "${IMPORT_BINARY_PATHS[$i]}" >> "$manifest"
    printf 'import_binary.%s.sha256=%s\n' "${IMPORT_BINARY_NAMES[$i]}" "$(sha256_file "${IMPORT_BINARY_PATHS[$i]}")" >> "$manifest"
  done
  for ((i = 0; i < ${#IMPORT_HOOK_NAMES[@]}; i++)); do
    printf 'import_hook.%s.source=%s\n' "${IMPORT_HOOK_NAMES[$i]}" "${IMPORT_HOOK_PATHS[$i]}" >> "$manifest"
    printf 'import_hook.%s.sha256=%s\n' "${IMPORT_HOOK_NAMES[$i]}" "$(sha256_file "${IMPORT_HOOK_PATHS[$i]}")" >> "$manifest"
  done
  chmod 0644 "$manifest"

  ## Sanity checks on staged dir
  # Check we did render all templated entries
  if grep -R '@@SARUS_SUITE_' "$(payload_path /xdg/config)" >/dev/null 2>&1; then
    die "unrendered Sarus Suite placeholder in user configuration"
  fi
  # Check the stating dir path has not been baked into the staged bundle, as the stage dir will be deleted after done
  if grep -R -F "$OUTPUT_DIR" "$OUTPUT_DIR" >/dev/null 2>&1; then
    die "staging path leaked into user installation"
  fi

  # Apply the staging dir to the user root
  apply_user_payload "$OUTPUT_DIR"
  # Now we modify the shell startup
  write_user_shell_init "$shell_init_file"
  # if we could not modify the user shell, tell the user to update PATH. Normally, we are good to go
  if [ -z "$shell_init_file" ]; then
    printf 'Add %s/bin to PATH to use the installed commands.\n' "$USER_ROOT"
  else
    printf 'Start a new shell to use sarusctl, podman, parallax, and sarus-suite-check.\n'
  fi
  exit 0
fi


#####################################
# APPLY MODE
#####################################
if [ "$MODE" = apply ]; then
  # Validate the target
  require_apply_target
  
  # Create temporary work directory
  APPLY_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sarus-suite-install.XXXXXX")"
  trap 'rm -rf "${APPLY_WORK_DIR}"' EXIT INT TERM

  # recursive invocation in stage mode!
  STAGE_ARGS=(stage --bundle-root "$BUNDLE_ROOT" --output-dir "${APPLY_WORK_DIR}/payload" --parallax-store "$PARALLAX_STORE")
  for spec in "${IMPORT_BINARY_SPECS[@]}"; do STAGE_ARGS+=(--import-binary "$spec"); done
  for dir in "${IMPORT_HOOK_DIRS[@]}"; do STAGE_ARGS+=(--import-hook-dir "$dir"); done
  "$0" "${STAGE_ARGS[@]}"

  # Apply the staged payload (either dry-run or dev install)
  apply_staged_payload "${APPLY_WORK_DIR}/payload"
  exit 0
fi


#####################################
# STAGE MODE
#####################################

BIN_DIR="${PREFIX}/bin"
HOOK_DIR="${PREFIX}/libexec/oci/hooks"
SHARE_DIR="${PREFIX}/share"
src=""
name=""
mode=""

#################################################################################
# Copy artifact from bundle to target location and apply replacement/injection
#################################################################################
for src in "${BUNDLE_ROOT}/bin"/*; do
  [ -f "$src" ] || continue
  [ -x "$src" ] || die "bundle bin entry is not executable: ${src}"
  name="$(basename "$src")"
  case "$name" in
    sarus-suite-system-install|sarus-suite-user-install|sarus-suite-user-uninstall) continue ;;
  esac
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

#################################################################################
# Render the templates and copy files (placeholders and final paths are resolved)
#################################################################################
render_template "${BUNDLE_ROOT}/etc/containers/containers.conf" "$(payload_path /etc/containers/containers.conf)"
render_template "${BUNDLE_ROOT}/etc/containers/storage.conf" "$(payload_path /etc/containers/storage.conf)"
render_template "${BUNDLE_ROOT}/etc/parallax/parallax-mount.conf" "$(payload_path /etc/parallax-mount.conf)"
render_template "${BUNDLE_ROOT}/etc/sarus-suite/90-sarusctl.conf" "$(payload_path /etc/sarus-suite/90-sarusctl.conf)"
copy_file "${BUNDLE_ROOT}/etc/containers/registries.conf" /etc/containers/registries.conf 0644
copy_file "${BUNDLE_ROOT}/etc/containers/policy.json" /etc/containers/policy.json 0644
copy_file "${BUNDLE_ROOT}/etc/containers/seccomp.json" /etc/containers/seccomp.json 0644
copy_file "${BUNDLE_ROOT}/etc/containers/containers.conf.modules/hpc" /etc/containers/containers.conf.modules/hpc 0644
copy_tree "${BUNDLE_ROOT}/etc/containers/registries.d" /etc/containers/registries.d 0644
copy_tree "${BUNDLE_ROOT}/etc/cdi" /etc/cdi 0644
for src in "${BUNDLE_ROOT}/etc/containers/oci/hooks.d"/*; do
  [ -f "$src" ] || continue
  render_template "$src" "$(payload_path "/etc/containers/oci/hooks.d/$(basename "$src")")"
done
copy_tree "${BUNDLE_ROOT}/examples" "${SHARE_DIR}/examples" 0644
copy_tree "${BUNDLE_ROOT}/share" "$SHARE_DIR" 0644

########################
# profile and manifest
########################
# Write profile.d entry
install -d -m 0755 "$(payload_path /etc/sarus-suite)" "$(payload_path /etc/profile.d)"
cat > "$(payload_path /etc/profile.d/sarus-suite.sh)" <<PROFILE
# Generated while building the Sarus Suite system package.
_sarus_suite_bin=${BIN_DIR}
case ":\${PATH:-}:" in
  *":\${_sarus_suite_bin}:"*) ;;
  *) PATH="\${_sarus_suite_bin}\${PATH:+:\${PATH}}"; export PATH ;;
esac
unset _sarus_suite_bin
PROFILE
chmod 0644 "$(payload_path /etc/profile.d/sarus-suite.sh)"

# build manifest
manifest="$(payload_path "${SHARE_DIR}/system-build-manifest.txt")"
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

#######################
## Final sanity checks
#######################
# Check all template placeholders got resolved
if grep -R '@@SARUS_SUITE_' "$(payload_path /etc)" >/dev/null 2>&1; then
  die "unrendered Sarus Suite placeholder in system configuration"
fi
# Check all references point to final locations, note temp staging
if grep -R -F "$OUTPUT_DIR" "$(payload_path /etc)" "$manifest" >/dev/null 2>&1; then
  die "staging path leaked into packaged configuration"
fi

# Declare success
printf 'System package payload assembled at %s\n' "$OUTPUT_DIR"

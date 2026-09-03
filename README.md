# Sarus Suite

Sarus Suite is a self-contained bundle for running Sarus containers on Linux.
It includes `sarusctl`, Podman, Parallax, filesystem and FUSE helpers, OCI
hooks, configuration, and diagnostic tools in one directory.

## Quick start

Download the bundle for your host architecture (`amd64` or `arm64`) from the
[GitHub releases](https://github.com/sarus-suite/sarus-suite/releases):

```sh
VERSION=v26.8.3
ARCH=amd64

curl -LO "https://github.com/sarus-suite/sarus-suite/releases/download/${VERSION}/sarus-suite-${VERSION}-${ARCH}.tar.gz"
tar -xzf "sarus-suite-${VERSION}-${ARCH}.tar.gz"
cd sarus-suite
```

Run commands inside the self-contained environment:

```sh
./bin/sarus-suite-shell -- bash -lc \
  'sarusctl run examples/ubuntu.toml cat /etc/os-release'
```

To open an interactive shell instead:

```sh
./bin/sarus-suite-shell
```

The bundle contains example EDF files at `examples/ubuntu.toml` and
`examples/debian.toml`. Check the local setup with:

```sh
./bin/sarus-suite-check
```

## System-wide installation for development

To make the bundled commands available to all users on a Linux host:

```sh
sudo ./bin/sarus-suite-system-install
```

This installs commands under `/usr/local/bin`, configuration under `/etc`,
and a per-user Parallax image store at `~/.sarus-suite/ro-store`. Start a new
login shell after installation, then use `podman`, `parallax`, `sarusctl`, or
`sarus-suite-check` directly.

Preview the installation without changing the host:

```sh
./bin/sarus-suite-system-install --dry-run
```

The installer refuses to replace differing files unless `--force` is supplied.
Use `--help` for deployment options such as `--prefix`, `--bin-dir`,
`--parallax-store`, `--install-root`, and `--report`.

## Testing local builds

A downloaded bundle can temporarily use locally built components:

```sh
./bin/sarus-suite-shell \
  --import-binary /path/to/sarusctl \
  --import-binary /path/to/parallax-static:parallax \
  --import-hook-dir /path/to/performance-extensions/target/release
```

Imported files replace the matching files in the extracted bundle. Use a copy
of the bundle when you need to preserve the original files.

## Building

Build a self-contained bundle with:

```sh
./scripts/build-bundle.sh
```

The build fetches upstream components, builds the helpers, assembles the
runtime tree under `dist/`, verifies it, and creates a compressed tarball.
The default Podman build is glibc-linked; use `PODMAN_MODE=static` for the
static fallback in a supported Alpine build environment.

The build requires `git`, `tar`, `curl` or `wget`, and either the
`devcontainer` CLI with a Docker/Podman backend or a supported Alpine build
environment. Build logs are written under `.work/logs/`; set `VERBOSE=1` to
stream full output. RPM packaging is available with:

```sh
./scripts/build-rpm.sh
```

## Runtime requirements

The target Linux host needs:

- unprivileged user namespaces;
- FUSE support;
- rootless container setup, including `/etc/subuid` and `/etc/subgid`; and
- `uidmap`, `newuidmap`, and `newgidmap` support.

AppArmor may also need to be configured to allow user namespaces.

For bundle layout details, see [sarus-suite-bundle-artifacts.d2](sarus-suite-bundle-artifacts.d2).

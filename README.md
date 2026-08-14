# sarus-suite

This repository packages the moving parts needed by Sarus-Suite, an HPC-style container runtime into one tarball: sarusctl, static Podman, Parallax, FUSE/SquashFS helpers, configs, and launch/check scripts.

## What it does

* Fetches and builds upstream componets for sarus-suite.
* Provide builder scripts that produce static-built dependency binaries.
* Assembles everything into a structured tar.gz
* Provides sarus-suite-shell, which creates private config/state dirs and puts bundled tools on PATH.
* Configures Podman overlay storage to use a Parallax-aware mount program and a read-only Parallax image store.


## Try the released bundle locally

The release tarball is the fastest way to try the Sarus Suite runtime on a Linux machine. It includes Podman, Sarus tooling, Parallax, FUSE/SquashFS
helpers, default configs, examples, and check scripts in one portable directory.

Pick the artifact for your host architecture:

```sh
VERSION=v26.7.3
ARCH=amd64   # or arm64

curl -LO "https://github.com/sarus-suite/sarus-suite/releases/download/${VERSION}/sarus-suite-${VERSION}-${ARCH}.tar.gz"
tar -xzf "sarus-suite-${VERSION}-${ARCH}.tar.gz"

```

Enter the bundled environment and inspect the bundled EDF examples:

```sh
./sarus-suite/bin/sarus-suite-shell

cat "./sarus-suite/examples/ubuntu.toml"
cat "./sarus-suite/examples/debian.toml"

sarusctl run ./sarus-suite/examples/ubuntu.toml cat /etc/os-release
sarusctl run ./sarus-suite/examples/debian.toml cat /etc/os-release
```

## Test local component binaries

To test a locally built component with a downloaded bundle, import the new
artifact while entering `sarus-suite-shell`:

```sh
./sarus-suite/bin/sarus-suite-shell \
  --import-binary /path/to/sarusctl \
  --import-binary /path/to/parallax-static:parallax
```

Performance-extension hooks can be imported from a build output directory:

```sh
./sarus-suite/bin/sarus-suite-shell \
  --import-hook-dir /path/to/performance-extensions/target/release
```

`--import-hook-dir` copies every executable file in the directory into the
bundle hook location and mirrors it into `bin/`.

## Install the bundle system-wide

On a Linux host, the bundle can be installed once for all users instead of
entering `sarus-suite-shell` for every session:

```sh
sudo ./sarus-suite/bin/sarus-suite-system-install
```

The default installation:

* copies commands to `/usr/local/bin` and OCI hook executables to
  `/usr/local/libexec/sarus-suite/oci/hooks`;
* renders Podman configuration below `/etc/containers`, Parallax configuration
  at `/etc/parallax-mount.conf`, and sarusctl configuration below
  `/etc/sarus-suite`;
* configures a separate Parallax store for each user at
  `~/.sarus-suite/ro-store`, created on first Sarus use;
* installs `/etc/profile.d/sarus-suite.sh` so the selected binary directory is
  on `PATH` in future login shells; and
* writes and prints `/var/log/sarus-suite-install-report.txt`, listing every
  created, updated, and unchanged path considered by the installation.

Podman's graph and runtime roots are intentionally not made global. Rootless
users continue to get Podman's normal per-user writable storage, and each user
gets an independent Parallax image store. Sarusctl passes that resolved store
to Podman for each invocation, avoiding an invalid dynamic path in Podman's
system-wide storage configuration. Parallax mount temporary files and logs also
retain their per-user `/tmp/parallax-<uid>` defaults.

The installer performs a complete collision check before it writes anything.
It refuses to replace a differing file unless `--force` is supplied. Preview
an installation and its report without modifying the host with:

```sh
./sarus-suite/bin/sarus-suite-system-install --dry-run
```

Common deployment overrides include `--prefix`, `--bin-dir`,
`--parallax-store`, and `--report`. Supplying `--state-dir` retains the legacy
shared-store layout at `STATE_DIR/parallax/ro-store`; it is not needed for the
default per-user store. `--install-root` stages the same logical system layout
below another directory for image/package construction. Run
`sarus-suite-system-install --help` for the complete interface.

After installation, start a new login shell and invoke `podman`, `parallax`,
`sarusctl`, or `sarus-suite-check` directly. `sarus-suite-shell` is not needed.

## Build bundle

Run the full bundle build with:

```sh
./scripts/build-bundle.sh
```

Direct requirements:

* `git`
* `tar`
* `curl` or `wget`
* `devcontainer` CLI with a working Docker or Podman backend
  or an Alpine build environment with the needed toolchains available

The script fetches Parallax, `sarusctl`, and `performance-extensions`,
downloads static Podman artifacts, builds the helper binaries, assembles the
runtime tree under `dist/`, verifies it, and writes a `.tar.gz` bundle.

## Target runtime requirements

The generated bundle expects a Linux target host with:

* Unprivileged user namespaces enabled in the kernel
* AppArmor configured to allow user namespaces, where applicable
* FUSE support available
* Rootless container prerequisites configured, including subordinate UID/GID
  ranges in `/etc/subuid` and `/etc/subgid`
* `uidmap`/`newuidmap`/`newgidmap` support available on the target host

## Temporary notes

Note: this repo currently defaults to the Parallax `parallax-static`
branch because it still carries the Alpine devcontainer and static build
scripts this bundle expects.

Once that branch is merged into `main`, switch the Parallax defaults in
`components.sh` back to `main` and remove this note.

TODO: revisit the scope of `sarus-suite-check` so it can validate bundle
structure and config consistency more generically, instead of relying so much
on hard-coded file names and specific optional layouts.

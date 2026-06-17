# sarus-suite

This repository packages the moving parts needed by Sarus-Suite, an HPC-style container runtime into one tarball: sarusctl, static Podman, Parallax, FUSE/SquashFS helpers, configs, and launch/check scripts.

## What it does

* Fetches and builds upstream componets for sarus-suite.
* Provide builder scripts that produce static-built dependency binaries.
* Assembles everything into a structured tar.gz
* Provides sarus-suite-shell, which creates private config/state dirs and puts bundled tools on PATH.
* Configures Podman overlay storage to use a Parallax-aware mount program and a read-only Parallax image store.


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

The script fetches Parallax and `sarusctl`, downloads static Podman artifacts,
builds the helper binaries, assembles the runtime tree under `dist/`, verifies
it, and writes a `.tar.gz` bundle.

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

Note: this repo also currently defaults to the `sarusctl-home-config`
branch from `sarus-suite/cluster-tooling` because it carries the Alpine
devcontainer and static `sarusctl` build flow this bundle expects.

Once that branch is merged into `main`, switch the `cluster-tooling` defaults
in `components.sh` back to `main` and remove this note.

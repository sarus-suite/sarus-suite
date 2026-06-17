# sarus-suite

This repository packages the moving parts needed for an HPC-style container runtime into one tarball: sarusctl, static Podman, Parallax, FUSE/SquashFS helpers, configs, and launch/check scripts.

## What it does

* Fetches and builds upstream componets for sarus-suite.
* Provide builder scripts that produce static-built dependency binaries.
* Assembles everything into a structured tar.gz
* Provides sarus-suite-shell, which creates private config/state dirs and puts bundled tools on PATH.
* Configures Podman overlay storage to use a Parallax-aware mount program and a read-only Parallax image store.


## Requirements

* Enable unprivileges user namespaces in the kernel
* Apparmor needs to be configured to allow user namespaces

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

# sarus-suite

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

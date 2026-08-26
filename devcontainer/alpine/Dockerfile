FROM alpine:3.22

ARG GO_VERSION=1.25.0
ARG RUST_VERSION=1.87.0
ARG RUSTUP_VERSION=1.29.0
ARG RUSTUP_INIT_SHA256_AMD64=9cd3fda5fd293890e36ab271af6a786ee22084b5f6c2b83fd8323cec6f0992c1
ARG RUSTUP_INIT_SHA256_ARM64=88761caacddb92cd79b0b1f939f3990ba1997d701a38b3e8dd6746a562f2a759

RUN apk add --no-cache \
        autoconf \
        automake \
        argp-standalone \
        bash \
        binutils \
        btrfs-progs \
        btrfs-progs-dev \
        build-base \
        ca-certificates \
        clang \
        curl \
        coreutils \
        file \
        fuse3-dev \
        fuse3-static \
        git \
        glib-static \
        gpgme-dev \
        iptables \
        json-c-dev \
        libcap-dev \
        libcap-static \
        libc-dev \
        inotify-tools \
        libassuan-dev \
        libseccomp-dev \
        libseccomp-static \
        libselinux-dev \
        libtool \
        lvm2-dev \
        linux-headers \
        lz4-dev \
        lz4-static \
        meson \
        musl-dev \
        ninja \
        openssl \
        ostree-dev \
        pax-utils \
        pcre2-static \
        pkgconf \
        protobuf-c-dev \
        protobuf-dev \
        python3 \
        rsync \
        shellcheck \
        slirp4netns \
        squashfs-tools \
        tar \
        tzdata \
        go-md2man \
        xz-dev \
        xz-static \
        zlib-dev \
        zlib-static \
        zstd-dev \
        zstd-static

COPY scripts/install-go.sh /tmp/install-go.sh
RUN chmod 0755 /tmp/install-go.sh && /tmp/install-go.sh "${GO_VERSION}" && rm -f /tmp/install-go.sh

ENV PATH="/usr/local/go/bin:${PATH}"

# Install a pinned rustup-init binary instead of executing the mutable
# sh.rustup.rs installer. Checksums are published alongside the archive.
RUN set -eu; \
    case "$(uname -m)" in \
        aarch64) rust_target='aarch64-unknown-linux-musl'; rustup_sha="${RUSTUP_INIT_SHA256_ARM64}" ;; \
        x86_64) rust_target='x86_64-unknown-linux-musl'; rustup_sha="${RUSTUP_INIT_SHA256_AMD64}" ;; \
        *) printf 'unsupported Rust build architecture: %s\n' "$(uname -m)" >&2; exit 1 ;; \
    esac; \
    rustup_url="https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${rust_target}/rustup-init"; \
    curl --proto '=https' --tlsv1.2 -fsSLo /tmp/rustup-init "${rustup_url}"; \
    printf '%s  %s\n' "${rustup_sha}" /tmp/rustup-init | sha256sum -c -; \
    chmod 0755 /tmp/rustup-init; \
    /tmp/rustup-init -y --profile minimal --default-toolchain none; \
    rm -f /tmp/rustup-init; \
    /root/.cargo/bin/rustup toolchain install "${RUST_VERSION}" --profile minimal --target "${rust_target}"; \
    /root/.cargo/bin/rustup default "${RUST_VERSION}"

ENV PATH="/root/.cargo/bin:${PATH}"

CMD ["bash"]

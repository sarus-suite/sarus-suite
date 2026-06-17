FROM alpine:3.22

ARG GO_VERSION=1.24.0

RUN apk add --no-cache \
        autoconf \
        automake \
        bash \
        binutils \
        build-base \
        ca-certificates \
        cargo \
        curl \
        file \
        fuse3-dev \
        fuse3-static \
        git \
        gpgme-dev \
        inotify-tools \
        libassuan-dev \
        libseccomp-dev \
        libselinux-dev \
        libtool \
        linux-headers \
        lz4-dev \
        lz4-static \
        meson \
        musl-dev \
        ninja \
        pax-utils \
        pkgconf \
        protobuf-c-dev \
        protobuf-dev \
        rsync \
        rust \
        slirp4netns \
        squashfs-tools \
        tar \
        xz-dev \
        xz-static \
        zlib-dev \
        zlib-static \
        zstd-dev \
        zstd-static

COPY scripts/install-go.sh /tmp/install-go.sh
RUN chmod 0755 /tmp/install-go.sh && /tmp/install-go.sh "${GO_VERSION}" && rm -f /tmp/install-go.sh

ENV PATH="/usr/local/go/bin:${PATH}"

CMD ["bash"]

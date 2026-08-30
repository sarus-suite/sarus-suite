FROM debian:12-slim

ARG GO_VERSION=1.25.0

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        bash \
        binutils \
        ca-certificates \
        curl \
        diffutils \
        file \
        findutils \
        g++ \
        gcc \
        git \
        gperf \
        libc6-dev \
        libapparmor-dev \
        libassuan-dev \
        libcap-dev \
        libfuse3-dev \
        libgpgme-dev \
        libjson-c-dev \
        libostree-dev \
        libpcre2-dev \
        libprotobuf-c-dev \
        libseccomp-dev \
        libselinux1-dev \
        libsepol-dev \
        libssl-dev \
        libtool \
        libzstd-dev \
        make \
        pkg-config \
        rpm \
        tar \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN test "$(getconf GNU_LIBC_VERSION)" = 'glibc 2.36'

COPY scripts/install-go.sh /tmp/install-go.sh
RUN chmod 0755 /tmp/install-go.sh \
    && /tmp/install-go.sh "${GO_VERSION}" \
    && rm -f /tmp/install-go.sh

ENV PATH="/usr/local/go/bin:${PATH}"

CMD ["bash"]

FROM rockylinux:8

ARG GO_VERSION=1.25.0

RUN dnf install -y dnf-plugins-core \
    && dnf config-manager --set-enabled powertools \
    && dnf install -y --setopt=install_weak_deps=False \
        autoconf \
        automake \
        bash \
        binutils \
        ca-certificates \
        curl \
        diffutils \
        file \
        findutils \
        fuse3-devel \
        gcc \
        gcc-c++ \
        git \
        gperf \
        glibc-devel \
        glibc-static \
        gpgme-devel \
        json-c-devel \
        libassuan-devel \
        libcap-devel \
        libtool \
        make \
        openssl-devel \
        ostree-devel \
        pcre2-devel \
        pkgconf-pkg-config \
        protobuf-c-devel \
        rpm \
        tar \
        zlib-devel \
        libzstd-devel \
    && dnf clean all \
    && rm -rf /var/cache/dnf

RUN test "$(getconf GNU_LIBC_VERSION)" = 'glibc 2.28'

COPY scripts/install-go.sh /tmp/install-go.sh
RUN chmod 0755 /tmp/install-go.sh \
    && /tmp/install-go.sh "${GO_VERSION}" \
    && rm -f /tmp/install-go.sh

ENV PATH="/usr/local/go/bin:${PATH}"

CMD ["bash"]

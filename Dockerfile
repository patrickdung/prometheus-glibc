# SPDX-License-Identifier: MIT

# bullseye npm & nodejs is too old
# https://github.com/prometheus/prometheus/issues/11724
#FROM docker.io/golang:1.19-bullseye AS build

FROM registry.access.redhat.com/ubi9/go-toolset:1.21.11-7.1724661022 AS build

# no apk
#FROM cgr.dev/chainguard/go:latest-glibc AS build

# no 'npm tar yarn (and golang)'
#FROM cgr.dev/chainguard/wolfi-base:latest AS build

ARG ARCH
## With Docker's buildx, TARGETARCH gives out amd64/arm64

ARG PROM_VERSION="2.54.1"
ARG CHECKSUM="3ee88a80f82e069073028862b3c92b1938bd932b059d25b37d093a6e221090d9"

ADD https://github.com/prometheus/prometheus/archive/v$PROM_VERSION.tar.gz /tmp/prometheus.tar.gz

USER root

# Build shared binary
# https://pkg.go.dev/cmd/link
# https://wiki.archlinux.org/title/Go_package_guidelines
ENV GOFLAGS='-buildmode=pie -ldflags=-linkmode=external'
ENV CGO_ENABLED=0

RUN set -eux && \
    ls -la /tmp && \
    [ "$(sha256sum /tmp/prometheus.tar.gz | awk '{print $1}')" = "$CHECKSUM" ] && \
    curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo && \
    rpm --import https://dl.yarnpkg.com/rpm/pubkey.gpg && \
    dnf --nodocs --setopt=install_weak_deps=0 --setopt=keepcache=0 \
      -y install --repo yarn yarn && \
    tar -C /tmp -xf /tmp/prometheus.tar.gz && \
    mkdir -p /go/src/github.com/prometheus && \
    mv /tmp/prometheus-${PROM_VERSION//+/-} /go/src/github.com/prometheus/prometheus && \
    cd /go/src/github.com/prometheus/prometheus && \
      yarn config set networkTimeout 3000000 && \
      make build && \
    dnf --nodocs --setopt=install_weak_deps=0 --setopt=keepcache=0 \
      -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
    dnf --nodocs --setopt=install_weak_deps=0 --setopt=keepcache=0 \
      -y install --repo epel jemalloc

RUN set -eux && \
    mkdir -p /rootfs/etc/prometheus && \
      cp -v /go/src/github.com/prometheus/prometheus/documentation/examples/prometheus.yml /rootfs/etc/prometheus/ && \
    mkdir -p /rootfs/bin && \
      cp -v /go/src/github.com/prometheus/prometheus/prometheus /rootfs/bin/prometheus && \
      cp -v /go/src/github.com/prometheus/prometheus/promtool /rootfs/bin/promtool && \
    mkdir -p /rootfs/usr/share/prometheus/ && \
      cp -v /go/src/github.com/prometheus/prometheus/console_libraries /rootfs/usr/share/prometheus/ && \
      cp -v /go/src/github.com/prometheus/prometheus/consoles /rootfs/usr/share/prometheus/ && \
    cp -v /go/src/github.com/prometheus/prometheus/LICENSE /rootfs/ && \
    cp -v /go/src/github.com/prometheus/prometheus/NOTICE /rootfs/ && \
    mkdir -p /rootfs/prometheus & \
    mkdir -p /rootfs/etc && \
      echo "nogroup:*:2000:nobody" > /rootfs/etc/group && \
      echo "nobody:*:1000:2000:::" > /rootfs/etc/passwd && \
    mkdir -p /rootfs/etc/ssl/certs && \
      cp -v /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /rootfs/etc/ssl/certs/ca-certificates.crt

#RUN set -eux && \
#    ls -la /go/src/github.com/prometheus/prometheus/prom* && \
#    ls -la /go/src/github.com/prometheus/prometheus/console*

# https://registry-ui.chainguard.app/?image=cgr.dev/chainguard/busybox:latest
# no jemalloc
FROM cgr.dev/chainguard/busybox:latest-glibc

#FROM docker.io/bitnami/minideb:bullseye

ARG LABEL_IMAGE_URL
ARG LABEL_IMAGE_SOURCE

LABEL org.opencontainers.image.url=${LABEL_IMAGE_URL}
LABEL org.opencontainers.image.source=${LABEL_IMAGE_SOURCE}

USER 0
WORKDIR /prometheus

RUN mkdir /usr/share/prometheus
COPY --from=build --chown=1000:2000 /rootfs /
COPY --from=build --chown=1000:2000 /go/src/github.com/prometheus/prometheus/prometheus /bin/prometheus
COPY --from=build --chown=1000:2000 /go/src/github.com/prometheus/prometheus/promtool /bin/promtool
COPY --from=build --chown=1000:2000 /go/src/github.com/prometheus/prometheus/console_libraries /usr/share/prometheus/console_libraries
COPY --from=build --chown=1000:2000 /go/src/github.com/prometheus/prometheus/consoles /usr/share/prometheus/consoles
COPY --from=build --chown=1000:2000 /go/src/github.com/prometheus/prometheus/npm_licenses.tar.bz2 /
COPY --from=build --chown=1000:2000 /usr/lib64/libjemalloc.so.2 /usr/lib64/libjemalloc.so.2

RUN set -eux && \
      ln -s /usr/share/prometheus/console_libraries /usr/share/prometheus/consoles/ /etc/prometheus/ && \
      chown -R 1000:2000 /etc/prometheus /prometheus && \
      ls -la /bin/prom* /usr/share/prometheus

USER 1000
ENV LD_PRELOAD=/usr/lib64/libjemalloc.so.2
#USER nobody
EXPOSE 9090/tcp
VOLUME [ "/prometheus" ]
ENTRYPOINT [ "/bin/prometheus" ]
CMD        [ "--config.file=/etc/prometheus/prometheus.yml", \
             "--storage.tsdb.path=/prometheus", \
             "--web.console.libraries=/usr/share/prometheus/console_libraries", \
             "--web.console.templates=/usr/share/prometheus/consoles" ]

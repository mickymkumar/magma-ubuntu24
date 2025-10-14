################################################################################
# Combined Magma Gateway Dockerfile (C + Python + Open vSwitch 1.9)
################################################################################

ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=focal
ARG EXTRA_REPO=https://linuxfoundation.jfrog.io/artifactory/magma-packages-test
ARG FEATURES=mme_oai

# -----------------------------------------------------------------------------
# Builder image for C binaries and Magma proto files
# -----------------------------------------------------------------------------
FROM $OS_DIST:$OS_RELEASE AS builder
ARG CPU_ARCH
ARG DEB_PORT
ARG OS_DIST
ARG OS_RELEASE
ARG EXTRA_REPO

ENV MAGMA_ROOT=/magma
ENV C_BUILD=/build/c
ENV OAI_BUILD=$C_BUILD/oai
ENV TZ=Europe/Paris
ENV CCACHE_DIR=${MAGMA_ROOT}/.cache/gateway/ccache
ENV MAGMA_DEV_MODE=0
ENV XDG_CACHE_HOME=${MAGMA_ROOT}/.cache

# Allow insecure repos (temporary workaround)
RUN echo "Acquire::AllowInsecureRepositories true;" > /etc/apt/apt.conf.d/99AllowInsecureRepositories \
    && echo "APT::Get::AllowUnauthenticated true;" >> /etc/apt/apt.conf.d/99AllowInsecureRepositories

# Base dependencies
RUN apt-get update && apt-get install -y \
    apt-utils software-properties-common apt-transport-https gnupg wget \
    autoconf autogen build-essential ccache check cmake curl git \
    libboost-chrono-dev libboost-context-dev libboost-program-options-dev \
    libboost-filesystem-dev libboost-regex-dev libc++-dev libconfig-dev \
    libcurl4-openssl-dev libczmq-dev libdouble-conversion-dev libgflags-dev \
    libgmp3-dev libgoogle-glog-dev libmnl-dev libpcap-dev libprotoc-dev \
    libsctp-dev libsqlite3-dev libssl-dev libtspi-dev libtool libxml2-dev \
    libxslt-dev libyaml-cpp-dev ninja-build nlohmann-json3-dev pkg-config \
    protobuf-compiler python3-pip sudo unzip uuid-dev \
    && rm -rf /var/lib/apt/lists/*

# Bazel setup
RUN wget -P /usr/sbin --progress=dot:giga https://github.com/bazelbuild/bazelisk/releases/download/v1.10.0/bazelisk-linux-"${DEB_PORT}" \
    && chmod +x /usr/sbin/bazelisk-linux-"${DEB_PORT}" \
    && ln -s /usr/sbin/bazelisk-linux-"${DEB_PORT}" /usr/sbin/bazel

WORKDIR $MAGMA_ROOT

# Copy bazel and proto files
COPY WORKSPACE.bazel BUILD.bazel .bazelignore .bazelrc .bazelversion $MAGMA_ROOT/
COPY bazel/ $MAGMA_ROOT/bazel/
COPY third_party/build/patches/libfluid/ $MAGMA_ROOT/third_party/build/patches/libfluid/
COPY feg/protos $MAGMA_ROOT/feg/protos
COPY feg/gateway/services/aaa/protos $MAGMA_ROOT/feg/gateway/services/aaa/protos
COPY lte/protos $MAGMA_ROOT/lte/protos
COPY orc8r/protos $MAGMA_ROOT/orc8r/protos
COPY protos $MAGMA_ROOT/protos

# Copy C code
COPY orc8r/gateway/c/common $MAGMA_ROOT/orc8r/gateway/c/common
COPY lte/gateway/c $MAGMA_ROOT/lte/gateway/c

# Copy Python scripts
COPY lte/gateway/python/scripts $MAGMA_ROOT/lte/gateway/python/scripts

# Build external dependencies
RUN bazel build \
    @com_github_grpc_grpc//:grpc++ \
    @com_google_protobuf//:protobuf \
    @prometheus_cpp//:prometheus-cpp \
    @yaml-cpp//:yaml-cpp \
    @github_nlohmann_json//:json \
    @sentry_native//:sentry

# Build C binaries
RUN bazel build --config=production \
    //lte/gateway/c/sctpd/src:sctpd \
    //lte/gateway/c/connection_tracker/src:connectiond \
    //lte/gateway/c/li_agent/src:liagentd \
    //lte/gateway/c/session_manager:sessiond \
    //lte/gateway/c/core:agw_of

# -----------------------------------------------------------------------------
# Runtime image (C + Python)
# -----------------------------------------------------------------------------
FROM $OS_DIST:$OS_RELEASE AS gateway_c
ARG CPU_ARCH
ARG OS_DIST
ARG OS_RELEASE

ENV MAGMA_ROOT=/magma
ENV TZ=Europe/Paris
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Runtime deps
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https apt-utils ca-certificates gnupg iproute2 iptables \
    libgoogle-glog-dev libidn11-dev libmnl-dev libprotoc-dev libsctp-dev \
    libtspi1 libyaml-cpp-dev net-tools netcat openssl psmisc sudo tshark tzdata wget \
    && rm -rf /var/lib/apt/lists/*

# Copy C binaries
COPY --from=builder /usr/lib/$CPU_ARCH-linux-gnu/lib* /usr/lib/$CPU_ARCH-linux-gnu/
COPY --from=builder /usr/local/lib/lib* /usr/local/lib/
COPY --from=builder $MAGMA_ROOT/bazel-bin/lte/gateway/c/session_manager/sessiond /usr/local/bin/sessiond
COPY --from=builder $MAGMA_ROOT/bazel-bin/lte/gateway/c/sctpd/src/sctpd /usr/local/bin/sctpd
COPY --from=builder $MAGMA_ROOT/bazel-bin/lte/gateway/c/connection_tracker/src/connectiond /usr/local/bin/connectiond
COPY --from=builder $MAGMA_ROOT/bazel-bin/lte/gateway/c/li_agent/src/liagentd /usr/local/bin/liagentd
COPY --from=builder $MAGMA_ROOT/bazel-bin/lte/gateway/c/core/agw_of /usr/local/bin/oai_mme

# Copy configs
COPY lte/gateway/configs /etc/magma
COPY orc8r/gateway/configs/templates /etc/magma/templates

# -----------------------------------------------------------------------------
# Open vSwitch 1.9
# -----------------------------------------------------------------------------
FROM $OS_DIST:$OS_RELEASE AS gateway_ovs
ARG CPU_ARCH
ARG OS_DIST
ARG OS_RELEASE
ARG EXTRA_REPO

ENV LINUX_HEADERS_VER=5.4.0-186-generic

# Base packages
RUN apt-get -q update && apt-get install -y --no-install-recommends \
    apt-utils ca-certificates apt-transport-https iptables iproute2 iputils-arping \
    iputils-clockdiff iputils-ping iputils-tracepath bridge-utils ifupdown vim \
    && rm -rf /var/lib/apt/lists/*

# Add Magma repo for OVS modules
COPY keys/linux_foundation_registry_key.asc /etc/apt/trusted.gpg.d/magma.asc
RUN echo "deb [trusted=yes] https://linuxfoundation.jfrog.io/artifactory/magma-packages focal-1.9 main" > /etc/apt/sources.list.d/magma.list
RUN apt-get update && apt-get install -y --no-install-recommends \
    libopenvswitch openvswitch-common openvswitch-switch openvswitch-datapath-dkms \
    linux-headers-${LINUX_HEADERS_VER} \
    && rm -rf /var/lib/apt/lists/*

# Copy OVS scripts
COPY --chmod=755 lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/
COPY --chmod=755 lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]

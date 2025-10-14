################################################################################
# Step 5: Builder image for C binaries and Magma proto files
################################################################################
ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=24.04
ARG EXTRA_REPO=https://linuxfoundation.jfrog.io/artifactory/magma-packages-test
ARG CLANG_VERSION=3.8
ARG FEATURES=mme_oai

FROM $OS_DIST:$OS_RELEASE AS builder_c
ARG CPU_ARCH
ARG DEB_PORT
ARG OS_DIST
ARG OS_RELEASE
ARG EXTRA_REPO
ARG CLANG_VERSION

ENV MAGMA_ROOT=/magma
ENV C_BUILD=/build/c
ENV OAI_BUILD=$C_BUILD/oai
ENV TZ=America/Toronto
ENV CCACHE_DIR=${MAGMA_ROOT}/.cache/gateway/ccache
ENV MAGMA_DEV_MODE=0
ENV XDG_CACHE_HOME=${MAGMA_ROOT}/.cache

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Temporary GPG workaround
RUN echo "Acquire::AllowInsecureRepositories true;" > /etc/apt/apt.conf.d/99AllowInsecureRepositories && \
    echo "APT::Get::AllowUnauthenticated true;" >> /etc/apt/apt.conf.d/99AllowInsecureRepositories

# Base tools and Bazelisk
RUN apt-get update && apt-get install -y \
    apt-utils software-properties-common apt-transport-https gnupg wget \
    && wget -P /usr/sbin https://github.com/bazelbuild/bazelisk/releases/download/v1.10.0/bazelisk-linux-"${DEB_PORT}" \
    && chmod +x /usr/sbin/bazelisk-linux-"${DEB_PORT}" \
    && ln -s /usr/sbin/bazelisk-linux-"${DEB_PORT}" /usr/sbin/bazel

# Build dependencies
RUN apt-get update && apt-get install -y \
    autoconf autogen build-essential ccache check cmake curl git \
    libboost-chrono-dev libboost-context-dev libboost-program-options-dev \
    libboost-filesystem-dev libboost-regex-dev libc++-dev libconfig-dev \
    libcurl4-openssl-dev libczmq-dev libdouble-conversion-dev libgflags-dev \
    libgmp3-dev libgoogle-glog-dev libmnl-dev libpcap-dev libprotoc-dev \
    libsctp-dev libsqlite3-dev libssl-dev libtspi-dev libtool libxml2-dev \
    libxslt-dev libyaml-cpp-dev ninja-build nlohmann-json3-dev pkg-config \
    protobuf-compiler python3-pip sudo unzip uuid-dev \
    && rm -rf /var/lib/apt/lists/*

# Add Magma repo (trusted)
COPY keys/linux_foundation_registry_key.asc /etc/apt/trusted.gpg.d/magma.asc
RUN echo "deb [trusted=yes] ${EXTRA_REPO} focal-ci main" > /etc/apt/sources.list.d/magma.list

# Install C runtime deps
RUN apt-get update && apt-get install -y \
    grpc-dev libfolly-dev liblfds710 magma-cpp-redis magma-libfluid \
    oai-asn1c oai-freediameter oai-gnutls oai-nettle prometheus-cpp-dev \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/apt/sources.list.d/magma.list

WORKDIR $MAGMA_ROOT

# Copy Bazel files
COPY WORKSPACE.bazel BUILD.bazel .bazelignore .bazelrc .bazelversion $MAGMA_ROOT/
COPY bazel/ $MAGMA_ROOT/bazel
COPY third_party/build/patches/libfluid/ $MAGMA_ROOT/third_party/build/patches/libfluid/

# Build external dependencies
RUN bazel build \
    @com_github_grpc_grpc//:grpc++ \
    @com_google_protobuf//:protobuf \
    @prometheus_cpp//:prometheus-cpp \
    @yaml-cpp//:yaml-cpp \
    @github_nlohmann_json//:json \
    @sentry_native//:sentry

# Copy proto files
COPY feg/protos $MAGMA_ROOT/feg/protos
COPY feg/gateway/services/aaa/protos $MAGMA_ROOT/feg/gateway/services/aaa/protos
COPY lte/protos $MAGMA_ROOT/lte/protos
COPY orc8r/protos $MAGMA_ROOT/orc8r/protos
COPY protos $MAGMA_ROOT/protos

# Copy C code and scripts
COPY orc8r/gateway/c/common $MAGMA_ROOT/orc8r/gateway/c/common
COPY lte/gateway/c $MAGMA_ROOT/lte/gateway/c
COPY lte/gateway/python/scripts $MAGMA_ROOT/lte/gateway/python/scripts
COPY lte/gateway/docker $MAGMA_ROOT/lte/gateway/docker
COPY lte/gateway/docker/mme/configs/ $MAGMA_ROOT/lte/gateway/docker/configs/

# Build C binaries
RUN bazel build --config=production \
    //lte/gateway/c/sctpd/src:sctpd \
    //lte/gateway/c/connection_tracker/src:connectiond \
    //lte/gateway/c/li_agent/src:liagentd \
    //lte/gateway/c/session_manager:sessiond \
    //lte/gateway/c/core:agw_of

# Copy configs
COPY lte/gateway/configs $MAGMA_ROOT/lte/gateway/configs

################################################################################
# Step 6: Dev/Production Gateway C Image
################################################################################
FROM $OS_DIST:$OS_RELEASE AS gateway_c

ENV MAGMA_ROOT=/magma
ENV C_BUILD=/build/c
ENV TZ=America/Toronto

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Temporary GPG workaround
RUN echo "Acquire::AllowInsecureRepositories true;" > /etc/apt/apt.conf.d/99AllowInsecureRepositories && \
    echo "APT::Get::AllowUnauthenticated true;" >> /etc/apt/apt.conf.d/99AllowUnauthenticated

# Install runtime dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https apt-utils ca-certificates gnupg \
    iproute2 iptables libgoogle-glog-dev libidn11-dev libmnl-dev libprotoc-dev \
    libsctp-dev libtspi1 libyaml-cpp-dev net-tools netcat openssl psmisc sudo \
    tshark tzdata wget \
    libopenvswitch openvswitch-common openvswitch-datapath-dkms openvswitch-switch \
    && rm -rf /var/lib/apt/lists/*

# Copy pre-built shared libraries from builder
COPY --from=builder_c /usr/lib/${CPU_ARCH}-linux-gnu/lib* /usr/lib/${CPU_ARCH}-linux-gnu/
COPY --from=builder_c /usr/local/lib/lib* /usr/local/lib/
RUN ldconfig 2> /dev/null

# Copy C binaries
COPY --from=builder_c $MAGMA_ROOT/bazel-bin/lte/gateway/c/session_manager/sessiond /usr/local/bin/sessiond
COPY --from=builder_c $MAGMA_ROOT/bazel-bin/lte/gateway/c/sctpd/src/sctpd /usr/local/bin/sctpd
COPY --from=builder_c $MAGMA_ROOT/bazel-bin/lte/gateway/c/connection_tracker/src/connectiond /usr/local/bin/connectiond
COPY --from=builder_c $MAGMA_ROOT/bazel-bin/lte/gateway/c/li_agent/src/liagentd /usr/local/bin/liagentd
COPY --from=builder_c $MAGMA_ROOT/bazel-bin/lte/gateway/c/core/agw_of /usr/local/bin/oai_mme

# Copy configs
COPY lte/gateway/configs /etc/magma
COPY orc8r/gateway/configs/templates /etc/magma/templates
COPY lte/gateway/deploy/roles/magma/files/magma-create-gtp-port.sh /usr/local/bin/

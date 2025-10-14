################################################################################
# Magma Gateway Multi-stage Dockerfile (C + Python + Open vSwitch)
# Base setup BEFORE cloning Magma source
################################################################################

ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=focal
ARG EXTRA_REPO=https://linuxfoundation.jfrog.io/artifactory/magma-packages-test

# -------------------------
# Stage 1: Builder (C binaries)
# -------------------------
FROM $OS_DIST:$OS_RELEASE AS builder_c
ARG CPU_ARCH
ARG DEB_PORT
ARG OS_DIST
ARG OS_RELEASE

ENV MAGMA_ROOT=/magma
ENV C_BUILD=/build/c
ENV OAI_BUILD=$C_BUILD/oai
ENV TZ=America/Toronto
ENV CCACHE_DIR=${MAGMA_ROOT}/.cache/gateway/ccache
ENV MAGMA_DEV_MODE=0
ENV XDG_CACHE_HOME=${MAGMA_ROOT}/.cache

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Allow insecure repos temporarily
RUN echo "Acquire::AllowInsecureRepositories true;" > /etc/apt/apt.conf.d/99AllowInsecureRepositories \
    && echo "APT::Get::AllowUnauthenticated true;" >> /etc/apt/apt.conf.d/99AllowInsecureRepositories

# Install build tools & dependencies
RUN apt-get update && apt-get install -y \
    apt-utils software-properties-common apt-transport-https gnupg wget \
    autoconf autogen build-essential ccache check cmake curl git \
    libboost-chrono-dev libboost-context-dev libboost-program-options-dev libboost-filesystem-dev libboost-regex-dev \
    libc++-dev libconfig-dev libcurl4-openssl-dev libczmq-dev libdouble-conversion-dev libgflags-dev libgmp3-dev \
    libgoogle-glog-dev libmnl-dev libpcap-dev libprotoc-dev libsctp-dev libsqlite3-dev libssl-dev libtspi-dev \
    libtool libxml2-dev libxslt-dev libyaml-cpp-dev ninja-build nlohmann-json3-dev pkg-config protobuf-compiler \
    python3-pip sudo unzip uuid-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR $MAGMA_ROOT

# Placeholder: later COPY Bazel files, proto files, and source code
# COPY WORKSPACE.bazel BUILD.bazel .bazelignore .bazelrc .bazelversion $MAGMA_ROOT/
# COPY bazel/ $MAGMA_ROOT/bazel
# COPY third_party/build/patches/libfluid/ $MAGMA_ROOT/third_party/build/patches/libfluid/
# COPY lte/protos $MAGMA_ROOT/lte/protos
# COPY orc8r/protos $MAGMA_ROOT/orc8r/protos
# COPY protos $MAGMA_ROOT/protos
# COPY feg/protos $MAGMA_ROOT/feg/protos
# COPY feg/gateway/services/aaa/protos $MAGMA_ROOT/feg/gateway/services/aaa/protos
# COPY lte/gateway/c $MAGMA_ROOT/lte/gateway/c
# COPY orc8r/gateway/c/common $MAGMA_ROOT/orc8r/gateway/c/common
# COPY lte/gateway/python/scripts $MAGMA_ROOT/lte/gateway/python/scripts
# COPY lte/gateway/docker $MAGMA_ROOT/lte/gateway/docker
# COPY lte/gateway/docker/mme/configs/ $MAGMA_ROOT/lte/gateway/docker/configs/

# -------------------------
# Stage 2: Python environment
# -------------------------
FROM $OS_DIST:$OS_RELEASE AS builder_python
ARG CPU_ARCH
ARG DEB_PORT
ARG OS_DIST
ARG OS_RELEASE

ENV MAGMA_ROOT=/magma
ENV TZ=America/Toronto

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install Python runtime & dependencies
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-setuptools python3-dev python3-venv \
    git curl unzip sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR $MAGMA_ROOT
# Placeholder for Python scripts
# COPY lte/gateway/python/scripts $MAGMA_ROOT/lte/gateway/python/scripts

# -------------------------
# Stage 3: Open vSwitch
# -------------------------
FROM $OS_DIST:$OS_RELEASE AS gateway_ovs
ARG CPU_ARCH
ARG DEB_PORT
ARG OS_DIST
ARG OS_RELEASE
ARG EXTRA_REPO

ENV LINUX_HEADERS_VER=5.4.0-186-generic
ENV TZ=America/Toronto

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install basic network tools
RUN apt-get -q update && \
    apt-get -y -q --no-install-recommends install \
    apt-utils ca-certificates apt-transport-https \
    iptables iproute2 iputils-arping iputils-clockdiff iputils-ping iputils-tracepath \
    bridge-utils ifupdown vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Add Magma repo (for OVS modules later)
COPY ./keys/linux_foundation_registry_key.asc /etc/apt/trusted.gpg.d/magma.asc
RUN echo "deb [trusted=yes] https://linuxfoundation.jfrog.io/artifactory/magma-packages focal-1.8.0 main" > /etc/apt/sources.list.d/magma.list

# Install OVS
RUN apt-get update && apt-get install -y --no-install-recommends \
    libopenvswitch openvswitch-common openvswitch-switch \
    linux-headers-${LINUX_HEADERS_VER} openvswitch-datapath-dkms \
    && rm -rf /var/lib/apt/lists/*

# Copy OVS scripts (ensure they exist in build context)
# COPY --chmod=755 ./lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/
# COPY --chmod=755 ./lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh
# ENTRYPOINT [ "/entrypoint.sh" ]


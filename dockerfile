################################################################################
# Magma Core Dockerfile for Ubuntu 24.04 with Open vSwitch
################################################################################

# -----------------------------------------------------------------------------
# Step 0: Base image
# -----------------------------------------------------------------------------
ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=focal
ARG EXTRA_REPO=https://linuxfoundation.jfrog.io/artifactory/magma-packages-test

FROM $OS_DIST:$OS_RELEASE AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Toronto

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && apt-get update && apt-get upgrade -y \
    && apt-get install -y \
        software-properties-common \
        curl \
        wget \
        git \
        lsb-release \
        ca-certificates \
        apt-transport-https \
        gnupg \
        build-essential \
        cmake \
        pkg-config \
        sudo \
        python3-pip \
        python3-venv \
        unzip \
        tzdata \
        vim \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Step 1: Python builder image
# -----------------------------------------------------------------------------
FROM base AS builder_python

ENV MAGMA_ROOT=/magma
ENV PIP_CACHE_HOME="~/.pipcache"
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    docker.io libsystemd-dev && rm -rf /var/lib/apt/lists/*

# Download Bazel
RUN wget -P /usr/sbin https://github.com/bazelbuild/bazelisk/releases/download/v1.10.0/bazelisk-linux-amd64 \
    && chmod +x /usr/sbin/bazelisk-linux-amd64 \
    && ln -s /usr/sbin/bazelisk-linux-amd64 /usr/sbin/bazel

WORKDIR /magma
# Placeholder: copy Python files and protos
# COPY ./lte/gateway/python $MAGMA_ROOT/lte/gateway/python
# COPY ./orc8r/gateway/python $MAGMA_ROOT/orc8r/gateway/python
# COPY ./protos $MAGMA_ROOT/protos

# -----------------------------------------------------------------------------
# Step 2: C builder image
# -----------------------------------------------------------------------------
FROM base AS builder_c

ENV MAGMA_ROOT=/magma
ENV C_BUILD=/build/c
ENV OAI_BUILD=$C_BUILD/oai
ENV CCACHE_DIR=${MAGMA_ROOT}/.cache/gateway/ccache
ENV MAGMA_DEV_MODE=0
ENV XDG_CACHE_HOME=${MAGMA_ROOT}/.cache

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

WORKDIR /magma
# Placeholder: copy Bazel, protos, and C source
# COPY WORKSPACE.bazel BUILD.bazel .bazelignore .bazelrc .bazelversion $MAGMA_ROOT/
# COPY bazel/ $MAGMA_ROOT/bazel
# COPY feg/protos lte/protos orc8r/protos protos $MAGMA_ROOT/
# COPY lte/gateway/c $MAGMA_ROOT/lte/gateway/c
# COPY orc8r/gateway/c/common $MAGMA_ROOT/orc8r/gateway/c/common

# -----------------------------------------------------------------------------
# Step 3: Runtime image
# -----------------------------------------------------------------------------
FROM base AS gateway_runtime

ENV MAGMA_ROOT=/magma
ENV TZ=America/Toronto
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    docker.io ethtool iproute2 iptables net-tools netcat \
    openvswitch-switch openvswitch-common openvswitch-datapath-dkms \
    redis-server tzdata wget sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/bin

# Placeholder: copy Python and C build artifacts
# COPY --from=builder_python /magma/bazel-bin/lte/gateway/release/magma_python_executables.tar.gz /tmp/
# COPY --from=builder_c /magma/bazel-bin/lte/gateway/c/session_manager/sessiond /usr/local/bin/sessiond

# Placeholder: copy configs
# COPY lte/gateway/configs /etc/magma
# COPY orc8r/gateway/configs/templates /etc/magma/templates
# COPY lte/gateway/deploy/roles/magma/files/magma-create-gtp-port.sh /usr/local/bin/

# -----------------------------------------------------------------------------
# Step 4: Open vSwitch image
# -----------------------------------------------------------------------------
FROM $OS_DIST:$OS_RELEASE AS gateway_ovs

ENV LINUX_HEADERS_VER=5.4.0-186-generic

RUN apt-get -q update && apt-get install -y --no-install-recommends \
    apt-utils ca-certificates apt-transport-https \
    iptables iproute2 iputils-arping iputils-clockdiff iputils-ping iputils-tracepath \
    bridge-utils ifupdown vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Add Magma repo and install OVS
COPY keys/linux_foundation_registry_key.asc /etc/apt/trusted.gpg.d/magma.asc
RUN echo "deb https://linuxfoundation.jfrog.io/artifactory/magma-packages focal-1.8.0 main" > /etc/apt/sources.list.d/magma.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        libopenvswitch \
        openvswitch-common \
        openvswitch-switch \
        linux-headers-${LINUX_HEADERS_VER} \
        openvswitch-datapath-dkms \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/
COPY --chmod=755 lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]

################################################################################
# Magma Core Dockerfile for Ubuntu 24.04
# Combines Python and C builder images with runtime images
################################################################################

# -----------------------------------------------------------------------------
# Step 0: Base image and update
# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS base

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
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Step 1: Clone Magma Core (placeholder)
# -----------------------------------------------------------------------------
# Uncomment and set the correct repo URL and branch
# RUN git clone --recursive https://github.com/magma/magma.git /magma
# WORKDIR /magma

# -----------------------------------------------------------------------------
# Step 2: Python builder image
# -----------------------------------------------------------------------------
FROM base AS builder_python

ENV MAGMA_ROOT=/magma
ENV PIP_CACHE_HOME="~/.pipcache"
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    docker.io \
    libsystemd-dev \
    && rm -rf /var/lib/apt/lists/*

# Download Bazel
RUN wget -P /usr/sbin https://github.com/bazelbuild/bazelisk/releases/download/v1.10.0/bazelisk-linux-amd64 \
    && chmod +x /usr/sbin/bazelisk-linux-amd64 \
    && ln -s /usr/sbin/bazelisk-linux-amd64 /usr/sbin/bazel

# Placeholder: copy Magma Python files
# COPY ./lte/gateway/python $MAGMA_ROOT/lte/gateway/python
# COPY ./orc8r/gateway/python $MAGMA_ROOT/orc8r/gateway/python
# COPY ./protos $MAGMA_ROOT/protos

WORKDIR /magma
# Placeholder build
# RUN bazel build //lte/gateway/release:python_executables_tar

# -----------------------------------------------------------------------------
# Step 3: C builder image
# -----------------------------------------------------------------------------
FROM base AS builder_c

ENV MAGMA_ROOT=/magma
ENV C_BUILD=/build/c
ENV OAI_BUILD=$C_BUILD/oai
ENV CCACHE_DIR=${MAGMA_ROOT}/.cache/gateway/ccache
ENV MAGMA_DEV_MODE=0
ENV XDG_CACHE_HOME=${MAGMA_ROOT}/.cache

# Install dependencies for C build
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

# Placeholder: copy Bazel files and proto files
# COPY WORKSPACE.bazel BUILD.bazel .bazelignore .bazelrc .bazelversion $MAGMA_ROOT/
# COPY bazel/ $MAGMA_ROOT/bazel
# COPY feg/protos lte/protos orc8r/protos protos $MAGMA_ROOT/
# COPY lte/gateway/c $MAGMA_ROOT/lte/gateway/c
# COPY orc8r/gateway/c/common $MAGMA_ROOT/orc8r/gateway/c/common

# Placeholder build
# RUN bazel build --config=production //lte/gateway/c/session_manager/sessiond

# -----------------------------------------------------------------------------
# Step 4: Runtime image for Python + C
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

ENTRYPOINT ["/bin/bash"]

################################################################################
# Base Image for Magma C + Python + Open vSwitch (pre-Magma clone)
################################################################################

ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=focal
ARG EXTRA_REPO=https://linuxfoundation.jfrog.io/artifactory/magma-packages-test

# -----------------------------------------------------------------------------
# Builder image for C binaries and Magma proto files
# -----------------------------------------------------------------------------
FROM $OS_DIST:$OS_RELEASE AS builder_c
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

# Allow insecure repos temporarily
RUN echo "Acquire::AllowInsecureRepositories true;" > /etc/apt/apt.conf.d/99AllowInsecureRepositories \
    && echo "APT::Get::AllowUnauthenticated true;" >> /etc/apt/apt.conf.d/99AllowInsecureRepositories

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install build dependencies (C + general tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    software-properties-common \
    apt-transport-https \
    gnupg \
    wget \
    autoconf \
    autogen \
    build-essential \
    ccache \
    check \
    cmake \
    curl \
    git \
    libboost-chrono-dev \
    libboost-context-dev \
    libboost-program-options-dev \
    libboost-filesystem-dev \
    libboost-regex-dev \
    libc++-dev \
    libconfig-dev \
    libcurl4-openssl-dev \
    libczmq-dev \
    libdouble-conversion-dev \
    libgflags-dev \
    libgmp3-dev \
    libgoogle-glog-dev \
    libmnl-dev \
    libpcap-dev \
    libprotoc-dev \
    libsctp-dev \
    libsqlite3-dev \
    libssl-dev \
    libtspi-dev \
    libtool \
    libxml2-dev \
    libxslt-dev \
    libyaml-cpp-dev \
    ninja-build \
    nlohmann-json3-dev \
    pkg-config \
    protobuf-compiler \
    python3-pip \
    sudo \
    unzip \
    uuid-dev \
    && rm -rf /var/lib/apt/lists/*

# Download Bazelisk (Bazel wrapper)
RUN wget -P /usr/sbin --progress=dot:giga https://github.com/bazelbuild/bazelisk/releases/download/v1.10.0/bazelisk-linux-"${DEB_PORT}" \
    && chmod +x /usr/sbin/bazelisk-linux-"${DEB_PORT}" \
    && ln -s /usr/sbin/bazelisk-linux-"${DEB_PORT}" /usr/sbin/bazel

WORKDIR /magma

# -----------------------------------------------------------------------------
# Builder image for Python dependencies (pre-Magma clone)
# -----------------------------------------------------------------------------
FROM $OS_DIST:$OS_RELEASE AS builder_python
ENV TZ=Europe/Paris
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Python dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    git \
    curl \
    unzip \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Open vSwitch image (Magma 1.9.0)
# -----------------------------------------------------------------------------
FROM $OS_DIST:$OS_RELEASE AS gateway_ovs
ARG CPU_ARCH
ARG DEB_PORT
ARG OS_DIST
ARG OS_RELEASE
ARG EXTRA_REPO

ENV TZ=Europe/Paris
ENV LINUX_HEADERS_VER=5.4.0-186-generic

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install networking utils and general tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    ca-certificates \
    apt-transport-https \
    iptables \
    iproute2 \
    iputils-arping \
    iputils-clockdiff \
    iputils-ping \
    iputils-tracepath \
    bridge-utils \
    ifupdown \
    vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Add Magma repo for OVS 1.9.0 modules
COPY ./keys/linux_foundation_registry_key.asc /etc/apt/trusted.gpg.d/magma.asc
RUN echo "deb [trusted=yes] https://linuxfoundation.jfrog.io/artifactory/magma-packages focal-1.9.0 main" > /etc/apt/sources.list.d/magma.list

# Install OVS
RUN apt-get update && apt-get install -y --no-install-recommends \
    libopenvswitch \
    openvswitch-common \
    openvswitch-switch \
    linux-headers-${LINUX_HEADERS_VER} \
    openvswitch-datapath-dkms \
    && rm -rf /var/lib/apt/lists/*

# Copy OVS scripts
COPY --chmod=755 lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/
COPY --chmod=755 lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]

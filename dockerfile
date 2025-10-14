################################################################################
# Step 1: Base Ubuntu 24.04 with updated packages
################################################################################
FROM ubuntu:24.04 AS base

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV MAGMA_ROOT=/magma
ENV TZ=America/Toronto
ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Update packages and install basic dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
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
        python3-dev \
        python3-pip \
        python3-venv \
        sudo \
        docker.io \
    && rm -rf /var/lib/apt/lists/*

################################################################################
# Step 2: Clone Magma Core
################################################################################
FROM base AS magma-clone

ARG MAGMA_REPO=https://github.com/magma/magma.git
ARG MAGMA_BRANCH=main

RUN git clone --branch $MAGMA_BRANCH $MAGMA_REPO /opt/magma
WORKDIR /opt/magma

################################################################################
# Step 3: Build Python binaries (Builder stage)
################################################################################
FROM base AS builder

ENV MAGMA_DEV_MODE=0
ENV PIP_CACHE_HOME="~/.pipcache"

# Allow insecure repositories (temporary workaround)
RUN echo "Acquire::AllowInsecureRepositories true;" > /etc/apt/apt.conf.d/99AllowInsecureRepositories && \
    echo "APT::Get::AllowUnauthenticated true;" >> /etc/apt/apt.conf.d/99AllowInsecureRepositories

RUN apt-get update && apt-get install -y \
    libsystemd-dev \
    pkg-config \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Download Bazelisk for building
RUN wget -P /usr/sbin https://github.com/bazelbuild/bazelisk/releases/download/v1.10.0/bazelisk-linux-"${DEB_PORT}" && \
    chmod +x /usr/sbin/bazelisk-linux-"${DEB_PORT}" && \
    ln -s /usr/sbin/bazelisk-linux-"${DEB_PORT}" /usr/sbin/bazel

WORKDIR /magma

# TODO: Copy only necessary Bazel files from magma-clone
# COPY --from=magma-clone /opt/magma/ ./ 

# Example build (adjust targets if required)
# RUN bazel build //lte/gateway/release:python_executables_tar //lte/gateway/release:dhcp_helper_cli_tar

################################################################################
# Step 4: Dev/Production Gateway Python Image
################################################################################
FROM base AS gateway_python

ENV VIRTUAL_ENV=/build
ENV PATH="/magma/orc8r/gateway/python/scripts/:/magma/lte/gateway/python/scripts/:$PATH"

# Allow insecure repositories (temporary workaround)
RUN echo "Acquire::AllowInsecureRepositories true;" > /etc/apt/apt.conf.d/99AllowInsecureRepositories && \
    echo "APT::Get::AllowUnauthenticated true;" >> /etc/apt/apt.conf.d/99AllowInsecureRepositories

# Add Magma repo (trusted for testing)
RUN echo "deb [trusted=yes] https://linuxfoundation.jfrog.io/artifactory/magma-packages-test focal-ci main" > /etc/apt/sources.list.d/magma.list

# Install required runtime packages
RUN apt-get update && apt-get install -y \
    bcc-tools \
    libopenvswitch \
    openvswitch-datapath-dkms \
    openvswitch-common \
    openvswitch-switch \
    wireguard \
    redis-server \
    ethtool \
    inetutils-ping \
    iproute2 \
    iptables \
    isc-dhcp-client \
    linux-headers-generic \
    net-tools \
    netcat \
    nghttp2-proxy \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/bin

# TODO: Copy build artifacts from builder stage
# COPY --from=builder /magma/bazel-bin/lte/gateway/release/magma_python_executables.tar.gz /tmp/
# RUN tar -xf /tmp/magma_python_executables.tar.gz --directory / && rm /tmp/magma_python_executables.tar.gz

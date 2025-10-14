# -----------------------------------------------------------------------------
# Base image
# -----------------------------------------------------------------------------
ARG OS_DIST=ubuntu
ARG OS_RELEASE=focal
FROM $OS_DIST:$OS_RELEASE AS base

ARG DEB_PORT=amd64
ARG CPU_ARCH=x86_64
ARG EXTRA_REPO=https://linuxfoundation.jfrog.io/artifactory/magma-packages-test

ENV MAGMA_ROOT=/magma
ENV TZ=America/Toronto
ENV DEBIAN_FRONTEND=noninteractive

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Basic upgrade and tools
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        apt-utils \
        software-properties-common \
        apt-transport-https \
        gnupg \
        wget \
        git \
        curl \
        sudo \
        lsb-release \
        tzdata \
        build-essential \
        python3-pip \
        python3-venv \
        unzip \
        uuid-dev \
        cmake \
        ninja-build \
        pkg-config \
        libtool \
        autoconf \
        autogen \
        curl \
        vim \
        net-tools \
        iproute2 \
        iputils-ping \
        iputils-arping \
        iputils-tracepath \
        bridge-utils \
        ifupdown \
        iptables \
        ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone Magma repository
# -----------------------------------------------------------------------------
WORKDIR /opt
RUN git clone https://github.com/magma/magma.git $MAGMA_ROOT
WORKDIR $MAGMA_ROOT
RUN git checkout v1.9

# -----------------------------------------------------------------------------
# Open vSwitch installation
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    openvswitch-switch \
    openvswitch-common \
    openvswitch-datapath-dkms \
    linux-headers-$(uname -r) \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy OVS scripts from repo
COPY lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/
COPY lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/healthcheck.sh /entrypoint.sh

# -----------------------------------------------------------------------------
# C build dependencies
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    ccache \
    libboost-chrono-dev \
    libboost-context-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-regex-dev \
    libdouble-conversion-dev \
    libgflags-dev \
    libgmp3-dev \
    libgoogle-glog-dev \
    libmnl-dev \
    libpcap-dev \
    libprotobuf-dev \
    libsctp-dev \
    libsqlite3-dev \
    libssl-dev \
    libtspi-dev \
    libxml2-dev \
    libxslt-dev \
    libyaml-cpp-dev \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Python dependencies
# -----------------------------------------------------------------------------
RUN pip3 install --no-cache-dir \
    grpcio \
    protobuf \
    pyyaml \
    requests \
    numpy \
    pandas

# -----------------------------------------------------------------------------
# Expose OVS entrypoint
# -----------------------------------------------------------------------------
ENTRYPOINT ["/entrypoint.sh"]

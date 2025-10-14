# -----------------------------------------------------------------------------
# Base image and args
# -----------------------------------------------------------------------------
ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=focal
ARG EXTRA_REPO=https://linuxfoundation.jfrog.io/artifactory/magma-packages-test

FROM $OS_DIST:$OS_RELEASE AS gateway_ovs
ARG CPU_ARCH
ARG OS_DIST
ARG OS_RELEASE

ENV MAGMA_ROOT=/magma
ENV TZ=America/Toronto

# -----------------------------------------------------------------------------
# Set timezone
# -----------------------------------------------------------------------------
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# -----------------------------------------------------------------------------
# Upgrade & install common packages
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    apt-utils \
    ca-certificates \
    apt-transport-https \
    curl \
    gnupg \
    wget \
    software-properties-common \
    sudo \
    build-essential \
    cmake \
    git \
    python3 \
    python3-pip \
    autoconf \
    libtool \
    pkg-config \
    vim \
    net-tools \
    iproute2 \
    iptables \
    tzdata \
    unzip \
    uuid-dev \
    bridge-utils \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone Magma v1.9
# -----------------------------------------------------------------------------
WORKDIR /opt
RUN git clone --branch v1.9 https://github.com/magma/magma.git $MAGMA_ROOT

# -----------------------------------------------------------------------------
# Install Open vSwitch
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    libopenvswitch \
    openvswitch-common \
    openvswitch-switch \
    openvswitch-datapath-dkms \
    linux-headers-$(uname -r) \
    && rm -rf /var/lib/apt/lists/*

# Copy OVS scripts from cloned repo
COPY $MAGMA_ROOT/lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY $MAGMA_ROOT/lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/healthcheck.sh /entrypoint.sh

# -----------------------------------------------------------------------------
# Install C dependencies for Magma build
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ccache \
    check \
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
    libxml2-dev \
    libxslt-dev \
    libyaml-cpp-dev \
    ninja-build \
    nlohmann-json3-dev \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install Python dependencies
# -----------------------------------------------------------------------------
RUN pip3 install --no-cache-dir -r $MAGMA_ROOT/lte/gateway/python/requirements.txt

# -----------------------------------------------------------------------------
# Optional: Build C binaries (sessiond, sctpd, connectiond, liagentd)
# -----------------------------------------------------------------------------
# WORKDIR $MAGMA_ROOT
# RUN bazel build //lte/gateway/c/session_manager:sessiond \
#                //lte/gateway/c/sctpd/src:sctpd \
#                //lte/gateway/c/connection_tracker/src:connectiond \
#                //lte/gateway/c/li_agent/src:liagentd

# -----------------------------------------------------------------------------
# Set entrypoint
# -----------------------------------------------------------------------------
ENTRYPOINT ["/entrypoint.sh"]

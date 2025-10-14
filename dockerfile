# -----------------------------------------------------------------------------
# Base image
# -----------------------------------------------------------------------------
ARG OS_DIST=ubuntu
ARG OS_RELEASE=focal
FROM $OS_DIST:$OS_RELEASE AS base

ARG DEB_PORT=amd64
ARG CPU_ARCH=x86_64

ENV MAGMA_ROOT=/magma
ENV TZ=America/Toronto
ENV DEBIAN_FRONTEND=noninteractive

# Set timezone and upgrade
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    apt-utils software-properties-common apt-transport-https gnupg wget git curl sudo lsb-release tzdata \
    build-essential python3-pip python3-venv unzip uuid-dev cmake ninja-build pkg-config libtool autoconf autogen vim \
    iproute2 iptables bridge-utils ifupdown iputils-ping iputils-arping iputils-tracepath net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone Magma repository (v1.9)
# -----------------------------------------------------------------------------
WORKDIR /opt
RUN git clone --branch v1.9 https://github.com/magma/magma.git $MAGMA_ROOT
WORKDIR $MAGMA_ROOT

# -----------------------------------------------------------------------------
# Open vSwitch installation
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    openvswitch-switch openvswitch-common openvswitch-datapath-dkms linux-headers-$(uname -r) \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy OVS scripts from the cloned repo inside the container
RUN chmod +x $MAGMA_ROOT/lte/gateway/docker/services/openvswitch/healthcheck.sh \
             $MAGMA_ROOT/lte/gateway/docker/services/openvswitch/entrypoint.sh
COPY $MAGMA_ROOT/lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY $MAGMA_ROOT/lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh

# -----------------------------------------------------------------------------
# C build dependencies
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    ccache libboost-chrono-dev libboost-context-dev libboost-filesystem-dev \
    libboost-program-options-dev libboost-regex-dev libdouble-conversion-dev \
    libgflags-dev libgmp3-dev libgoogle-glog-dev libmnl-dev libpcap-dev \
    libprotobuf-dev libsctp-dev libsqlite3-dev libssl-dev libtspi-dev \
    libxml2-dev libxslt-dev libyaml-cpp-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Python dependencies
# -----------------------------------------------------------------------------
RUN pip3 install --no-cache-dir grpcio protobuf pyyaml requests numpy pandas

# -----------------------------------------------------------------------------
# Set OVS entrypoint
# -----------------------------------------------------------------------------
ENTRYPOINT ["/entrypoint.sh"]

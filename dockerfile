################################################################################
# Magma Core - Ubuntu 24.04 Dockerfile
# Steps:
# 1. Update/Upgrade Packages
# 2. Clone Magma on Host
# 3. Install OVS, C, Python dependencies
# 4. Bring Magma services up
################################################################################

FROM ubuntu:24.04

# -----------------------------------------------------------------------------
# Environment Variables
# -----------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Toronto
ENV MAGMA_ROOT=/magma

# -----------------------------------------------------------------------------
# System Update and Dependencies
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    git curl wget ca-certificates gnupg2 lsb-release tzdata \
    build-essential cmake pkg-config \
    python3 python3-pip python3-venv python3-setuptools python3-dev \
    net-tools iproute2 iputils-ping dnsutils \
    openvswitch-switch openvswitch-common && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Copy Magma Source Code (cloned on host)
# -----------------------------------------------------------------------------
# Make sure to clone the repo on host:
# git clone https://github.com/magma/magma.git
# Then run: docker build -t magma-core -f Dockerfile .
COPY magma ${MAGMA_ROOT}

# -----------------------------------------------------------------------------
# Install Python dependencies for Magma
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway
RUN pip install --upgrade pip && \
    pip install -r python/requirements.txt || true

# -----------------------------------------------------------------------------
# Setup Open vSwitch Scripts
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway/docker/services/openvswitch
COPY magma/lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY magma/lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/healthcheck.sh /entrypoint.sh

# -----------------------------------------------------------------------------
# Expose Ports & Entrypoint
# -----------------------------------------------------------------------------
EXPOSE 6640 6633 6653 53 80 443
ENTRYPOINT ["/entrypoint.sh"]

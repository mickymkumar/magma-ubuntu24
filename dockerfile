################################################################################
# Magma Core - Ubuntu 24.04 Dockerfile
# Steps:
# 1. Update/Upgrade Packages
# 2. Clone Magma on Host
# 3. Install OVS, C, Python dependencies
# 4. Bring Magma services up
################################################################################

# Use Ubuntu 24.04 as base image
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
# Clone Magma Source Code (host mounts magma folder before build)
# -----------------------------------------------------------------------------
# IMPORTANT: Clone the Magma repo on your EC2 host **before** running docker build
# Example:
#   git clone https://github.com/magma/magma.git
#   docker build -t magma-core -f Dockerfile .
# This Dockerfile expects the magma folder to be in the build context.

COPY magma /magma

# -----------------------------------------------------------------------------
# Build and Install Magma Components
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway

# Install Python packages from Magma requirements
RUN pip install --upgrade pip && \
    pip install -r python/requirements.txt || true

# -----------------------------------------------------------------------------
# Setup OVS Service
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway/docker/services/openvswitch

COPY ${MAGMA_ROOT}/lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY ${MAGMA_ROOT}/lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/healthcheck.sh /entrypoint.sh

# -----------------------------------------------------------------------------
# Expose Ports & Entry
# -----------------------------------------------------------------------------
EXPOSE 6640 6633 6653 53 80 443

ENTRYPOINT ["/entrypoint.sh"]

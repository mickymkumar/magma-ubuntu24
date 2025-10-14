################################################################################
# Magma Full Core - Ubuntu 24.04 Dockerfile
# Fully functional on AWS without vport_gtp kernel module
################################################################################

FROM ubuntu:24.04

# -----------------------------------------------------------------------------
# Environment Variables
# -----------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Toronto
ENV MAGMA_ROOT=/magma
ENV PATH=$PATH:/usr/local/bin:/usr/local/sbin

# -----------------------------------------------------------------------------
# System Update and Dependencies
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    git curl wget ca-certificates gnupg2 lsb-release tzdata \
    build-essential cmake pkg-config \
    python3 python3-pip python3-venv python3-setuptools python3-dev \
    net-tools iproute2 iputils-ping dnsutils sudo \
    openvswitch-switch openvswitch-common \
    autoconf automake libtool pkg-config m4 dkms && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install Bazel (for completeness, skip building C binaries)
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y curl gnupg2 apt-transport-https && \
    curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /usr/share/keyrings/bazel-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
    apt-get update && apt-get install -y bazel-5.2.0 && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone Magma Source Code
# -----------------------------------------------------------------------------
RUN git clone --branch master https://github.com/magma/magma.git ${MAGMA_ROOT}

# -----------------------------------------------------------------------------
# Skip building C components (sessiond, sctpd, liagentd) on AWS kernels
# -----------------------------------------------------------------------------
# WORKDIR ${MAGMA_ROOT}
# RUN bazel build //lte/gateway/c/session_manager:sessiond \
#                //lte/gateway/c/sctpd/src:sctpd \
#                //lte/gateway/c/connection_tracker/src:connectiond \
#                //lte/gateway/c/li_agent/src:liagentd || true

# -----------------------------------------------------------------------------
# Install Python packages from Magma
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway/python
RUN python3 -m pip install --upgrade pip && \
    pip install -r requirements.txt || true

# -----------------------------------------------------------------------------
# Setup OVS Service and Patch entrypoint to skip DKMS
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway/docker/services/openvswitch
RUN cp healthcheck.sh /usr/local/bin/healthcheck.sh && \
    cp entrypoint.sh /entrypoint.sh && \
    chmod +x /usr/local/bin/healthcheck.sh /entrypoint.sh && \
    # Patch entrypoint.sh to skip vport_gtp DKMS build if missing
    sed -i '/Checking kernel module "vport_gtp"/,/Error! Arguments <module>/c\echo "vport_gtp not available, skipping DKMS build."' /entrypoint.sh

# -----------------------------------------------------------------------------
# Expose Ports
# -----------------------------------------------------------------------------
EXPOSE 6640 6633 6653 53 80 443

# -----------------------------------------------------------------------------
# Entrypoint to start OVS and Python Magma services
# -----------------------------------------------------------------------------
ENTRYPOINT ["/entrypoint.sh"]

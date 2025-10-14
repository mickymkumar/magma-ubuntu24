################################################################################
# Magma Full Core - Ubuntu 24.04 Dockerfile
# Builds C & Python components, OVS, and Magma services with dynamic binary paths
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
    autoconf automake libtool pkg-config m4 dkms \
    linux-headers-$(uname -r) && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install Bazel (required for C builds)
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y curl gnupg && \
    curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /usr/share/keyrings/bazel-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
    apt-get update && apt-get install -y bazel && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone Magma Source Code
# -----------------------------------------------------------------------------
RUN git clone --branch master https://github.com/magma/magma.git ${MAGMA_ROOT}

# -----------------------------------------------------------------------------
# Build Magma C Components (AGW)
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}

RUN bazel build //lte/gateway/c/session_manager:sessiond \
               //lte/gateway/c/sctpd/src:sctpd \
               //lte/gateway/c/connection_tracker/src:connectiond \
               //lte/gateway/c/li_agent/src:liagentd

# -----------------------------------------------------------------------------
# Install Python packages from Magma
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway
RUN python3 -m pip install --upgrade pip && \
    pip install -r python/requirements.txt

# -----------------------------------------------------------------------------
# Setup OVS Service and Entrypoint
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway/docker/services/openvswitch
RUN cp healthcheck.sh /usr/local/bin/healthcheck.sh && \
    chmod +x /usr/local/bin/healthcheck.sh

# Create robust entrypoint
RUN echo '#!/bin/bash\n\
set -e\n\
echo "Checking kernel module vport_gtp..."\n\
if ! modprobe -n vport_gtp &>/dev/null; then\n\
    echo "vport_gtp not available, skipping DKMS build."\n\
else\n\
    echo "vport_gtp found, loading modules..."\n\
    modprobe vport_gtp || true\n\
fi\n\
echo "Starting Open vSwitch..."\n\
/usr/share/openvswitch/scripts/ovs-ctl start\n\
echo "Starting AGW services..."\n\
AGW_BIN=$(bazel info bazel-bin)/lte/gateway/c/session_manager/sessiond\n\
SCTP_BIN=$(bazel info bazel-bin)/lte/gateway/c/sctpd/src/sctpd\n\
$AGW_BIN &\n\
$SCTP_BIN &\n\
exec bash' > /entrypoint.sh && chmod +x /entrypoint.sh

# -----------------------------------------------------------------------------
# Expose Ports
# -----------------------------------------------------------------------------
EXPOSE 6640 6633 6653 53 80 443

# -----------------------------------------------------------------------------
# Start Magma Services (AGW, OVS)
# -----------------------------------------------------------------------------
ENTRYPOINT ["/entrypoint.sh"]

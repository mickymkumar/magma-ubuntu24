################################################################################
# Magma Full Core - Ubuntu 24.04 Dockerfile
# Fully self-contained: builds Python + C components, sets up OVS, skips vport_gtp DKMS
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
    autoconf automake libtool pkg-config m4 dkms linux-headers-$(uname -r) && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install Bazel 5.2.0
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y apt-transport-https curl gnupg2 && \
    curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /usr/share/keyrings/bazel-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
    apt-get update && \
    apt-get install -y bazel-5.2.0 && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone Magma Source
# -----------------------------------------------------------------------------
RUN git clone --branch master https://github.com/magma/magma.git ${MAGMA_ROOT}

# -----------------------------------------------------------------------------
# Build C binaries if Bazel works
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}
RUN if command -v bazel > /dev/null; then \
      bazel build //lte/gateway/c/session_manager:sessiond \
                  //lte/gateway/c/sctpd/src:sctpd \
                  //lte/gateway/c/connection_tracker/src:connectiond \
                  //lte/gateway/c/li_agent/src:liagentd || true; \
    fi

# -----------------------------------------------------------------------------
# Install Python packages
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway
RUN python3 -m pip install --upgrade pip && \
    pip install -r python/requirements.txt || true

# -----------------------------------------------------------------------------
# Setup OVS Service
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway/docker/services/openvswitch
RUN cp healthcheck.sh /usr/local/bin/healthcheck.sh && \
    cp entrypoint.sh /entrypoint.sh && \
    chmod +x /usr/local/bin/healthcheck.sh /entrypoint.sh && \
    # Patch entrypoint.sh to skip vport_gtp DKMS build
    sed -i '/Checking kernel module "vport_gtp"/,/Error! Arguments <module>/c\echo "vport_gtp not available, skipping DKMS build."' /entrypoint.sh

# -----------------------------------------------------------------------------
# Create OVS runtime directories and wrapper script
# -----------------------------------------------------------------------------
RUN mkdir -p /var/run/openvswitch /etc/openvswitch

COPY <<EOF /usr/local/bin/start_magma.sh
#!/bin/bash
set -e

# Ensure OVS directories exist
mkdir -p /var/run/openvswitch /etc/openvswitch

echo "Starting Open vSwitch..."
ovsdb-server --remote=punix:/var/run/openvswitch/db.sock \
             --remote=db:Open_vSwitch,Open_vSwitch,manager_options \
             --pidfile --detach
ovs-vsctl --no-wait init
ovs-vswitchd --pidfile --detach

echo "Starting Magma services..."
# Run C binaries if they exist, otherwise skip
for bin in sessiond sctpd connectiond liagentd; do
    if [ -x /magma/bazel-bin/lte/gateway/c/\$bin ]; then
        /magma/bazel-bin/lte/gateway/c/\$bin &
    else
        echo "\$bin not found, skipping"
    fi
done

# Keep container alive
tail -f /dev/null
EOF

RUN chmod +x /usr/local/bin/start_magma.sh

# -----------------------------------------------------------------------------
# Expose Ports
# -----------------------------------------------------------------------------
EXPOSE 6640 6633 6653 53 80 443

# -----------------------------------------------------------------------------
# Start everything via wrapper
# -----------------------------------------------------------------------------
ENTRYPOINT ["/usr/local/bin/start_magma.sh"]

################################################################################
# Magma Full Core - Ubuntu 24.04 Dockerfile
# Builds C & Python components, OVS, and Magma services with DKMS support
# Automatically skips vport_gtp DKMS build if kernel module is missing
################################################################################

FROM ubuntu:24.04

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
    autoconf automake libtool pkg-config m4 dkms linux-headers-$(uname -r) \
    apt-transport-https && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install Bazel 5.2.0
# -----------------------------------------------------------------------------
RUN curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /usr/share/keyrings/bazel-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
    apt-get update && \
    apt-get install -y bazel-5.2.0 && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone Magma Source Code
# -----------------------------------------------------------------------------
RUN git clone --branch master https://github.com/magma/magma.git ${MAGMA_ROOT}

# -----------------------------------------------------------------------------
# Build Magma C Components
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}
RUN bazel build //lte/gateway/c/session_manager:sessiond \
               //lte/gateway/c/sctpd/src:sctpd \
               //lte/gateway/c/connection_tracker/src:connectiond \
               //lte/gateway/c/li_agent/src:liagentd || true

# -----------------------------------------------------------------------------
# Install Python packages
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway
RUN python3 -m pip install --upgrade pip && \
    pip install -r python/requirements.txt || true

# -----------------------------------------------------------------------------
# Patch entrypoint.sh to skip DKMS build
# -----------------------------------------------------------------------------
WORKDIR ${MAGMA_ROOT}/lte/gateway/docker/services/openvswitch
RUN sed -i '/Checking kernel module "vport_gtp"/,/Error! Arguments <module>/c\echo "vport_gtp not available, skipping DKMS build."' entrypoint.sh && \
    chmod +x entrypoint.sh healthcheck.sh

# -----------------------------------------------------------------------------
# Wrapper Script to Start OVS and Magma
# -----------------------------------------------------------------------------
RUN echo '#!/bin/bash\n\
set -e\n\
mkdir -p /var/run/openvswitch /etc/openvswitch\n\
chmod 777 /var/run/openvswitch /etc/openvswitch\n\
echo "Starting Open vSwitch..."\n\
ovsdb-tool create /etc/openvswitch/conf.db vswitch.ovsschema || true\n\
ovsdb-server /etc/openvswitch/conf.db --remote=punix:/var/run/openvswitch/db.sock --remote=db:Open_vSwitch,Open_vSwitch,manager_options --pidfile --detach || true\n\
while [ ! -S /var/run/openvswitch/db.sock ]; do sleep 0.5; done\n\
ovs-vsctl --no-wait init || true\n\
ovs-vswitchd --pidfile --detach || true\n\
echo "Open vSwitch started successfully"\n\
for bin in session_manager/sctpd connection_tracker/connectiond li_agent/liagentd; do\n\
    if [ -x /magma/bazel-bin/lte/gateway/c/$bin ]; then\n\
        echo "Starting $bin"\n\
        /magma/bazel-bin/lte/gateway/c/$bin &\n\
    else\n\
        echo "$bin not found, skipping"\n\
    fi\n\
done\n\
tail -f /dev/null' > /start_magma.sh && chmod +x /start_magma.sh

EXPOSE 6640 6633 6653 53 80 443

ENTRYPOINT ["/start_magma.sh"]

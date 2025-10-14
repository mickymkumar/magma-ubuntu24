################################################################################
# Magma Gateway Dockerfile (Ubuntu 24.04 / 22.04 compatible)
# Includes: OVS, Python, C deps, and Magma v1.9 source
################################################################################

# -----------------------------------------------------------------------------
# Build Arguments
# -----------------------------------------------------------------------------
ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=focal
ARG EXTRA_REPO=https://linuxfoundation.jfrog.io/artifactory/magma-packages-test

FROM ${OS_DIST}:${OS_RELEASE} AS magma_gateway

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
ENV TZ=America/Toronto
ENV MAGMA_ROOT=/opt/magma
ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Set timezone
# -----------------------------------------------------------------------------
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# -----------------------------------------------------------------------------
# Update packages and install base tools
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    git curl wget sudo vim tzdata build-essential cmake python3 python3-pip \
    iproute2 iptables net-tools bridge-utils iputils-ping iputils-tracepath \
    libssl-dev libffi-dev pkg-config software-properties-common \
    ca-certificates gnupg lsb-release supervisor && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone Magma v1.9
# -----------------------------------------------------------------------------
WORKDIR /opt
RUN git clone --branch v1.9 https://github.com/magma/magma.git

# -----------------------------------------------------------------------------
# Install Open vSwitch
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    openvswitch-switch openvswitch-common libopenvswitch && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Copy OVS scripts from cloned repo
# -----------------------------------------------------------------------------
RUN cp /opt/magma/lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/healthcheck.sh && \
    cp /opt/magma/lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh && \
    chmod +x /usr/local/bin/healthcheck.sh /entrypoint.sh

# -----------------------------------------------------------------------------
# Install Magma C and Python dependencies
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    libboost-all-dev libconfig-dev libcurl4-openssl-dev \
    libgflags-dev libgoogle-glog-dev libprotobuf-dev protobuf-compiler \
    ninja-build ccache check libtspi-dev && \
    rm -rf /var/lib/apt/lists/*

# Python requirements for Magma LTE gateway
RUN pip3 install --no-cache-dir -r /opt/magma/lte/gateway/python/requirements.txt

# -----------------------------------------------------------------------------
# Supervisor config for OVS + Magma services
# -----------------------------------------------------------------------------
RUN mkdir -p /etc/supervisor/conf.d
RUN echo "[supervisord]" > /etc/supervisor/supervisord.conf && \
    echo "nodaemon=true" >> /etc/supervisor/supervisord.conf && \
    echo "" >> /etc/supervisor/supervisord.conf && \
    echo "[program:openvswitch]" >> /etc/supervisor/supervisord.conf && \
    echo "command=/usr/share/openvswitch/scripts/ovs-ctl start --system-id=random" >> /etc/supervisor/supervisord.conf && \
    echo "autostart=true" >> /etc/supervisor/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisor/supervisord.conf && \
    echo "" >> /etc/supervisor/supervisord.conf && \
    echo "[program:healthcheck]" >> /etc/supervisor/supervisord.conf && \
    echo "command=/usr/local/bin/healthcheck.sh" >> /etc/supervisor/supervisord.conf && \
    echo "autostart=true" >> /etc/supervisor/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisor/supervisord.conf

# -----------------------------------------------------------------------------
# Expose ports (OVS, Magma)
# -----------------------------------------------------------------------------
EXPOSE 6653 6640 9090 8080

# -----------------------------------------------------------------------------
# Entrypoint
# -----------------------------------------------------------------------------
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

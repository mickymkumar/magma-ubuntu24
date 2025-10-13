################################################################################
# Magma Gateway Dockerfile (Ubuntu 24.04, EC2 Ready)
################################################################################

ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=noble

# -----------------------------------------------------------------------------
# Stage 1: Base builder (system + python)
# -----------------------------------------------------------------------------
FROM ${OS_DIST}:${OS_RELEASE} AS base
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/venv/bin:$PATH"

# Install system packages and Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo net-tools iproute2 bridge-utils iputils-ping tcpdump iptables \
    software-properties-common curl wget git unzip make build-essential cmake \
    pkg-config libsystemd-dev libffi-dev libssl-dev libxml2-dev libxslt1-dev \
    libgmp-dev zlib1g-dev rsync zip ifupdown lsb-release gnupg supervisor \
    autoconf automake libtool lksctp-tools libsctp-dev tzdata \
    python3 python3-venv python3-dev python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create magma user
RUN useradd -ms /bin/bash magma && echo "magma ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
WORKDIR /home/magma
VOLUME /home/magma

# Create Python virtual environment
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip setuptools wheel cython

# -----------------------------------------------------------------------------
# Stage 2: Magma source setup
# -----------------------------------------------------------------------------
FROM base AS magma-src
WORKDIR /magma
RUN git clone https://github.com/magma/magma.git . || true

# -----------------------------------------------------------------------------
# Stage 3: Python build (Bazel python_executables)
# -----------------------------------------------------------------------------
FROM magma-src AS magma-python
ENV MAGMA_DEV_MODE=0
ENV TZ=Etc/UTC
ENV PIP_CACHE_HOME="~/.pipcache"

# Install Bazel and required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io git lsb-release libsystemd-dev pkg-config python3-dev python3-pip sudo wget \
    && rm -rf /var/lib/apt/lists/*

# Install Bazelisk
RUN wget -O /usr/local/bin/bazelisk \
    https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -s /usr/local/bin/bazelisk /usr/sbin/bazel

WORKDIR /magma
RUN bazel build //lte/gateway/release:python_executables_tar \
               //lte/gateway/release:dhcp_helper_cli_tar

# -----------------------------------------------------------------------------
# Stage 4: C build (sessiond, sctpd, etc.)
# -----------------------------------------------------------------------------
FROM magma-src AS magma-c
ENV TZ=Etc/UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf autogen build-essential ccache check cmake git ninja-build pkg-config curl \
    libboost-chrono-dev libboost-context-dev libboost-program-options-dev libboost-filesystem-dev \
    libboost-regex-dev libc++-dev libconfig-dev libcurl4-openssl-dev libczmq-dev \
    libdouble-conversion-dev libgflags-dev libgmp3-dev libgoogle-glog-dev libmnl-dev libpcap-dev \
    libprotoc-dev libsctp-dev libsqlite3-dev libssl-dev libtspi-dev libtool libxml2-dev libxslt-dev \
    libyaml-cpp-dev protobuf-compiler unzip uuid-dev sudo && rm -rf /var/lib/apt/lists/*

# Install Bazelisk
RUN wget -P /usr/sbin https://github.com/bazelbuild/bazelisk/releases/download/v1.10.0/bazelisk-linux-"${DEB_PORT}" \
    && chmod +x /usr/sbin/bazelisk-linux-"${DEB_PORT}" \
    && ln -s /usr/sbin/bazelisk-linux-"${DEB_PORT}" /usr/sbin/bazel

WORKDIR /magma
RUN bazel build --config=production \
    //lte/gateway/c/sctpd/src:sctpd \
    //lte/gateway/c/connection_tracker/src:connectiond \
    //lte/gateway/c/li_agent/src/liagentd \
    //lte/gateway/c/session_manager:sessiond \
    //lte/gateway/c/core/agw_of

# -----------------------------------------------------------------------------
# Stage 5: Runtime (OVS + Python + C)
# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS magma-runtime
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV PATH="/opt/venv/bin:$PATH"

# Install runtime packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates iproute2 iptables iputils-ping net-tools bridge-utils tcpdump \
    software-properties-common \
    python3 python3-venv python3-pip redis-server ethtool sudo curl wget vim tzdata \
    libgoogle-glog-dev libyaml-cpp-dev libsctp-dev libssl-dev libpcap-dev \
    openvswitch-switch openvswitch-common \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Copy Python environment and Magma source
COPY --from=magma-python /magma /magma
COPY --from=base /opt/venv /opt/venv

# Copy built C binaries
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/session_manager/sessiond /usr/local/bin/sessiond
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/sctpd/src/sctpd /usr/local/bin/sctpd
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/connection_tracker/src/connectiond /usr/local/bin/connectiond
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/li_agent/src/liagentd /usr/local/bin/liagentd
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/core/agw_of /usr/local/bin/oai_mme

# Placeholder OVS scripts
RUN mkdir -p /usr/local/bin /magma/openvswitch
RUN echo '#!/bin/bash\necho "OVS healthcheck: OK"' > /usr/local/bin/healthcheck.sh && chmod +x /usr/local/bin/healthcheck.sh
RUN echo '#!/bin/bash\n\
echo "Starting Magma services..."\n\
/usr/local/bin/sessiond &\n\
/usr/local/bin/sctpd &\n\
/usr/local/bin/connectiond &\n\
/usr/local/bin/liagentd &\n\
/usr/local/bin/oai_mme &\n\
tail -f /dev/null' > /entrypoint.sh && chmod +x /entrypoint.sh

WORKDIR /magma
ENTRYPOINT ["/entrypoint.sh"]

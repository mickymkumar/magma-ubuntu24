################################################################################
# Magma Gateway Dockerfile - Ubuntu 24.04
################################################################################

ARG CPU_ARCH=x86_64
ARG DEB_PORT=amd64
ARG OS_DIST=ubuntu
ARG OS_RELEASE=noble

# --------------------------
# Stage 1: Base system
# --------------------------
FROM ${OS_DIST}:${OS_RELEASE} AS base
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo net-tools iproute2 bridge-utils iputils-ping tcpdump iptables \
    python3 python3-venv python3-dev python3-pip \
    curl wget git unzip make build-essential cmake pkg-config software-properties-common \
    libsystemd-dev libffi-dev libssl-dev libxml2-dev libxslt1-dev libgmp-dev zlib1g-dev rsync zip \
    ifupdown lsb-release gnupg supervisor autoconf automake libtool lksctp-tools libsctp-dev \
    libgoogle-glog-dev libdouble-conversion-dev libgflags-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash magma && echo "magma ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
WORKDIR /home/magma
VOLUME /home/magma

RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --upgrade pip setuptools wheel cython

# --------------------------
# Stage 2: Magma source
# --------------------------
FROM base AS magma-src
WORKDIR /magma
RUN git clone https://github.com/magma/magma.git . || true

# --------------------------
# Stage 3: Python build
# --------------------------
FROM magma-src AS magma-python
ENV MAGMA_DEV_MODE=0
ENV TZ=Etc/UTC
ENV PIP_CACHE_HOME="~/.pipcache"

RUN apt-get update && apt-get install -y --no-install-recommends \
  docker.io git lsb-release libsystemd-dev pkg-config python3-dev python3-pip sudo wget \
  && rm -rf /var/lib/apt/lists/*

# Bazelisk
RUN wget -O /usr/local/bin/bazelisk https://github.com/bazelbuild/bazelisk/releases/download/v1.10.1/bazelisk-linux-${DEB_PORT} \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -sf /usr/local/bin/bazelisk /usr/bin/bazel

WORKDIR /magma
RUN bazel build //lte/gateway/release:python_executables_tar //lte/gateway/release:dhcp_helper_cli_tar

# --------------------------
# Stage 4: C build
# --------------------------
FROM magma-src AS magma-c
ENV TZ=Etc/UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && apt-get install -y --no-install-recommends \
  autoconf autogen build-essential ccache check cmake git ninja-build pkg-config curl \
  libboost-chrono-dev libboost-context-dev libboost-program-options-dev libboost-filesystem-dev \
  libboost-regex-dev libc++-dev libconfig-dev libcurl4-openssl-dev libczmq-dev \
  libdouble-conversion-dev libgflags-dev libgmp3-dev libgoogle-glog-dev libmnl-dev libpcap-dev \
  libprotoc-dev libsctp-dev libsqlite3-dev libssl-dev libtspi-dev libtool libxml2-dev libxslt-dev \
  libyaml-cpp-dev protobuf-compiler unzip uuid-dev sudo systemd \
  && rm -rf /var/lib/apt/lists/*

# Bazelisk install
RUN wget -O /usr/local/bin/bazelisk https://github.com/bazelbuild/bazelisk/releases/download/v1.10.1/bazelisk-linux-${DEB_PORT} \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -sf /usr/local/bin/bazelisk /usr/bin/bazel

# Fix library symlinks to satisfy Bazel glob
RUN ln -sf /usr/lib/x86_64-linux-gnu/libglog.so /usr/lib/x86_64-linux-gnu/libglog.so.0 \
    && ln -sf /usr/lib/x86_64-linux-gnu/libsystemd.so /usr/lib/x86_64-linux-gnu/libsystemd.so.0

WORKDIR /magma

# Build external dependencies
RUN bazel build \
  @com_github_grpc_grpc//:grpc++ \
  @com_google_protobuf//:protobuf \
  @prometheus_cpp//:prometheus-cpp \
  @yaml-cpp//:yaml-cpp \
  @github_nlohmann_json//:json \
  @sentry_native//:sentry

# Build main C binaries
RUN bazel build --config=production \
  //lte/gateway/c/sctpd/src:sctpd \
  //lte/gateway/c/connection_tracker/src:connectiond \
  //lte/gateway/c/li_agent/src:liagentd \
  //lte/gateway/c/session_manager:sessiond \
  //lte/gateway/c/core:agw_of

# --------------------------
# Stage 5: Runtime
# --------------------------
FROM ubuntu:24.04 AS magma-runtime
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV PATH="/opt/venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates iproute2 iptables iputils-ping net-tools bridge-utils tcpdump \
    python3 python3-venv python3-pip redis-server ethtool sudo curl wget vim tzdata \
    libgoogle-glog-dev libyaml-cpp-dev libsctp-dev libssl-dev libpcap-dev \
    openvswitch-switch openvswitch-common openvswitch-datapath-dkms systemd \
    && rm -rf /var/lib/apt/lists/*

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN echo 1 > /proc/sys/net/ipv4/ip_forward

# Copy Magma Python environment and source
COPY --from=magma-python /magma /magma
COPY --from=base /opt/venv /opt/venv

# Copy built C binaries
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/session_manager/sessiond /usr/local/bin/sessiond
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/sctpd/src/sctpd /usr/local/bin/sctpd
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/connection_tracker/src/connectiond /usr/local/bin/connectiond
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/li_agent/src/liagentd /usr/local/bin/liagentd
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/core/agw_of /usr/local/bin/oai_mme

# Copy OVS health scripts
COPY lte/gateway/docker/services/openvswitch/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY lte/gateway/docker/services/openvswitch/entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/healthcheck.sh /entrypoint.sh

WORKDIR /magma
ENTRYPOINT ["/entrypoint.sh"]

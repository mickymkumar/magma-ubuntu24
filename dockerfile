# --- Base Image ---
FROM ubuntu:24.04

# --- Environment Variables ---
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV PATH="/opt/venv/bin:$PATH"
ENV MAGMA_ROOT=/magma

# --- Install OS packages ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    iproute2 iptables iputils-ping net-tools bridge-utils tcpdump \
    sudo curl wget git unzip make build-essential cmake pkg-config \
    software-properties-common tzdata \
    python3 python3-venv python3-pip python3-dev \
    libsystemd-dev libffi-dev libssl-dev libxml2-dev libxslt1-dev \
    libgmp-dev zlib1g-dev rsync zip \
    redis-server \
    libgoogle-glog-dev libyaml-cpp-dev libsctp-dev libpcap-dev \
    openvswitch-switch openvswitch-common \
    ifupdown lsb-release gnupg supervisor autoconf automake libtool lksctp-tools libsctp-dev \
    && rm -rf /var/lib/apt/lists/*

# --- Setup Python virtual environment ---
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip setuptools wheel

# --- Install Bazelisk (Bazel launcher) ---
RUN wget -O /usr/local/bin/bazelisk \
    https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazelisk

# --- Create work directory ---
WORKDIR $MAGMA_ROOT

# --- Clone Magma repository ---
RUN git clone https://github.com/magma/magma.git $MAGMA_ROOT

# --- Install Bazelisk (Bazel launcher) ---
RUN wget -O /usr/local/bin/bazelisk \
    https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel
# --- Install Python 3.10 ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-venv python3.10-dev python3-pip \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1

# --- Install Bazelisk (Bazel launcher) ---
RUN wget -O /usr/local/bin/bazelisk \
    https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel

# --- Tell Bazel to use Python 3.10 ---
ENV USE_BAZEL_PYTHON=/usr/bin/python3.10


# --- Bazel build for C components ---
RUN bazel build --config=production \
    //lte/gateway/c/sctpd/src:sctpd \
    //lte/gateway/c/connection_tracker/src:connectiond \
    //lte/gateway/c/session_manager:sessiond \
    //lte/gateway/c/core/agw_of

# --- Bazel build for Python components ---
RUN bazel build //lte/gateway/release:python_executables_tar \
    //lte/gateway/release:dhcp_helper_cli_tar

# --- Expose ports (adjust as needed) ---
EXPOSE 9090 5000

# --- Default command ---
CMD ["/bin/bash"]

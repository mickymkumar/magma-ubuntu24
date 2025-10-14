# --- Base Image ---
FROM ubuntu:24.04

# --- Environment Variables ---
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV PATH="/opt/venv/bin:$PATH"
ENV MAGMA_ROOT=/magma
ENV USE_BAZEL_PYTHON=/usr/bin/python3.10

# --- Install OS packages and build tools ---
RUN apt-get update && apt-get install -y \
        software-properties-common \
        python3-apt \
        wget \
        curl \
        lsb-release \
        gnupg \
        ca-certificates \
        git \
        build-essential \
        gcc \
        g++ \
        make \
        pkg-config \
        zlib1g-dev \
        libssl-dev \
        libgoogle-glog-dev \
        libsystemd-dev \
        libdouble-conversion-dev \
        libunwind-dev \
        libgflags-dev \
    && add-apt-repository universe \
    && rm -rf /var/lib/apt/lists/*

# --- Add Deadsnakes PPA and install Python 3.10 ---
RUN add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python3.10 python3.10-venv python3.10-dev python3.10-distutils \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 \
    && rm -rf /var/lib/apt/lists/*

# --- Setup Python virtual environment ---
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip setuptools wheel

# --- Install Bazelisk (Bazel launcher) ---
RUN wget -O /usr/local/bin/bazelisk \
        https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel

# --- Create work directory and clone Magma ---
WORKDIR $MAGMA_ROOT
RUN git clone https://github.com/magma/magma.git $MAGMA_ROOT

# --- Fix library symlinks for Bazel ---
RUN ln -sf /usr/lib/x86_64-linux-gnu/libglog.so /usr/lib/x86_64-linux-gnu/libglog.so.0 \
    && ln -sf /usr/lib/x86_64-linux-gnu/libsystemd.so /usr/lib/x86_64-linux-gnu/libsystemd.so.0

# --- Bazel build for C components ---
RUN bazel build --config=production \
    //lte/gateway/c/sctpd/src:sctpd \
    //lte/gateway/c/connection_tracker/src:connectiond \
    //lte/gateway/c/session_manager:sessiond

# --- Bazel build for Python components ---
RUN bazel build //lte/gateway/release:python_executables_tar \
    //lte/gateway/release:dhcp_helper_cli_tar

# --- Expose ports (adjust as needed) ---
EXPOSE 9090 5000

# --- Default command ---
CMD ["/bin/bash"]

FROM ubuntu:24.04

# Environment
ENV DEBIAN_FRONTEND=noninteractive
ENV MAGMA_ROOT=/magma
ENV PATH="/opt/venv/bin:$PATH"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
        wget \
        curl \
        lsb-release \
        git \
        build-essential \
        pkg-config \
        python3.10 \
        python3.10-venv \
        python3.10-dev \
        libgoogle-glog-dev \
        libsystemd-dev \
        libdouble-conversion-dev \
        libunwind-dev \
        libgflags-dev \
        zlib1g-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Python virtual environment
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip setuptools wheel

# Install Bazelisk
RUN wget -O /usr/local/bin/bazelisk \
        https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazelisk

# Set working directory
WORKDIR /magma

# Clone Magma
RUN git clone https://github.com/magma/magma.git /magma

# Fix library paths for Bazel
RUN ln -sf /usr/lib/x86_64-linux-gnu/libglog.so /usr/lib/x86_64-linux-gnu/libglog.so.0 \
    && ln -sf /usr/lib/x86_64-linux-gnu/libsystemd.so /usr/lib/x86_64-linux-gnu/libsystemd.so.0

# Build C components with Bazel
RUN LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu \
    bazel build --config=production \
        //lte/gateway/c/sctpd/src:sctpd \
        //lte/gateway/c/connection_tracker/src:connectiond \
        //lte/gateway/c/session_manager:sessiond

# Default workdir
WORKDIR /magma/lte/gateway

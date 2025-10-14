# --- Base Image ---
FROM ubuntu:24.04

# --- Environment Variables ---
ENV DEBIAN_FRONTEND=noninteractive
ENV MAGMA_ROOT=/magma
ENV PATH="/opt/venv/bin:$PATH"

# --- Install System Dependencies ---
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

# --- Python Virtual Environment ---
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip setuptools wheel

# --- Install Bazelisk (Bazel wrapper) ---
RUN wget -O /usr/local/bin/bazelisk \
        https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazelisk

# --- Set Working Directory ---
WORKDIR /magma

# --- Clone Magma Repository ---
RUN git clone https://github.com/magma/magma.git /magma

# --- Fix Library Paths for Bazel ---
# Bazel's glob needs exact filenames
RUN ln -sf /usr/lib/x86_64-linux-gnu/libglog.so /usr/lib/x86_64-linux-gnu/libglog.so.0 \
    && ln -sf /usr/lib/x86_64-linux-gnu/libsystemd.so /usr/lib/x86_64-linux-gnu/libsystemd.so.0

# --- Build C Components with Bazel ---
RUN LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu \
    bazel build --config=production \
        //lte/gateway/c/sctpd/src:sctpd \
        //lte/gateway/c/connection_tracker/src:connectiond \
        //lte/gateway/c/session_manager:sessiond

# --- Set Default Workdir ---
WORKDIR /magma/lte/gateway

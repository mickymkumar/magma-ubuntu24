#!/bin/bash
set -e

# --- 1. Update and install dependencies ---
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    python3.10 python3.10-venv python3.10-dev python3.10-distutils \
    libgoogle-glog-dev \
    libsystemd-dev \
    pkg-config \
    g++ \
    cmake \
    zlib1g-dev \
    libssl-dev \
    libunwind-dev \
    libgflags-dev

# --- 2. Ensure Bazelisk is installed ---
if ! command -v bazel &> /dev/null; then
    wget -O /usr/local/bin/bazelisk https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64
    chmod +x /usr/local/bin/bazelisk
    ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel
fi

# --- 3. Fix symlinks for Bazel glob patterns ---
sudo ln -sf /usr/lib/x86_64-linux-gnu/libglog.so /usr/lib/x86_64-linux-gnu/libglog.so.0
sudo ln -sf /usr/lib/x86_64-linux-gnu/libsystemd.so /usr/lib/x86_64-linux-gnu/libsystemd.so.0

# --- 4. Set Python 3.10 as default for Bazel ---
export USE_BAZEL_PYTHON=/usr/bin/python3.10

# --- 5. Clone Magma (if not done yet) ---
if [ ! -d "$HOME/magma" ]; then
    git clone https://github.com/magma/magma.git $HOME/magma
fi

cd $HOME/magma

# --- 6. Run Bazel build ---
bazel build --config=production \
    //lte/gateway/c/sctpd/src:sctpd \
    //lte/gateway/c/connection_tracker/src:connectiond \
    //lte/gateway/c/session_manager:sessiond

echo "✅ Bazel C components build completed successfully!"

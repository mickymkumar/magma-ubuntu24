# Base image
FROM ubuntu:24.04

# Set environment variables to avoid prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update packages and install basic dependencies
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
    software-properties-common \
    curl \
    wget \
    git \
    lsb-release \
    ca-certificates \
    apt-transport-https \
    gnupg \
    build-essential \
    cmake \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Verify Ubuntu version
RUN lsb_release -a

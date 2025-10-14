# -----------------------------------------------------------------------------
# Stage: Magma runtime (Ubuntu 24.04)
# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS magma-runtime
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/venv/bin:$PATH"

# Install required system packages and Python 3.12
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates iproute2 iptables iputils-ping net-tools bridge-utils tcpdump \
    python3 python3-venv python3-pip redis-server ethtool sudo curl wget vim tzdata \
    libgoogle-glog-dev libyaml-cpp-dev libsctp-dev libssl-dev libpcap-dev \
    openvswitch-switch openvswitch-common \
    && rm -rf /var/lib/apt/lists/*

# Create Python virtual environment using Python 3
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --upgrade pip setuptools wheel

# Timezone setup
ENV TZ=Etc/UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Copy Magma source and binaries from build stages
COPY --from=magma-python /magma /magma
COPY --from=base /opt/venv /opt/venv
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/session_manager/sessiond /usr/local/bin/sessiond
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/sctpd/src/sctpd /usr/local/bin/sctpd
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/connection_tracker/src/connectiond /usr/local/bin/connectiond
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/li_agent/src/liagentd /usr/local/bin/liagentd
COPY --from=magma-c /magma/bazel-bin/lte/gateway/c/core/agw_of /usr/local/bin/oai_mme

# Entry point
RUN echo '#!/bin/bash\n\
echo "Starting Magma runtime..."\n\
tail -f /dev/null' > /entrypoint.sh && chmod +x /entrypoint.sh
WORKDIR /magma
ENTRYPOINT ["/entrypoint.sh"]

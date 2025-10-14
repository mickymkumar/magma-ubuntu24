#!/bin/bash
set -e

echo "Starting Open vSwitch..."
ovsdb-server --remote=punix:/var/run/openvswitch/db.sock --pidfile --detach
ovs-vsctl --no-wait init
ovs-vswitchd --pidfile --detach

echo "Skipping vport_gtp DKMS if missing..."
# Actual DKMS build is skipped in patched entrypoint

echo "Starting Python Magma services..."
cd /magma/lte/gateway/python
python3 -m magma.main &

echo "Container ready. OVS and Python services running."
exec bash

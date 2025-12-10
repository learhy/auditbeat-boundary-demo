#!/bin/bash
# Start Boundary Dev with Enterprise License

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LICENSE_FILE="$SCRIPT_DIR/boundary-license.hclic"

if [ ! -f "$LICENSE_FILE" ]; then
    echo "❌ Error: boundary-license.hclic not found in $SCRIPT_DIR"
    echo "Please ensure your enterprise license file is present."
    exit 1
fi

echo "🔑 Loading Boundary Enterprise License..."
export BOUNDARY_LICENSE="$(cat "$LICENSE_FILE")"

echo "🚀 Starting Boundary Dev with Enterprise License..."
echo ""
echo "📋 Important: Keep this terminal window open!"
echo "   Press Ctrl+C to stop Boundary"
echo ""
echo "✅ Enterprise features enabled:"
echo "   - SSH target type with certificate injection"
echo "   - Credential injection (not just brokering)"
echo "   - Session recording"
echo ""

# Make the dev worker reachable from Docker containers by advertising a
# public address on the host and binding the proxy listener on 0.0.0.0.
export BOUNDARY_DEV_WORKER_PUBLIC_ADDRESS="host.docker.internal:9202"
export BOUNDARY_DEV_WORKER_PROXY_LISTEN_ADDRESS="0.0.0.0:9202"

# Start boundary dev with the license
boundary dev

#!/bin/bash

# Boundary Session Generator
# This script authenticates with Boundary and establishes REAL SSH connections
# through Boundary with injected SSH certificates, executing commands that
# trigger audit events captured by Auditbeat.

set -e

BOUNDARY_ADDR="${BOUNDARY_ADDR:-http://host.docker.internal:9200}"
SHARED_DIR="/shared"
LOG_FILE="/tmp/audit-demo/boundary-activity.log"
mkdir -p /tmp/audit-demo

# Function to log session activity
log_activity() {
  local msg="$1"
  echo "$(date -u +%Y-%m-%dT%H:%M:%S)Z $msg" | tee -a "$LOG_FILE"
}

log_activity "Starting Boundary session generation"

# Wait for TARGET_ID from boundary-setup
echo "⏳ Waiting for TARGET_ID from boundary-setup..."
for i in $(seq 1 60); do
  if [ -s "$SHARED_DIR/target-id" ]; then
    TARGET_ID=$(cat "$SHARED_DIR/target-id")
    log_activity "✅ Got TARGET_ID: $TARGET_ID"
    break
  fi
  echo "  Waiting for target-id ($i)..."; sleep 2
  if [ "$i" -eq 60 ]; then
    log_activity "❌ TARGET_ID not found after 60 attempts"
    exit 0
  fi
done

# Wait for AUTH_METHOD_ID from boundary-setup
echo "⏳ Waiting for AUTH_METHOD_ID from boundary-setup..."
for i in $(seq 1 60); do
  if [ -s "$SHARED_DIR/auth-method-id" ]; then
    AUTH_METHOD_ID=$(cat "$SHARED_DIR/auth-method-id")
    log_activity "✅ Got AUTH_METHOD_ID: $AUTH_METHOD_ID"
    break
  fi
  echo "  Waiting for auth-method-id ($i)..."; sleep 2
  if [ "$i" -eq 60 ]; then
    log_activity "❌ AUTH_METHOD_ID not found after 60 attempts"
    exit 0
  fi
done

# Wait for Boundary to be ready
log_activity "Checking Boundary availability at $BOUNDARY_ADDR..."
for i in $(seq 1 30); do
  if curl -sf "$BOUNDARY_ADDR/v1/scopes" >/dev/null 2>&1; then
    log_activity "✅ Boundary is available"
    break
  fi
  echo "  Waiting for Boundary ($i)..."; sleep 3
  if [ "$i" -eq 30 ]; then
    log_activity "❌ Boundary not available"
    exit 0
  fi
done

# Check if boundary CLI is available
if ! command -v boundary >/dev/null 2>&1; then
  log_activity "❌ boundary CLI not found in PATH"
  exit 1
fi

log_activity "🔑 Authenticating to Boundary..."

# Authenticate with Boundary and capture token
export BOUNDARY_ADDR
export BOUNDARY_PASSWORD=password
AUTH_OUTPUT=$(boundary authenticate password \
  -auth-method-id "$AUTH_METHOD_ID" \
  -login-name admin \
  -password env://BOUNDARY_PASSWORD \
  -keyring-type none \
  -format json 2>&1)

if [ $? -ne 0 ]; then
  log_activity "❌ Failed to authenticate with Boundary"
  echo "$AUTH_OUTPUT" | tee -a "$LOG_FILE"
  exit 0
fi

# Extract token from JSON response
BOUNDARY_TOKEN=$(echo "$AUTH_OUTPUT" | jq -r '.item.attributes.token' 2>/dev/null)
if [ -z "$BOUNDARY_TOKEN" ] || [ "$BOUNDARY_TOKEN" = "null" ]; then
  log_activity "❌ Failed to extract token from auth response"
  exit 0
fi

export BOUNDARY_TOKEN
log_activity "✅ Authenticated with Boundary"

# Establish SSH session through Boundary and run commands
log_activity "🔔 Establishing SSH session through Boundary to target $TARGET_ID..."

# Run commands through Boundary SSH connection using -remote-command
log_activity "Running whoami command..."
if boundary connect ssh \
  -addr "$BOUNDARY_ADDR" \
  -token env://BOUNDARY_TOKEN \
  -target-id "$TARGET_ID" \
  -username ubuntu \
  -remote-command 'whoami' 2>&1 | tee -a "$LOG_FILE"; then
  log_activity "✅ SSH session 1 (whoami) completed"
else
  log_activity "⚠️ SSH session 1 failed"
fi

log_activity "Reading /etc/passwd..."
if boundary connect ssh \
  -addr "$BOUNDARY_ADDR" \
  -token env://BOUNDARY_TOKEN \
  -target-id "$TARGET_ID" \
  -username ubuntu \
  -remote-command 'cat /etc/passwd' 2>&1 | tee -a "$LOG_FILE"; then
  log_activity "✅ SSH session 2 (cat /etc/passwd) completed"
else
  log_activity "⚠️ SSH session 2 failed"
fi

log_activity "Listing processes..."
if boundary connect ssh \
  -addr "$BOUNDARY_ADDR" \
  -token env://BOUNDARY_TOKEN \
  -target-id "$TARGET_ID" \
  -username ubuntu \
  -remote-command 'ps aux' 2>&1 | tee -a "$LOG_FILE"; then
  log_activity "✅ SSH session 3 (ps aux) completed"
else
  log_activity "⚠️ SSH session 3 failed"
fi

log_activity "🏁 Session generation cycle complete"
exit 0

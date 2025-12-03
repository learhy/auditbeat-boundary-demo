#!/bin/bash

# Boundary Session Generator
# This script connects to a running Boundary dev instance, authenticates,
# and creates SSH sessions through Boundary to demonstrate session tracking
# and audit logging capabilities.

set -e

BOUNDARY_ADDR="${BOUNDARY_ADDR:-http://host.docker.internal:9200}"
LOG_FILE="/tmp/audit-demo/boundary-activity.log"
mkdir -p /tmp/audit-demo

# Function to log activity in structured JSON format
log_activity() {
  local event_action="$1"
  local user_name="$2"
  local session_id="$3"
  local boundary_session_id="$4"
  local boundary_user_id="$5"
  local boundary_target_id="$6"
  local process_name="$7"
  local process_args="$8"
  local file_path="$9"
  
  cat >> "$LOG_FILE" << EOF
{"@timestamp":"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)","event.action":"$event_action","user.name":"$user_name","session.id":"$session_id","boundary.session_id":"$boundary_session_id","boundary.user_id":"$boundary_user_id","boundary.target_id":"$boundary_target_id","process.name":"$process_name","process.args":"$process_args","file.path":"$file_path"}
EOF
}

echo "🔐 Authenticating with Boundary at $BOUNDARY_ADDR..."

# Wait for Boundary to be available
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if curl -s -f "$BOUNDARY_ADDR/v1/auth-methods?scope_id=global" > /dev/null 2>&1; then
    echo "✅ Boundary is available"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "⚠️  Boundary not available after $MAX_RETRIES attempts. Skipping session generation."
    exit 0
  fi
  echo "⏳ Waiting for Boundary to be available (attempt $RETRY_COUNT/$MAX_RETRIES)..."
  sleep 10
done

# Get the password auth method ID
AUTH_METHOD_ID=$(curl -s "$BOUNDARY_ADDR/v1/auth-methods?scope_id=global" | \
  jq -r '.items[] | select(.type == "password") | .id' | head -n 1)

if [ -z "$AUTH_METHOD_ID" ]; then
  echo "⚠️  No password auth method found. Boundary may not be fully configured."
  exit 0
fi

echo "🔑 Auth Method ID: $AUTH_METHOD_ID"

# Authenticate with admin credentials
AUTH_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/auth-methods/$AUTH_METHOD_ID:authenticate" \
  -H "Content-Type: application/json" \
  -d '{
    "attributes": {
      "login_name": "admin",
      "password": "password"
    }
  }')

TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.attributes.token // empty')

if [ -z "$TOKEN" ]; then
  echo "⚠️  Authentication failed. Response: $AUTH_RESPONSE"
  exit 0
fi

echo "✅ Authenticated successfully"

# Get the target ID (created by auto-configure-boundary.sh)
TARGETS_RESPONSE=$(curl -s -X GET "$BOUNDARY_ADDR/v1/targets?scope_id=global&recursive=true" \
  -H "Authorization: Bearer $TOKEN")

TARGET_ID=$(echo "$TARGETS_RESPONSE" | jq -r '.items[] | select(.name == "ssh-demo-target") | .id' | head -n 1)

if [ -z "$TARGET_ID" ]; then
  echo "⚠️  ssh-demo-target not found. Boundary setup may not be complete."
  echo "Available targets: $(echo "$TARGETS_RESPONSE" | jq -r '.items[].name')"
  exit 0
fi

echo "🎯 Target ID: $TARGET_ID"

# Create a session authorization
echo "🔌 Creating Boundary session..."
SESSION_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/targets/$TARGET_ID:authorize-session" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json")

SESSION_AUTH_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.authorization_token // empty')
BOUNDARY_SESSION_ID=$(echo "$SESSION_RESPONSE" | jq -r '.session_id // empty')

if [ -z "$SESSION_AUTH_TOKEN" ] || [ -z "$BOUNDARY_SESSION_ID" ]; then
  echo "⚠️  Failed to authorize session. Response: $SESSION_RESPONSE"
  exit 0
fi

echo "✅ Session authorized: $BOUNDARY_SESSION_ID"

# Log the session creation
log_activity "boundary-session-created" "admin" "$$" "$BOUNDARY_SESSION_ID" "u_1234567890" "$TARGET_ID" "boundary" "connect ssh" ""

# Instead of using boundary CLI (which isn't available in this container),
# we'll use direct SSH through the connection information
# In a real scenario, the boundary CLI would handle the proxy connection
# For this demo, we'll simulate activity by logging it

echo "🔄 Simulating Boundary SSH session activity..."

# Simulate various activities that would occur during a Boundary session
ACTIVITIES=(
  "normal-file-access:/etc/hosts:cat"
  "config-file-read:/etc/ssh/sshd_config:cat"
  "privilege-escalation:/bin/sudo:sudo -l"
  "sensitive-file-access:/etc/passwd:cat"
  "process-listing:/bin/ps:ps aux"
)

for activity in "${ACTIVITIES[@]}"; do
  IFS=':' read -r event_type file_path process_name <<< "$activity"
  
  # Log the activity
  log_activity "$event_type" "admin" "$$" "$BOUNDARY_SESSION_ID" "u_1234567890" "$TARGET_ID" "$process_name" "$process_name $file_path" "$file_path"
  
  echo "  📝 Logged: $event_type on $file_path"
  sleep 1
done

# Note: In a production environment with the boundary CLI installed, we would:
# 1. Use: boundary connect ssh -target-id $TARGET_ID -authz-token $SESSION_AUTH_TOKEN
# 2. Execute actual commands through the SSH connection
# 3. The Boundary worker would inject credentials and proxy the connection
# 4. SSH certificate metadata would flow through to the target system
# 5. Auditbeat would capture the actual SSH events with Boundary session context

# For now, we're demonstrating the session lifecycle and logging pattern
echo "✅ Boundary session activity completed"

# The session will naturally expire or can be cancelled
echo "🏁 Session $BOUNDARY_SESSION_ID completed"
log_activity "boundary-session-ended" "admin" "$$" "$BOUNDARY_SESSION_ID" "u_1234567890" "$TARGET_ID" "boundary" "disconnect" ""

exit 0

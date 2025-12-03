#!/bin/sh

echo "🎯 Auto-configuring Boundary for SSH session monitoring..."

BOUNDARY_ADDR="http://host.docker.internal:9200"
echo "Waiting for Boundary dev instance at $BOUNDARY_ADDR..."

# Wait up to 5 minutes for Boundary to be ready
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if curl -s "$BOUNDARY_ADDR/v1/scopes" > /dev/null 2>&1; then
        echo "✅ Boundary detected!"
        break
    fi
    echo "⏳ Waiting for Boundary dev... (${ELAPSED}s elapsed)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "❌ Boundary dev not found after 5 minutes"
    echo "🚨 PLEASE RUN: boundary dev"
    exit 1
fi

# Get the password auth method specifically
echo "🔍 Getting password auth method..."
AUTH_METHODS_RESPONSE=$(curl -s "$BOUNDARY_ADDR/v1/auth-methods?scope_id=global")
AUTH_METHOD_ID=$(echo "$AUTH_METHODS_RESPONSE" | jq -r '.items[] | select(.type=="password") | .id' 2>/dev/null)

if [ -z "$AUTH_METHOD_ID" ] || [ "$AUTH_METHOD_ID" = "null" ]; then
    echo "❌ Failed to get password auth method ID"
    exit 1
fi

echo "✅ Password Auth Method ID: $AUTH_METHOD_ID"

# Authenticate using CORRECT format with "attributes"
echo "🔐 Authenticating with Boundary..."
AUTH_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/auth-methods/$AUTH_METHOD_ID:authenticate" \
    -H "Content-Type: application/json" \
    -d '{"attributes": {"login_name": "admin", "password": "password"}}')

# Extract token from the CORRECT location
TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.attributes.token' 2>/dev/null)
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "❌ Failed to authenticate with Boundary"
    echo "Auth response: $AUTH_RESPONSE"
    exit 1
fi

echo "✅ Authenticated successfully!"
echo "🔑 Token: ${TOKEN:0:20}..."

# Get the default org scope
echo "📋 Getting organization scope..."
SCOPES_RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/scopes")
ORG_SCOPE_ID=$(echo "$SCOPES_RESPONSE" | jq -r '.items[] | select(.type=="org") | .id' 2>/dev/null)

echo "📋 Org Scope ID: $ORG_SCOPE_ID"

if [ -z "$ORG_SCOPE_ID" ] || [ "$ORG_SCOPE_ID" = "null" ]; then
    echo "❌ Failed to get org scope ID"
    exit 1
fi

# Create or find project scope
echo "📁 Creating project scope..."
PROJECT_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/scopes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"scope_id\": \"$ORG_SCOPE_ID\", \"name\": \"demo-project\", \"description\": \"Demo project for SSH monitoring\", \"type\": \"project\"}")

PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.item.id' 2>/dev/null)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
    echo "⚠️ Project might already exist, searching..."
    EXISTING_PROJECTS=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/scopes?scope_id=$ORG_SCOPE_ID")
    PROJECT_ID=$(echo "$EXISTING_PROJECTS" | jq -r '.items[] | select(.name=="demo-project") | .id' 2>/dev/null)
    
    if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
        echo "❌ Failed to create or find project"
        echo "Project response: $PROJECT_RESPONSE"
        echo "Existing projects: $EXISTING_PROJECTS"
        exit 1
    fi
    echo "✅ Found existing project: $PROJECT_ID"
else
    echo "✅ Created new project: $PROJECT_ID"
fi

# Create or find SSH target
echo "🎯 Creating SSH target..."
TARGET_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/targets" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$PROJECT_ID\",
        \"name\": \"ssh-demo-target\", 
        \"description\": \"SSH target for demo\",
        \"type\": \"tcp\",
        \"attributes\": {
            \"default_port\": 2222
        },
        \"address\": \"host.docker.internal\"
    }")

TARGET_ID=$(echo "$TARGET_RESPONSE" | jq -r '.item.id' 2>/dev/null)
if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "null" ]; then
    echo "⚠️ Target might already exist, searching..."
    EXISTING_TARGETS=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/targets?scope_id=$PROJECT_ID")
    TARGET_ID=$(echo "$EXISTING_TARGETS" | jq -r '.items[] | select(.name=="ssh-demo-target") | .id' 2>/dev/null)
    
    if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "null" ]; then
        echo "❌ Failed to create or find target"
        echo "Target response: $TARGET_RESPONSE"
        echo "Existing targets: $EXISTING_TARGETS"
        exit 1
    fi
    echo "✅ Found existing target: $TARGET_ID"
else
    echo "✅ Created new target: $TARGET_ID"
fi

echo ""
echo "🎉 BOUNDARY AUTO-CONFIGURATION COMPLETE!"
echo "================================================"
echo "🎯 TARGET_ID=$TARGET_ID"
echo "🔗 BOUNDARY_ADDR=$BOUNDARY_ADDR"  
echo "📁 PROJECT_ID=$PROJECT_ID"
echo "🔑 AUTH_METHOD_ID=$AUTH_METHOD_ID"
echo "================================================"
echo ""
echo "🚀 Connect with:"
echo "   boundary connect ssh -target-id $TARGET_ID -username ubuntu"
echo ""
echo "💡 Set environment:"
echo "   export TARGET_ID=$TARGET_ID"
echo "   export BOUNDARY_ADDR=http://127.0.0.1:9200"
echo ""
echo "🔑 Authenticate first:"
echo "   boundary authenticate password -auth-method-id $AUTH_METHOD_ID -login-name admin -password password"
echo ""

# Keep running so logs are visible
echo "✅ Configuration complete! Container will exit in 10 seconds..."
sleep 10

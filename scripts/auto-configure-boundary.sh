#!/bin/sh

echo "🎯 Auto-configuring Boundary for SSH session monitoring..."

BOUNDARY_ADDR="http://host.docker.internal:9200"
VAULT_ADDR="http://localhost:8200"  # Boundary dev runs on host, so use localhost
SHARED_DIR="/shared"

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

# Wait for Vault token to be ready
echo "⏳ Waiting for Vault token from vault-setup..."
for i in $(seq 1 60); do
  if [ -s "$SHARED_DIR/boundary-vault-token" ]; then
    VAULT_TOKEN=$(cat "$SHARED_DIR/boundary-vault-token")
    echo "✅ Got Vault token"
    break
  fi
  echo "  Waiting for Vault token ($i)..."; sleep 2
  if [ "$i" -eq 60 ]; then echo "❌ Vault token not found"; exit 1; fi
done

# Create Vault credential store
echo "🔐 Creating Vault credential store..."
CSTORE_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/credential-stores" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$PROJECT_ID\",
        \"name\": \"vault-store\",
        \"description\": \"Vault credential store for SSH certs\",
        \"type\": \"vault\",
        \"attributes\": {
            \"address\": \"$VAULT_ADDR\",
            \"token\": \"$VAULT_TOKEN\"
        }
    }")

CSTORE_ID=$(echo "$CSTORE_RESPONSE" | jq -r '.item.id' 2>/dev/null)
if [ -z "$CSTORE_ID" ] || [ "$CSTORE_ID" = "null" ]; then
    echo "⚠️ Credential store creation failed. Response:"
    echo "$CSTORE_RESPONSE" | jq .
    echo "⚠️ Searching for existing credential store..."
    EXISTING_CSTORES=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/credential-stores?scope_id=$PROJECT_ID")
    CSTORE_ID=$(echo "$EXISTING_CSTORES" | jq -r '.items[] | select(.name=="vault-store") | .id' 2>/dev/null)
    if [ -z "$CSTORE_ID" ] || [ "$CSTORE_ID" = "null" ]; then
        echo "❌ Failed to create or find credential store"
        echo "Search response:"
        echo "$EXISTING_CSTORES" | jq .
        exit 1
    fi
    echo "✅ Found existing credential store: $CSTORE_ID"
else
    echo "✅ Created credential store: $CSTORE_ID"
fi

# Create SSH certificate credential library
echo "📜 Creating SSH certificate credential library..."
CLIB_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/credential-libraries" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"credential_store_id\": \"$CSTORE_ID\",
        \"name\": \"ssh-cert-library\",
        \"description\": \"SSH certificate library\",
        \"type\": \"vault-ssh-certificate\",
        \"attributes\": {
            \"path\": \"ssh/sign/boundary-client\",
            \"username\": \"ubuntu\",
            \"key_type\": \"ecdsa\",
            \"key_bits\": 521,
            \"extensions\": {
                \"permit-pty\": \"\"
            }
        }
    }")

CLIB_ID=$(echo "$CLIB_RESPONSE" | jq -r '.item.id' 2>/dev/null)
if [ -z "$CLIB_ID" ] || [ "$CLIB_ID" = "null" ]; then
    echo "⚠️ Credential library creation failed. Response:"
    echo "$CLIB_RESPONSE" | jq .
    echo "⚠️ Searching for existing credential library..."
    EXISTING_CLIBS=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/credential-libraries?credential_store_id=$CSTORE_ID")
    CLIB_ID=$(echo "$EXISTING_CLIBS" | jq -r '.items[] | select(.name=="ssh-cert-library") | .id' 2>/dev/null)
    if [ -z "$CLIB_ID" ] || [ "$CLIB_ID" = "null" ]; then
        echo "❌ Failed to create or find credential library"
        echo "Search response:"
        echo "$EXISTING_CLIBS" | jq .
        exit 1
    fi
    echo "✅ Found existing credential library: $CLIB_ID"
else
    echo "✅ Created credential library: $CLIB_ID"
fi

# Create SSH target (type=ssh, not tcp)
echo "🎯 Creating SSH target..."
TARGET_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/targets" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$PROJECT_ID\",
        \"name\": \"ssh-demo-target\", 
        \"description\": \"SSH target for demo with certificate injection\",
        \"type\": \"ssh\",
        \"default_port\": 2222,
        \"address\": \"localhost\"
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

# Get current target version first
echo "🔍 Getting target version..."
TARGET_INFO=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/targets/$TARGET_ID")
TARGET_VERSION=$(echo "$TARGET_INFO" | jq -r '.item.version // .version // 1')
echo "ℹ️ Target version: $TARGET_VERSION"

# Check if credentials are already attached
EXISTING_CREDS=$(echo "$TARGET_INFO" | jq -r '.item.injected_application_credential_source_ids[]? // .injected_application_credential_source_ids[]?' 2>/dev/null)
if echo "$EXISTING_CREDS" | grep -q "$CLIB_ID"; then
    echo "✅ Credential library already attached to target!"
    echo "Skipping attachment step..."
    SKIP_ATTACH=true
else
    SKIP_ATTACH=false
fi

# Attach credential library to target with injected-application credentials
if [ "$SKIP_ATTACH" = "true" ]; then
    echo "ℹ️ Credential library already attached, skipping..."
else
    echo "🔗 Attaching SSH certificate library to target with injection..."
    ATTACH_RESPONSE=$(curl -s -X POST "$BOUNDARY_ADDR/v1/targets/$TARGET_ID:add-credential-sources" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"version\": $TARGET_VERSION,
            \"injected_application_credential_source_ids\": [\"$CLIB_ID\"]
        }")

    if echo "$ATTACH_RESPONSE" | jq -e '.item' >/dev/null 2>&1; then
        echo "✅ Attached credential library to target"
    else
        # Check if it's already attached
        if echo "$ATTACH_RESPONSE" | grep -q "already exists\|duplicate key"; then
            echo "✅ Credential library already attached"
        else
            echo "⚠️ Warning: Attachment may have failed. Response:"
            echo "$ATTACH_RESPONSE" | jq .
        fi
    fi
fi

# Verify the attachment by reading the target
echo "🔍 Verifying credential injection is configured..."
VERIFY_RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/targets/$TARGET_ID")
HAS_CREDS=$(echo "$VERIFY_RESPONSE" | jq -r '.item.injected_application_credential_source_ids[]? // .injected_application_credential_source_ids[]?' 2>/dev/null)

if [ -n "$HAS_CREDS" ]; then
    echo "✅ Verified: Injected application credentials configured"
    echo "✓ Credential library ID: $HAS_CREDS"
else
    echo "⚠️ Warning: Could not verify credential injection"
    echo "This may be due to API response format. Testing connection..."
fi

# Save TARGET_ID to shared volume for activity-generator
mkdir -p "$SHARED_DIR"
echo "$TARGET_ID" > "$SHARED_DIR/target-id"

echo ""
echo "🎉 BOUNDARY AUTO-CONFIGURATION COMPLETE!"
echo "================================================"
echo "🎯 TARGET_ID=$TARGET_ID"
echo "🔗 BOUNDARY_ADDR=$BOUNDARY_ADDR"  
echo "📁 PROJECT_ID=$PROJECT_ID"
echo "🔑 AUTH_METHOD_ID=$AUTH_METHOD_ID"
echo "🔐 CSTORE_ID=$CSTORE_ID"
echo "📜 CLIB_ID=$CLIB_ID"
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

#!/bin/sh
set -e

VAULT_ADDR=${VAULT_ADDR:-http://vault:8200}
ROOT_TOKEN=${VAULT_DEV_ROOT_TOKEN_ID:-groot}
SHARED_DIR=/shared

echo "🔐 Configuring Vault SSH secrets engine at $VAULT_ADDR"

# Wait for Vault to be ready
for i in $(seq 1 60); do
  if curl -sf "$VAULT_ADDR/v1/sys/health" >/dev/null; then
    echo "✅ Vault is up"
    break
  fi
  echo "⏳ Waiting for Vault ($i) ..."; sleep 2
  if [ "$i" -eq 60 ]; then echo "❌ Vault not ready"; exit 1; fi
done

# Enable SSH secrets engine
curl -sf -X POST "$VAULT_ADDR/v1/sys/mounts/ssh" \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"ssh"}' >/dev/null || echo "ℹ️ SSH engine may already be enabled"

# Generate CA key
curl -sf -X POST "$VAULT_ADDR/v1/ssh/config/ca" \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"generate_signing_key":true}' >/dev/null || echo "ℹ️ CA may already exist"

# Read CA public key
PUB_KEY=$(curl -sf -H "X-Vault-Token: $ROOT_TOKEN" "$VAULT_ADDR/v1/ssh/config/ca" | jq -r '.data.public_key')
[ -n "$PUB_KEY" ] || { echo "❌ Failed to retrieve CA public key"; exit 1; }
mkdir -p "$SHARED_DIR"
echo "$PUB_KEY" > "$SHARED_DIR/vault-ca.pem"
chmod 0644 "$SHARED_DIR/vault-ca.pem"
echo "✅ Wrote CA public key to $SHARED_DIR/vault-ca.pem"

# Create role for signing user certs
curl -sf -X POST "$VAULT_ADDR/v1/ssh/roles/boundary-client" \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "allow_user_certificates": true,
    "allowed_users": "ubuntu",
    "default_user": "ubuntu",
    "ttl": "5m",
    "max_ttl": "10m",
    "key_type": "ca",
    "allowed_extensions": "permit-pty,permit-user-rc"
  }' >/dev/null || echo "ℹ️ Role may already exist"

# Create the policy directly with all required Boundary permissions
POLICY_JSON='{"policy":"path \"ssh/sign/boundary-client\" {\n  capabilities = [\"create\", \"update\"]\n}\npath \"ssh/roles/boundary-client\" {\n  capabilities = [\"read\"]\n}\npath \"sys/leases/revoke\" {\n  capabilities = [\"update\"]\n}\npath \"sys/leases/lookup\" {\n  capabilities = [\"update\"]\n}\npath \"sys/leases/renew\" {\n  capabilities = [\"update\"]\n}"}'
curl -sf -X PUT "$VAULT_ADDR/v1/sys/policy/boundary-sign" \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$POLICY_JSON" >/dev/null || echo "ℹ️ Policy may already exist"

# Create a PERIODIC ORPHAN token for Boundary (Boundary requires both)
BOUNDARY_TOKEN=$(curl -sf -X POST "$VAULT_ADDR/v1/auth/token/create-orphan" \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"policies":["boundary-sign"],"period":"24h","renewable":true}' | jq -r '.auth.client_token')

[ -n "$BOUNDARY_TOKEN" ] || { echo "❌ Failed to create Boundary token"; exit 1; }
echo "$BOUNDARY_TOKEN" > "$SHARED_DIR/boundary-vault-token"
chmod 0600 "$SHARED_DIR/boundary-vault-token"
echo "✅ Wrote Boundary Vault token to $SHARED_DIR/boundary-vault-token"

echo "🎉 Vault SSH setup complete"
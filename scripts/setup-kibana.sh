#!/bin/sh

echo "🔥 Setting up Kibana with badass security columns..."

# Wait for Kibana to be completely ready
until curl -s http://kibana:5601/api/status | grep -q '"level":"available"'; do
  echo "Waiting for Kibana..."
  sleep 10
done

echo "Creating data view for auditbeat-*..."
# Create data view and capture response
AB_DATAVIEW_RESPONSE=$(curl -s -X POST "kibana:5601/api/data_views/data_view" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"data_view":{"title":"auditbeat-*","timeFieldName":"@timestamp"}}')

echo "Auditbeat data view response: $AB_DATAVIEW_RESPONSE"

# Get the auditbeat data view ID - try both new and existing
AB_DATAVIEW_ID=$(echo "$AB_DATAVIEW_RESPONSE" | jq -r '.data_view.id // empty')

if [ -z "$AB_DATAVIEW_ID" ]; then
  echo "Getting existing auditbeat data view ID..."
  EXISTING_RESPONSE=$(curl -s "kibana:5601/api/data_views/data_view" -H "kbn-xsrf: true")
  AB_DATAVIEW_ID=$(echo "$EXISTING_RESPONSE" | jq -r '.data_views[] | select(.title=="auditbeat-*") | .id' 2>/dev/null || echo "")
fi

if [ -z "$AB_DATAVIEW_ID" ]; then
  echo "❌ Failed to determine data view ID for auditbeat-*"
  exit 1
fi

echo "Using auditbeat data view ID: $AB_DATAVIEW_ID"

# Create data view for sshd-logs-* (Filebeat index)
echo "Creating data view for sshd-logs-*..."
SSHD_DATAVIEW_RESPONSE=$(curl -s -X POST "kibana:5601/api/data_views/data_view" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"data_view":{"title":"sshd-logs-*","timeFieldName":"@timestamp"}}')

echo "SSHD data view response: $SSHD_DATAVIEW_RESPONSE"

SSHD_DATAVIEW_ID=$(echo "$SSHD_DATAVIEW_RESPONSE" | jq -r '.data_view.id // empty')
if [ -z "$SSHD_DATAVIEW_ID" ]; then
  echo "Getting existing sshd-logs data view ID..."
  EXISTING_SSHD_RESPONSE=$(curl -s "kibana:5601/api/data_views/data_view" -H "kbn-xsrf: true")
  SSHD_DATAVIEW_ID=$(echo "$EXISTING_SSHD_RESPONSE" | jq -r '.data_views[] | select(.title=="sshd-logs-*") | .id' 2>/dev/null || echo "")
fi

if [ -z "$SSHD_DATAVIEW_ID" ]; then
  echo "⚠️  Could not determine data view ID for sshd-logs-* (Filebeat). Continuing without SSHD saved search."
fi

# Create the primary saved search for auditbeat events
cat > /tmp/saved_search_auditbeat.json << SEARCHJSON_AB
{
  "attributes": {
    "title": "🔍 Security Audit Events",
    "description": "Security monitoring with key auditd and system fields",
    "columns": ["@timestamp", "event.action", "user.name", "process.name", "process.args", "file.path", "host.hostname", "auditd.data.key"],
    "sort": [["@timestamp", "desc"]],
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"version\":true,\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  },
  "references": [
    {
      "name": "kibanaSavedObjectMeta.searchSourceJSON.index",
      "type": "index-pattern", 
      "id": "$AB_DATAVIEW_ID"
    }
  ]
}
SEARCHJSON_AB

echo "Creating saved search '🔍 Security Audit Events'..."
curl -s -X POST "kibana:5601/api/saved_objects/search" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d @/tmp/saved_search_auditbeat.json

# Saved search: execve syscalls by ubuntu (auditd)
cat > /tmp/saved_search_execve_ubuntu.json << SEARCHJSON_EXEC
{
  "attributes": {
    "title": "🔑 SSH execve by ubuntu (auditd)",
    "description": "All execve syscalls attributed to ubuntu from auditd events.",
    "columns": ["@timestamp", "user.name", "auditd.data.syscall", "process.executable", "process.args", "host.hostname"],
    "sort": [["@timestamp", "desc"]],
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"version\":true,\"query\":{\"query\":\"auditd.data.syscall: execve and user.name: \\\"ubuntu\\\"\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  },
  "references": [
    {
      "name": "kibanaSavedObjectMeta.searchSourceJSON.index",
      "type": "index-pattern",
      "id": "$AB_DATAVIEW_ID"
    }
  ]
}
SEARCHJSON_EXEC

echo "Creating saved search '🔑 SSH execve by ubuntu (auditd)'..."
curl -s -X POST "kibana:5601/api/saved_objects/search" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d @/tmp/saved_search_execve_ubuntu.json

# Saved search: SSH cert logins from Boundary (if sshd-logs view exists)
if [ -n "$SSHD_DATAVIEW_ID" ]; then
  cat > /tmp/saved_search_sshd_boundary.json << SEARCHJSON_SSHD
{
  "attributes": {
    "title": "🔐 SSH cert logins from Boundary (sshd)",
    "description": "SSHD log entries where Vault-signed certificates are used (vault-token IDs).",
    "columns": ["@timestamp", "message", "ssh.user", "ssh.client_ip", "ssh.vault_token_id", "ssh.vault_serial"],
    "sort": [["@timestamp", "desc"]],
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"version\":true,\"query\":{\"query\":\"ssh.vault_token_id:*\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  },
  "references": [
    {
      "name": "kibanaSavedObjectMeta.searchSourceJSON.index",
      "type": "index-pattern",
      "id": "$SSHD_DATAVIEW_ID"
    }
  ]
}
SEARCHJSON_SSHD

  echo "Creating saved search '🔐 SSH cert logins from Boundary (sshd)'..."
  curl -s -X POST "kibana:5601/api/saved_objects/search" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d @/tmp/saved_search_sshd_boundary.json
fi

echo ""
echo "✅ BOOM! Security monitoring is ready!"
echo "🎯 Go to http://localhost:5601"
echo "🔍 Click Discover -> Open -> '🔍 Security Audit Events'"
echo "📊 Watch the security events roll in with all the juicy details!"

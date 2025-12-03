#!/bin/sh

echo "🔥 Setting up Kibana with badass security columns..."

# Wait for Kibana to be completely ready
until curl -s http://kibana:5601/api/status | grep -q '"level":"available"'; do
  echo "Waiting for Kibana..."
  sleep 10
done

echo "Creating data view..."
# Create data view and capture response
DATAVIEW_RESPONSE=$(curl -s -X POST "kibana:5601/api/data_views/data_view" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"data_view":{"title":"auditbeat-*","timeFieldName":"@timestamp"}}')

echo "Data view response: $DATAVIEW_RESPONSE"

# Get the data view ID - try both new and existing
DATAVIEW_ID=$(echo "$DATAVIEW_RESPONSE" | jq -r '.data_view.id // empty')

if [ -z "$DATAVIEW_ID" ]; then
  echo "Getting existing data view ID..."
  DATAVIEW_ID=$(curl -s "kibana:5601/api/data_views" -H "kbn-xsrf: true" | jq -r '.data_view[] | select(.title=="auditbeat-*") | .id')
fi

echo "Using data view ID: $DATAVIEW_ID"

# Create the saved search JSON using a heredoc to avoid escaping hell
cat > /tmp/saved_search.json << SEARCHJSON
{
  "attributes": {
    "title": "🔍 Security Audit Events",
    "description": "Badass security monitoring with all the important shit",
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
      "id": "$DATAVIEW_ID"
    }
  ]
}
SEARCHJSON

echo "Creating saved search with important columns..."
curl -s -X POST "kibana:5601/api/saved_objects/search" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d @/tmp/saved_search.json

echo ""
echo "✅ BOOM! Security monitoring is ready!"
echo "🎯 Go to http://localhost:5601"
echo "🔍 Click Discover -> Open -> '🔍 Security Audit Events'"
echo "📊 Watch the security events roll in with all the juicy details!"

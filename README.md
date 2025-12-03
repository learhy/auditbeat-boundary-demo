
# Auditbeat Boundary Demo Environment

A complete demo environment showing how Auditbeat can provide excellent detailed session audit logging for Boundary targets

## Quick Start


1. **Prerequisites**: Install Docker and Docker Compose

2. **Clone and start**:
```bash
git clone <this-repo>
cd auditbeat-boundary-demo
docker-compose up -d
```

3. **Wait for initial setup (about 3-4 minutes)**:

```bash
# Check status
docker-compose ps
# Watch setup progress
docker-compose logs -f demo-activity-generator
```

4. **Access Kibana**: 

Open [`http://localhost:5601`](http://localhost:5601)

5. Generate additional demo activity (optional):
```bash
# Run all scenarios again
docker-compose exec demo-activity-generator /scripts/activity-generator.sh 5

# Or run specific scenarios
docker-compose exec demo-activity-generator /scripts/activity-generator.sh 1  # Normal activity
docker-compose exec demo-activity-generator /scripts/activity-generator.sh 2  # Privilege escalation  
docker-compose exec demo-activity-generator /scripts/activity-generator.sh 3  # Suspicious file access
docker-compose exec demo-activity-generator /scripts/activity-generator.sh 4  # Network reconnaissance
```

## What's Included

- Elasticsearch: Stores audit events
- Kibana: Visualizes and searches audit data
- Auditbeat: Collects system audit events
- Demo App: Generates realistic user activity
- Auto-setup: Pre-configured index patterns and dashboards

## Demo Scenarios

The activity generator includes:

1. Normal Activity: Basic file operations and commands
2. Privilege Escalation: sudo attempts, su commands
3. Suspicious File Access: Reading sensitive files, copying system files
4. Network Activity: Port scanning, external connections

## Viewing Results

1. Open Kibana at [`http://localhost:5601`](http://localhost:5601)
2. Choose one of these options:

### Option A: Pre-configured Saved Search (Recommended)
- Go to **Discover**
- Click **Open** in the top menu
- Select **"Boundary Audit Events"**
- This view is pre-configured with the key correlation columns

### Option B: Dashboard View
- Go to **Dashboard**
- Open **"Boundary Audit Dashboard"**
- View audit events in a dashboard layout

### Option C: Manual Discovery
- Go to **Discover**
- Select `auditbeat-*` index pattern
- Manually add columns for the key fields listed below

## Key Fields for Boundary Correlation

The pre-configured views include these important fields:

- `@timestamp` - When the event occurred
- `event.action` - What action was performed  
- `process.title` - Which process executed
- `auditd.data.tty` - Terminal session info
- `auditd.session` - Session tracking ID
- `auditd.summary.actor.primary` - Primary user
- `auditd.summary.actor.secondary` - Secondary user (for privilege escalation)

## Cleanup

docker-compose down -v

## Production Considerations

- This demo runs Auditbeat in containers for simplicity and is not meant for product use whatsoever
- Production deployments should run Auditbeat directly on target systems
- Consider the Elastic License 2.0 restrictions for managed service scenarios
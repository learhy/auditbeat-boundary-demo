# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a demo environment showcasing Auditbeat's audit logging capabilities for HashiCorp Boundary targets. The entire stack runs in Docker containers via Docker Compose, creating a fully self-contained demonstration of security event monitoring with Elasticsearch, Kibana, and Auditbeat.

## Architecture

### Container Stack
- **elasticsearch**: Data store for all audit events (Elastic 8.11.0)
- **kibana**: Web UI for visualizing and searching audit data (port 5601)
- **auditbeat**: Collects system-level audit events with kernel auditd rules
- **activity-generator**: Ubuntu container that simulates realistic user activity (normal operations and suspicious behavior)
- **kibana-setup**: One-shot Alpine container that waits for Kibana to be ready, then creates data views and saved searches via API

### Key Configuration Files
- `docker-compose.yml`: Orchestrates all services, sets up volumes, networking, and dependencies
- `config/auditbeat.yml`: Configures three modules (auditd with custom rules, file_integrity, system monitoring) plus Elasticsearch output
- `config/kibana.yml`: Basic Kibana server configuration
- `scripts/activity-generator.sh`: Bash script with 5 scenarios (normal activity, privilege escalation, suspicious file access, network recon, all-in-one)
- `scripts/setup-kibana.sh`: Shell script that uses Kibana REST API to create data views and saved searches with security-focused columns

### Audit Rules
The auditbeat.yml defines custom auditd rules monitoring:
- File access to sensitive paths (`/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, `/root`, `/tmp`)
- Process execution via `execve` syscalls (both 32-bit and 64-bit architectures)
- Privilege escalation attempts via `sudo` and `su` commands

## Common Commands

### Starting/Stopping
```bash
# Start entire stack (initial setup takes 3-4 minutes)
docker-compose up -d

# Stop all containers
docker-compose down

# Stop and remove all data
docker-compose down -v
```

### Monitoring
```bash
# Check all container status
docker-compose ps

# Watch activity generator logs
docker-compose logs -f activity-generator

# Watch auditbeat logs
docker-compose logs -f auditbeat

# Watch Kibana setup logs
docker-compose logs -f kibana-setup
```

### Generating Demo Activity
```bash
# Run all scenarios (default)
docker-compose exec activity-generator /scripts/activity-generator.sh

# Run specific scenarios
docker-compose exec activity-generator /scripts/activity-generator.sh 1  # Normal activity
docker-compose exec activity-generator /scripts/activity-generator.sh 2  # Privilege escalation
docker-compose exec activity-generator /scripts/activity-generator.sh 3  # Suspicious file access
docker-compose exec activity-generator /scripts/activity-generator.sh 4  # Network reconnaissance
docker-compose exec activity-generator /scripts/activity-generator.sh 5  # All scenarios with delays
```

### Debugging
```bash
# Access running containers
docker-compose exec activity-generator bash
docker-compose exec auditbeat bash

# Check Elasticsearch health
curl http://localhost:9200/_cluster/health

# Check Kibana status
curl http://localhost:5601/api/status

# View activity logs inside container
docker-compose exec activity-generator cat /tmp/audit-demo/boundary-activity.log
```

## Development Workflow

### Modifying Auditbeat Rules
1. Edit `config/auditbeat.yml` with new audit rules in the `audit_rules` section
2. Restart auditbeat: `docker-compose restart auditbeat`
3. Verify rules loaded: `docker-compose logs auditbeat | grep -i "audit rule"`

### Modifying Activity Scenarios
1. Edit `scripts/activity-generator.sh` to add/modify scenarios in the `generate_activity()` function
2. Test specific scenario: `docker-compose exec activity-generator /scripts/activity-generator.sh <scenario_num>`
3. The main container loop runs every 30 seconds automatically

### Modifying Kibana Setup
1. Edit `scripts/setup-kibana.sh` to change data view columns, saved searches, or dashboards
2. Destroy and recreate to re-run setup: `docker-compose down -v && docker-compose up -d`
3. Or manually delete Kibana saved objects and re-run: `docker-compose restart kibana-setup`

### Testing Changes
- After configuration changes, always check logs: `docker-compose logs -f <service-name>`
- Verify data flow: Elasticsearch → Kibana (Discover → auditbeat-* index pattern)
- Test with fresh state: `docker-compose down -v && docker-compose up -d` to clear all data

## Important Notes

### Security Considerations
- This demo disables Elasticsearch security (`xpack.security.enabled=false`) for simplicity
- Auditbeat runs with privileged capabilities (`AUDIT_CONTROL`, `AUDIT_READ`) and `pid: host` mode
- Never use this configuration in production

### Data Persistence
- Elasticsearch data persists in named volume `esdata`
- Activity logs are written to `/tmp/audit-demo/` inside the activity-generator container
- Use `docker-compose down -v` to clear all persisted data

### Kibana Access
- Web UI available at http://localhost:5601 after ~3-4 minute initialization
- Pre-configured saved search: "🔍 Security Audit Events" includes key audit columns
- Columns configured: `@timestamp`, `event.action`, `user.name`, `process.name`, `process.args`, `file.path`, `host.hostname`, `auditd.data.key`

### Activity Generator Behavior
- Runs continuously in loop, executing all scenarios every 30 seconds by default
- Writes structured JSON logs to `/tmp/audit-demo/boundary-activity.log`
- Actual syscalls trigger real auditd events captured by Auditbeat
- JSON logs are for additional correlation but not sent to Elasticsearch directly

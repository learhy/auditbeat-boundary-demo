
# Auditbeat Boundary Demo Environment

A complete demo environment showing how Auditbeat can provide detailed session audit logging that is complimentary to Boundary Session Recording. This demo integrates **HashiCorp Boundary Enterprise** to demonstrate how session metadata (session IDs, user IDs, target IDs) can be automatically injected into SSH sessions via Vault-signed certificates and correlated with audit events.

**⚠️ Requires Boundary Enterprise License** - SSH certificate injection with session metadata requires Boundary Enterprise. Open-source Boundary does not support this feature.

## Quick Start

1. **Prerequisites**: 
   - Install Docker and Docker Compose
   - Install HashiCorp Boundary CLI: `brew install hashicorp/tap/boundary` (macOS) or [download from HashiCorp](https://developer.hashicorp.com/boundary/downloads)
   - **Boundary Enterprise License** (required for SSH certificate injection)

2. **Clone the repository**:
   ```bash
   git clone git@github.com:learhy/auditbeat-boundary-demo.git
   cd auditbeat-boundary-demo
   ```

3. **Add Your Enterprise License**:

   Place your `boundary-license.hclic` file in the project root directory:
   ```bash
   # Copy your license file into the repo
   cp /path/to/your/boundary-license.hclic .
   ```
   
   The license is already in `.gitignore` to prevent accidental commits.

4. **Start Boundary Enterprise Dev Mode**:

   In a **separate terminal window**, start Boundary in development mode with your enterprise license:
   ```bash
   ./start-boundary-enterprise.sh
   ```
   
   Or manually:
   ```bash
   export BOUNDARY_LICENSE="$(cat boundary-license.hclic)"
   boundary dev
   ```
   
   **Keep this terminal running!** The demo containers will connect to Boundary at `http://localhost:9200`.
   
   Enterprise development mode provides:
   - Pre-configured admin user (login: `admin`, password: `password`)
   - API endpoint on port 9200
   - **SSH target type** with credential injection
   - **Vault SSH certificate injection** with session metadata
   - No persistent storage (resets on restart)

5. **Start the demo containers**:
   ```bash
   docker-compose up -d
   ```

6. **Wait for initial setup (about 3-4 minutes)**:

   The Kibana instance takes a few minutes to configure. If you access Kibana before it's configured, the data won't pop out at you. 

   ```bash
   # Check status
   docker-compose ps
   
   # Watch Boundary configuration
   docker-compose logs -f boundary-setup
   
   # Watch session generation
   docker-compose logs -f activity-generator
   ```

7. **Access Kibana**:

Open [`http://localhost:5601`](http://localhost:5601)

8. **(Optional) Manually connect via Boundary**:

   After auto-configuration completes, you can manually connect to the SSH target through Boundary with automatic certificate injection:
   
   ```bash
   # Authenticate with Boundary
   boundary authenticate password -auth-method-id ampw_1234567890 -login-name admin -password password
   
   # Get the target ID from setup logs
   docker-compose logs boundary-setup | grep TARGET_ID
   
   # Connect through Boundary with SSH certificate injection
   # No password required - Vault-signed certificate is automatically injected!
   boundary connect ssh -target-id <TARGET_ID> -username ubuntu
   ```
   
   **What's happening:**
   - Boundary requests a signed SSH certificate from Vault
   - The certificate includes session metadata (session_id, user_id) in principals
   - Certificate is automatically injected into the SSH session
   - Target's SSH daemon validates the certificate against Vault's CA
   - Session metadata flows through to audit logs captured by Auditbeat

## What's Included

- **Elasticsearch**: Stores audit events
- **Kibana**: Visualizes and searches audit data  
- **Auditbeat**: Collects system audit events using kernel auditd rules
- **Boundary Integration**: Generates SSH sessions through Boundary with metadata tracking
  - Auto-configures Boundary with SSH targets
  - Creates sessions every 45 seconds with unique session IDs
  - Logs session metadata for correlation with audit events
- **SSH Target**: Ubuntu container with OpenSSH server for demonstration
- **Activity Generator**: Simulates user activity and Boundary sessions
- **Auto-setup**: Pre-configured index patterns and saved searches

## How Boundary Integration Works

This demo showcases how Boundary session metadata can be correlated with audit events:

1. **Session Creation**: The `generate-boundary-sessions.sh` script authenticates with Boundary and creates authorized sessions
2. **Metadata Capture**: Each session includes:
   - `boundary.session_id`: Unique Boundary session identifier
   - `boundary.user_id`: Boundary user who initiated the session
   - `boundary.target_id`: Target system being accessed
3. **Activity Logging**: Simulated activities during sessions are logged with full Boundary context
4. **Correlation**: Security analysts can track all actions back to specific Boundary sessions and users

## Simulated Session Activities

The Boundary session generator simulates these activities:

1. **Normal File Access**: Reading common configuration files (`/etc/hosts`)
2. **Config File Reads**: Accessing SSH configuration (`/etc/ssh/sshd_config`)
3. **Privilege Escalation**: Attempting sudo operations
4. **Sensitive File Access**: Reading password files (`/etc/passwd`)
5. **Process Listing**: Enumerating running processes

## Viewing Results

1. Open Kibana at [`http://localhost:5601`](http://localhost:5601)
2. Navigate to **Discover**
3. Select the `auditbeat-*` index pattern
4. You should see audit events from the activity generator

**Note**: The current demo generates structured JSON logs with Boundary session metadata. In a production environment:
- Auditbeat would capture actual SSH session events from the kernel audit subsystem
- SSH certificates from Boundary would include session metadata in certificate principals
- This metadata would flow through to auditd logs and be indexed by Auditbeat

### Viewing Session Logs

To see the Boundary session activity logs directly:
```bash
# View recent session logs
docker-compose exec activity-generator cat /tmp/audit-demo/boundary-activity.log | tail -20

# Watch live session activity
docker-compose logs -f activity-generator
```

## Key Fields for Boundary Correlation

The session logs include these important fields for correlation:

- `@timestamp` - When the event occurred
- `event.action` - What action was performed
- `boundary.session_id` - Unique Boundary session identifier  
- `boundary.user_id` - Boundary user who initiated the session
- `boundary.target_id` - Target system being accessed
- `user.name` - Username on the target system
- `process.name` - Process that executed the action
- `process.args` - Command line arguments
- `file.path` - File path that was accessed

In production with full Boundary + Auditbeat integration, you would also see:
- `auditd.session` - Kernel session tracking ID  
- `auditd.data.tty` - Terminal session info
- `auditd.summary.actor.primary` - Primary user
- `auditd.summary.actor.secondary` - Secondary user (for privilege escalation)

## Cleanup

```bash
# Stop and remove containers
docker-compose down -v

# Stop Boundary dev mode (Ctrl+C in the terminal where it's running)
```

## Production Considerations

- This demo runs Auditbeat in containers for simplicity and is **not meant for production use**
- This demo uses `boundary dev` mode which is **only for development/testing**
- Production deployments should:
  - Run Auditbeat directly on target systems (not in containers)
  - Use production Boundary clusters with proper HA configuration
  - Configure Boundary with Vault for SSH certificate injection
  - Enable session recording in Boundary for complete audit trails
  - Set up proper authentication (OIDC, LDAP) instead of password auth
  - Use proper certificate authorities for SSH certificate signing
- The session metadata demonstrated here would be included in SSH certificates via Boundary's certificate injection feature
- Consider the Elastic License 2.0 restrictions for managed service scenarios

## Architecture Notes

**Current Demo Flow:**
1. User starts `boundary dev` on host machine (port 9200)
2. Docker containers start and `boundary-setup` container auto-configures Boundary
3. `activity-generator` container creates Boundary sessions via API every 45 seconds
4. Session metadata is logged to structured JSON files
5. Auditbeat collects system audit events (separate from Boundary session logs)

**Production Flow:**
1. Boundary cluster with workers deployed
2. Vault configured for SSH certificate injection
3. Users authenticate and connect via `boundary connect ssh`
4. Boundary injects SSH certificates with session metadata embedded
5. Target system's SSH daemon validates certificate
6. Auditbeat captures kernel audit events including SSH session metadata from certificates
7. All events are correlated in Elasticsearch by Boundary session ID

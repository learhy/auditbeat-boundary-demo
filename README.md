
# Auditbeat Boundary Demo Environment

A complete demo environment showing how Auditbeat can provide detailed session audit logging that is complimentary to Boundary Session Recording. This demo integrates **HashiCorp Boundary Enterprise** to demonstrate how identity metadata (project, user, target) can be injected into SSH sessions via Vault-signed certificates and correlated with audit events.

**⚠️ Requires Boundary Enterprise License** - SSH certificate injection with session metadata requires Boundary Enterprise. Open-source Boundary does not support this feature.

## Quick Start

1. **Prerequisites**: 
   - Install Docker and Docker Compose
   - **Boundary Enterprise License** (required for SSH certificate injection)
   - **Install Boundary Enterprise CLI** (not the standard OSS version):
   
   **On Windows (experimental / not fully tested):**
   - Install **WSL2** with Ubuntu (or another Linux distro)
   - Install **Docker Desktop for Windows** with the WSL2 backend enabled
   - Run all commands from the **WSL2 shell** (not PowerShell/CMD)
   - Install the **Linux Boundary Enterprise CLI (`+ent`)** inside WSL2 and ensure `boundary` is on the WSL2 `$PATH`
   - This configuration is expected to work but has **not been fully tested**; behavior may vary based on your Docker Desktop / WSL2 setup.
   
   **Option A: Download from HashiCorp** (Recommended)
   ```bash
   # For macOS Apple Silicon (M1/M2/M3)
   curl -O https://releases.hashicorp.com/boundary/0.19.3+ent/boundary_0.19.3+ent_darwin_arm64.zip
   unzip boundary_0.19.3+ent_darwin_arm64.zip
   sudo mv boundary /usr/local/bin/
   
   # For macOS Intel
   curl -O https://releases.hashicorp.com/boundary/0.19.3+ent/boundary_0.19.3+ent_darwin_amd64.zip
   unzip boundary_0.19.3+ent_darwin_amd64.zip
   sudo mv boundary /usr/local/bin/
   
   # Verify Enterprise version is installed
   boundary version  # Should show "0.19.3+ent"
   ```
   
   **Option B: Download from web**
   - Visit https://releases.hashicorp.com/boundary/
   - Download the **Enterprise version** (`+ent`) for your platform
   - Extract and move to `/usr/local/bin/`
   
   ⚠️ **Important**: The `+ent` suffix is required. The standard Homebrew version (`brew install boundary`) is open-source and does NOT support SSH certificate injection.

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

4. **Start the demo (Boundary + containers)**:

   The `auditbeat-demo.sh` script will start Boundary Enterprise dev mode **and** all Docker services for you.

   ```bash
   ./auditbeat-demo.sh start
   ```

   This will:
   - Verify the Boundary Enterprise CLI is installed and licensed
   - Start `boundary dev` with the correct worker settings
   - Start all Docker containers via `docker-compose up -d`
   - Auto-configure Boundary (targets, credential store, credential library)
   - Wait for a valid SSH target ID and print it to the console

5. **Wait for initial setup (about 3-4 minutes)**:

   The Kibana instance takes a few minutes to configure. If you access Kibana before it's configured, the data won't pop out at you. 

   ```bash
   # Check overall demo status (Boundary dev + containers)
   ./auditbeat-demo.sh status

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
   # Find the auth method ID from the boundary-setup logs (look for AUTH_METHOD_ID=...)
   AUTH_METHOD_ID=$(docker-compose logs boundary-setup | sed -n 's/.*AUTH_METHOD_ID=\([^ ]*\).*/\1/p' | tail -1)
   boundary authenticate password -auth-method-id "$AUTH_METHOD_ID" -login-name admin -password password
   
   # Get the target ID from setup logs
   TARGET_ID=$(docker-compose logs boundary-setup | sed -n 's/.*TARGET_ID=\([^ ]*\).*/\1/p' | tail -1)
   
   # Connect through Boundary with SSH certificate injection
   # No password required - Vault-signed certificate is automatically injected!
   boundary connect ssh -target-id "$TARGET_ID" -username ubuntu
   ```
   
   **What's happening:**
   - Boundary requests a signed SSH certificate from Vault
   - The certificate includes identity metadata in the key ID (Boundary project, user, and target)
   - The certificate is automatically injected into the SSH session
   - The target's SSH daemon validates the certificate against Vault's CA
   - Identity metadata flows through to SSH logs (and into Elasticsearch via Filebeat), where it can be correlated with Auditbeat events

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

This demo showcases how Boundary activity can be correlated with audit events:

1. **Session Creation**: The `generate-boundary-sessions.sh` script authenticates with Boundary and creates authorized SSH sessions through the configured target.
2. **Metadata Capture (session log)**: Each session is logged by the activity generator into `/tmp/audit-demo/boundary-activity.log` with structured fields, including:
   - `boundary.session_id`: Unique Boundary session identifier
   - `boundary.user_id`: Boundary user who initiated the session
   - `boundary.target_id`: Target system being accessed
3. **Activity Logging**: Simulated activities during sessions (e.g. `whoami`, `ps aux`, `cat /etc/passwd`) are executed on the SSH target.
4. **Correlation**: Security analysts can correlate:
   - SSHD logs and cert key IDs (Boundary project/user/target)
   - Auditbeat `auditd` events (execve/file access on the target)
   - Optional session JSON logs from the activity generator

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
4. You should see audit events from the activity generator and from the Linux host.

### Recommended saved searches

After the stack has initialized and Kibana is ready, open these saved searches in **Discover**:

- **`🔍 Security Audit Events`** (data view: `auditbeat-*`)
  - Broad view of security-relevant events, including host, process, and (where available) auditd fields.
- **`🔑 SSH execve by ubuntu (auditd)`** (data view: `auditbeat-*`)
  - KQL filter: `auditd.data.syscall: execve and user.name: "ubuntu"`
  - Shows the actual commands executed by the `ubuntu` user as seen by the kernel audit subsystem. Use this to validate that Boundary-driven SSH sessions generate the expected execve audit events.
- **`🔐 SSH cert logins from Boundary (sshd)`** (data view: `sshd-logs-*`)
  - KQL filter: `ssh.vault_token_id:*`
  - Shows SSHD log entries where Vault-signed certificates are used, including the Vault token ID and serial for each session.

By comparing timestamps and host/user fields across these saved searches, you can see:
- When a Boundary-driven SSH session is established (from SSHD logs / Vault token IDs).
- Which commands the `ubuntu` user actually ran on the target (from auditd execve events).

### How principals and key IDs are configured

This demo configures Boundary and Vault so SSH certificates carry useful identity information in the **key ID** that shows up in SSH logs:

- In `scripts/auto-configure-boundary.sh`, the Vault SSH certificate credential library is created with:
  - `type: "vault-ssh-certificate"`
  - `attributes.key_id = "boundary-user-{{ .User.Name }}"`
- In `scripts/setup-vault-ssh.sh`, the Vault SSH role `boundary-client` is configured with:
  - `allow_user_key_ids: true` so Vault respects the `key_id` supplied by Boundary
  - `key_id_format: "vault-token-{{token_display_name}}-role-{{role_name}}"` as a fallback for non-Boundary callers

At runtime this results in SSHD log lines like:

- `Accepted certificate ID "boundary-project-demo-project-user-admin-target-ssh-demo-target" (serial ...) signed by RSA CA ...`
- `Accepted publickey for ubuntu ... ID boundary-project-demo-project-user-admin-target-ssh-demo-target (serial ...) CA RSA ...`

This gives you stable, human-friendly identifiers for each SSH certificate, which you can see in:

- Raw `sshd.log` on the target
- The `sshd-logs-*` index in Elasticsearch via Filebeat (`ssh.vault_token_id` field), where it is further split into:
  - `boundary.project` → `demo-project`
  - `boundary.user` → Boundary username (e.g. `admin`)
  - `boundary.target` → `ssh-demo-target`

You can customize this further by editing the `key_id` string in `auto-configure-boundary.sh` (for example to include additional context) and adjusting the Filebeat dissect patterns in `config/filebeat.yml` so that any new pieces are parsed into separate fields.

**Note**: This demo uses Boundary Enterprise to inject SSH certificates signed by Vault and to proxy real SSH sessions to the `ssh-target` container. Auditbeat collects host and process activity on the target, while SSHD logs on the target show certificate-based authentication using Vault's CA and token IDs for each session. In a production deployment you would typically:
- Run Auditbeat directly on target systems with full auditd integration
- Configure Boundary/Vault (or HCP Boundary) so SSH certificates include richer metadata (for example, session or user attributes) in principals or certificate extensions
- Ingest SSH/auth logs (e.g. via Filebeat or an additional Beat) so certificate and session metadata appears directly in Elasticsearch events alongside Auditbeat data

### Viewing Session Logs

To see the Boundary session activity logs directly:
```bash
# View recent session logs
docker-compose exec activity-generator cat /tmp/audit-demo/boundary-activity.log | tail -20

# Watch live session activity
docker-compose logs -f activity-generator
```

## Key Fields for Boundary Correlation

The activity generator's structured session log (`/tmp/audit-demo/boundary-activity.log`) includes these important fields for correlation:

- `@timestamp` - When the event occurred
- `event.action` - What action was performed
- `boundary.session_id` - Unique Boundary session identifier  
- `boundary.user_id` - Boundary user who initiated the session
- `boundary.target_id` - Target system being accessed
- `user.name` - Username on the target system (as simulated by the generator)
- `process.name` - Logical name for the action or process
- `process.args` - Command line arguments (where applicable)
- `file.path` - File path that was accessed (where applicable)

In production with full Boundary + Auditbeat integration, you would also typically see additional auditd fields, for example:
- `auditd.session` - Kernel session tracking ID  
- `auditd.data.tty` - Terminal session info
- `auditd.summary.actor.primary` - Primary user
- `auditd.summary.actor.secondary` - Secondary user (for privilege escalation)

## Cleanup

```bash
# Stop Boundary dev and all demo containers
./auditbeat-demo.sh stop

# (Optional) Remove all Docker volumes/state
# docker-compose down -v
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
1. User runs `./auditbeat-demo.sh start` (which starts `boundary dev` and all Docker services)
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

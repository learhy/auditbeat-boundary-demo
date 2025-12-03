# Boundary Enterprise Features - Quick Reference

## What Changes With Enterprise License

### 1. SSH Target Type
**Open Source**: Only `tcp` targets available
**Enterprise**: `ssh` targets with native SSH support

```bash
# Target creation now uses type: "ssh"
boundary targets create ssh -scope-id <project> -name ssh-target
```

### 2. Credential Injection
**Open Source**: Only "brokered" credentials (Boundary provides creds, user manually enters them)
**Enterprise**: "injected-application" credentials (Boundary automatically injects certificates)

```bash
# Credential library can now be attached with injection
boundary targets add-credential-sources \
  -id <target-id> \
  -injected-application-credential-source <library-id>
```

### 3. SSH Certificate Injection with Session Metadata

**How It Works**:
1. User runs: `boundary connect ssh -target-id <id> -username ubuntu`
2. Boundary authenticates user and authorizes session
3. Boundary requests signed SSH certificate from Vault
4. Vault signs certificate with session metadata in principals:
   - `boundary-session-<session_id>`
   - `boundary-user-<user_id>`
   - `boundary-target-<target_id>`
5. Boundary injects certificate into SSH session (NO PASSWORD NEEDED!)
6. SSH daemon validates certificate against Vault CA
7. User is authenticated and connected
8. Session metadata flows to audit logs

### 4. Audit Log Correlation

With Enterprise + certificate injection, audit logs will show:
- Kernel audit events from auditd
- SSH authentication via certificate (not password)
- Certificate principals containing Boundary session metadata
- Ability to correlate all session activity back to specific Boundary sessions

## Testing SSH Certificate Injection

### Manual Test
```bash
# 1. Authenticate with Boundary
export BOUNDARY_PASSWORD=password
boundary authenticate password \
  -auth-method-id ampw_1234567890 \
  -login-name admin \
  -password env://BOUNDARY_PASSWORD \
  -keyring-type none

# 2. Get target ID
docker-compose logs boundary-setup | grep TARGET_ID

# 3. Connect via Boundary (certificate is auto-injected!)
boundary connect ssh -target-id <TARGET_ID> -username ubuntu

# No password prompt! Certificate authentication happens automatically.
```

### What You Should See

**In Boundary logs**:
- Session authorization successful
- Credential library retrieved
- Vault credential requested
- SSH certificate signed

**In SSH target logs**:
- Certificate-based authentication
- No password authentication attempts
- User authenticated via certificate

**In Auditbeat/Elasticsearch**:
- SSH session start events
- Certificate validation events
- Process execution events linked to session
- File access events with user context

## Differences from Open Source Demo

| Feature | Open Source | Enterprise |
|---------|------------|-----------|
| Target Type | `tcp` only | `ssh` supported |
| Credentials | Brokered only | Injected supported |
| Certificate Injection | ❌ Not available | ✅ Available |
| Session Metadata | Manual correlation only | Automatic in certificates |
| Password Required | ✅ Yes | ❌ No (certificate auth) |

## Troubleshooting

### License Not Applied
**Symptom**: SSH target creation fails with "Unknown type provided"
**Solution**: Ensure `BOUNDARY_LICENSE` env var is set when starting boundary dev

### Credential Injection Fails  
**Symptom**: Error: "tcp.Target only supports credential purpose: 'brokered'"
**Solution**: Verify target type is `ssh`, not `tcp`

### Certificate Not Trusted
**Symptom**: SSH connection fails with "Permission denied (publickey)"
**Solution**: Verify ssh-target has Vault CA in TrustedUserCAKeys

### Session Metadata Missing
**Symptom**: Can connect but no session metadata in logs
**Solution**: Check that credential library is attached with `-injected-application-credential-source`

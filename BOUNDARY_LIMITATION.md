# Boundary SSH Certificate Injection Limitation

## Summary

**SSH certificate injection with Vault is NOT available in open-source Boundary.** This feature requires **HCP Boundary** (HashiCorp's managed Boundary service).

## What We Discovered

During implementation, we found that:

1. **SSH Target Type**: The `ssh` target type is HCP-only:
   ```
   $ boundary targets create --help
   Subcommands:
       ssh    Create a ssh-type target (HCP only)
       tcp    Create a tcp type target
   ```

2. **Credential Injection**: Open-source Boundary's `tcp` targets only support "brokered" credentials, not "injected-application" credentials:
   ```
   Error: tcp.Target only supports credential purpose: "brokered"
   ```

3. **Certificate Injection**: The Vault SSH certificate injection feature that would embed Boundary session metadata into SSH certificates is only available with HCP Boundary's SSH target type.

## What This Means

### Cannot Do (Open-Source Boundary):
- ❌ Inject SSH certificates with Boundary session metadata
- ❌ Automatically pass session_id, user_id into SSH sessions
- ❌ Have Boundary session metadata appear in SSH logs without manual correlation

### Can Do (Open-Source Boundary):
- ✅ Proxy SSH connections through Boundary
- ✅ Track Boundary sessions separately
- ✅ Use password or brokered credential authentication
- ✅ Manually correlate Boundary session logs with SSH audit logs by timestamp/username
- ✅ Capture SSH audit events with Auditbeat

### Can Do (HCP Boundary - Paid Service):
- ✅ Use SSH target type with certificate injection
- ✅ Embed Boundary session metadata in SSH certificates
- ✅ Automatic correlation between Boundary sessions and SSH audit events
- ✅ Session metadata visible in SSH logs and auditd events

## Demo Implications

This demo currently shows:
1. **Boundary Integration**: How to auto-configure Boundary and create SSH sessions programmatically
2. **Audit Event Collection**: How Auditbeat captures SSH-related system events
3. **Manual Correlation**: How session logs can be correlated with audit events by timestamp/username

To achieve full session metadata injection, users would need:
- **Option 1**: Use HCP Boundary (managed service, requires subscription)
- **Option 2**: Wait for this feature to potentially be added to open-source Boundary in the future
- **Option 3**: Implement custom SSH CA certificate generation with session metadata in certificate principals

## References

- [Boundary Target Types](https://developer.hashicorp.com/boundary/docs/concepts/domain-model/targets)
- [HCP Boundary SSH Targets](https://developer.hashicorp.com/boundary/docs/concepts/connection-workflows/workflow-ssh-proxyless)
- [Boundary Credential Injection](https://developer.hashicorp.com/boundary/docs/concepts/credentials)

## Recommendation

For the purposes of this demo:
1. Continue showing Boundary session management and SSH proxying
2. Document that full certificate injection requires HCP Boundary
3. Show how manual correlation can be done using logs and timestamps
4. Demonstrate the audit event collection capabilities that would work with HCP Boundary

This provides educational value while being transparent about the limitation.

# OpenClaw Security Configuration

## Security Features Implemented

### 1. Container Security
- ✅ Rootless Docker (non-root user execution)
- ✅ gVisor runtime (kernel-level isolation)
- ✅ Read-only root filesystem
- ✅ All capabilities dropped (except NET_BIND_SERVICE)
- ✅ No new privileges flag
- ✅ User namespace remapping
- ✅ AppArmor profiles (Ubuntu)

### 2. Secret Management
- ✅ Docker Secrets (memory-backed)
- ✅ 90-day rotation schedule
- ✅ Encrypted storage with git-crypt (development)
- ✅ Automated expiry tracking
- ✅ Secure input (hidden passwords)
- ✅ Format validation
- ✅ Zero-downtime rotation

### 3. Network Security
- ✅ Localhost-only binding (127.0.0.1)
- ✅ UFW firewall (SSH + Tailscale only)
- ✅ fail2ban SSH protection
- ✅ Isolated Docker network
- ✅ No public IP exposure
- ✅ Tailscale VPN for remote access

### 4. Application Security
- ✅ Telegram pairing mode
- ✅ User allowlist
- ✅ Mention-based group control
- ✅ Rate limiting (per-user + global)
- ✅ PII redaction in logs
- ✅ Content filtering
- ✅ Webhook secrets (optional)

### 5. System Security
- ✅ Automatic security updates (Ubuntu)
- ✅ Minimal attack surface
- ✅ No unnecessary packages
- ✅ Security audit logging
- ✅ Resource limits

## Threat Model

### Threats Addressed

1. **Container Escape** → gVisor + rootless Docker
2. **Credential Theft** → Docker Secrets + rotation
3. **Network Attack** → Firewall + localhost binding
4. **SSH Brute Force** → fail2ban + strong keys
5. **Unauthorized Access** → Pairing mode + allowlist
6. **Data Exfiltration** → Network isolation + logging
7. **Resource Exhaustion** → Resource limits + rate limiting
8. **Privilege Escalation** → No capabilities + no-new-privileges

### Remaining Risks

1. **API Key Compromise** → Rotate immediately if suspected
2. **Telegram Account Takeover** → Enable 2FA on Telegram
3. **Host Compromise** → Keep system updated, use Tailscale
4. **Supply Chain Attack** → Verify Docker image signatures
5. **Side-channel Attacks** → gVisor provides mitigation

## Security Checklist

### Initial Setup
- [ ] Run setup script (setup-ubuntu.sh or setup-macos.sh)
- [ ] Enable UFW firewall
- [ ] Configure fail2ban
- [ ] Install Tailscale
- [ ] Initialize secrets with strong API keys
- [ ] Enable 2FA on all API provider accounts
- [ ] Set strong Grafana admin password
- [ ] Configure email alerts

### Daily Operations
- [ ] Review logs for suspicious activity
- [ ] Check cost alerts (potential abuse indicator)
- [ ] Verify container is healthy
- [ ] Monitor failed authentication attempts

### Weekly Tasks
- [ ] Check secret expiry status
- [ ] Review Grafana security dashboard
- [ ] Check for system updates
- [ ] Review access logs
- [ ] Backup configuration

### Monthly Tasks
- [ ] Review and update allowlist
- [ ] Audit security events
- [ ] Test disaster recovery
- [ ] Review cost patterns for anomalies
- [ ] Update system packages

### Quarterly Tasks
- [ ] Rotate all secrets
- [ ] Security audit
- [ ] Review and update firewall rules
- [ ] Test backups
- [ ] Review and update documentation

## Incident Response

### Suspected Credential Compromise

1. **Immediate Actions**
   ```bash
   # Stop OpenClaw
   docker compose down
   
   # Rotate compromised secret
   ./rotate-secrets.sh --secret-name <secret_name>
   
   # Review logs for unauthorized usage
   docker compose logs openclaw | grep -i error
   ```

2. **Investigation**
   - Check Grafana for cost spikes
   - Review Prometheus security metrics
   - Check API provider usage dashboard
   - Review Telegram message history

3. **Remediation**
   - Rotate all secrets
   - Update allowlist
   - Review and update access controls
   - Document incident

### Unauthorized Access Attempt

1. **Check Alerts**
   ```bash
   # View authentication failures
   docker compose logs openclaw | grep -i "auth\|pairing\|failed"
   ```

2. **Block Source**
   ```bash
   # If from specific IP (via Tailscale/SSH)
   sudo ufw deny from <IP_ADDRESS>
   
   # If from Telegram user
   # Remove from allowFrom in config/openclaw.json
   ```

3. **Monitor**
   - Enable enhanced logging
   - Watch for repeated attempts
   - Consider changing Telegram bot token

### Container Compromise

1. **Isolate**
   ```bash
   # Stop container immediately
   docker compose down
   
   # Inspect container
   docker inspect openclaw-gateway
   ```

2. **Investigate**
   ```bash
   # Check for modifications
   docker diff openclaw-gateway
   
   # Review logs
   docker compose logs openclaw > incident-logs.txt
   ```

3. **Rebuild**
   ```bash
   # Remove potentially compromised image
   docker rmi openclaw:secure
   
   # Rebuild from scratch
   docker build --no-cache -t openclaw:secure .
   
   # Rotate all secrets
   ./rotate-secrets.sh --all
   
   # Deploy fresh container
   docker compose up -d
   ```

## Security Hardening Options

### Additional Measures (Advanced)

#### 1. AppArmor Profile (Ubuntu)

Create `/etc/apparmor.d/openclaw-profile`:

```
#include <tunables/global>

profile openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  
  capability net_bind_service,
  
  deny /proc/** wk,
  deny /sys/** wk,
  deny /home/** wk,
  
  /app/** r,
  /app/config/** rw,
  /app/workspace/** rw,
  /app/logs/** rw,
  /tmp/** rw,
  /run/secrets/** r,
}
```

Apply:
```bash
sudo apparmor_parser -r /etc/apparmor.d/openclaw-profile
```

#### 2. SELinux Policy (RHEL/CentOS)

```bash
# Create custom policy for OpenClaw
sudo semanage fcontext -a -t container_file_t "/path/to/openclaw(/.*)?"
sudo restorecon -Rv /path/to/openclaw
```

#### 3. Network Segmentation

Edit `docker-compose.yml`:

```yaml
networks:
  openclaw-net:
    internal: true  # No internet access
  
  openclaw-external:
    driver: bridge  # Internet access only for LLM APIs
```

#### 4. Audit Logging

```bash
# Enable Docker audit logging
sudo auditctl -w /usr/bin/docker -k docker
sudo auditctl -w /var/lib/docker -k docker

# View audit logs
sudo ausearch -k docker
```

## Compliance Considerations

### GDPR (if storing EU user data)

- ✅ PII redaction in logs
- ✅ Data encryption at rest (workspace volume)
- ⚠️ Implement data retention policy
- ⚠️ Provide user data export capability
- ⚠️ Implement right-to-be-forgotten

### SOC 2

- ✅ Access controls (allowlist)
- ✅ Audit logging
- ✅ Encryption in transit (TLS)
- ✅ Monitoring and alerting
- ⚠️ Formal incident response plan
- ⚠️ Regular security training

## References

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [gVisor Security Model](https://gvisor.dev/docs/architecture_guide/security/)
- [NIST Container Security Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [OpenClaw Security Documentation](https://docs.openclaw.ai/security)

## Contact

For security issues, please:
1. Do NOT create public GitHub issues
2. Email security concerns privately
3. Use encrypted communication when possible
4. Allow reasonable time for patching before disclosure

# n8n GCP Deployment - Security Guide

This document provides comprehensive security hardening guidelines and best practices for the n8n GCP deployment.

## Table of Contents

1. [Security Architecture Overview](#security-architecture-overview)
2. [Critical Security Configurations](#critical-security-configurations)
3. [GCP Server Hardening](#gcp-server-hardening)
4. [n8n Application Security](#n8n-application-security)
5. [Network Security](#network-security)
6. [Secrets Management](#secrets-management)
7. [Backup Security](#backup-security)
8. [Monitoring and Auditing](#monitoring-and-auditing)
9. [Incident Response](#incident-response)
10. [Security Checklist](#security-checklist)

---

## Security Architecture Overview

### Defense in Depth Strategy

This deployment implements multiple layers of security:

```
┌─────────────────────────────────────────────┐
│ Layer 1: Cloudflare DDoS Protection        │
│          - WAF Rules                        │
│          - Rate Limiting                    │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│ Layer 2: Cloudflare Tunnel (Zero Trust)    │
│          - No exposed ports                 │
│          - Encrypted tunnel                 │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│ Layer 3: GCP Firewall                      │
│          - SSH-only access                  │
│          - IP whitelisting                  │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│ Layer 4: OS Security (fail2ban, updates)   │
│          - Automated security patches       │
│          - Intrusion prevention             │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│ Layer 5: Docker Network Isolation          │
│          - Private bridge network           │
│          - No direct port exposure          │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│ Layer 6: Application Security (n8n)        │
│          - Basic authentication             │
│          - Credential encryption            │
│          - Session management               │
└─────────────────────────────────────────────┘
```

### Key Security Principles

1. **Zero Trust Network**: No services exposed directly to the internet
2. **Least Privilege**: Minimal permissions for all components
3. **Defense in Depth**: Multiple security layers
4. **Encryption Everywhere**: Data encrypted at rest and in transit
5. **Secure by Default**: Security-first configuration

---

## Critical Security Configurations

### 1. Restrict SSH Access (CRITICAL)

**Default Configuration Issue**: SSH is currently open to 0.0.0.0/0 (entire internet)

**Fix Immediately**:

```bash
# Edit Terraform variables
cd infra/terraform
nano terraform.tfvars
```

Add your IP address:

```hcl
ssh_source_ranges = [
  "YOUR_PUBLIC_IP/32",  # Your home/office IP
  # Add additional IPs as needed
]
```

Apply changes:

```bash
terraform apply
```

**For Dynamic IPs**, consider:

```hcl
ssh_source_ranges = [
  "YOUR_IP_RANGE/24",  # Broader range for dynamic IPs
]
```

Or use VPN with static endpoint.

### 2. Fix Ansible SSH Host Key Checking

**Current Configuration Issue**: `StrictHostKeyChecking=no` allows MITM attacks

**Fix**:

```bash
cd infra/ansible
nano inventory.ini
```

Change line 30:

```ini
# From:
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

# To:
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
```

Or remove entirely and add host key manually:

```bash
ssh-keyscan -H YOUR_SERVER_IP >> ~/.ssh/known_hosts
```

### 3. Secure Terraform State

**Issue**: Terraform state contains sensitive infrastructure data

**Recommended**: Use remote state backend

```hcl
# Add to infra/terraform/main.tf
terraform {
  backend "gcs" {
    bucket  = "your-terraform-state-bucket"
    prefix  = "n8n/state"
  }
}
```

Create the bucket:

```bash
# Create bucket for state storage
gsutil mb -l us-central1 gs://your-terraform-state-bucket

# Enable versioning
gsutil versioning set on gs://your-terraform-state-bucket

# Restrict access
gsutil iam ch user:you@example.com:objectAdmin gs://your-terraform-state-bucket
```

### 4. Validate Encryption Key Strength

Ensure n8n encryption key is cryptographically secure:

```bash
# Generate a strong key (32+ characters)
openssl rand -base64 32

# Add to vault.yml
cd infra/ansible
ansible-vault edit vault.yml

# Set:
n8n_encryption_key: "<output-from-openssl-command>"
```

**CRITICAL**: Never change the encryption key after deployment or all credentials will be lost!

---

## GCP Server Hardening

### System Security Configuration

The Ansible playbook already configures many security features. Verify they're active:

#### 1. Automatic Security Updates

**Verification**:

```bash
ssh ubuntu@YOUR_SERVER_IP

# Check unattended-upgrades is installed and configured
systemctl status unattended-upgrades

# Verify configuration
cat /etc/apt/apt.conf.d/50unattended-upgrades | grep "Unattended-Upgrade::Automatic-Reboot"
```

**Should show**: Automatic security updates enabled with reboot at 3 AM if needed

#### 2. Fail2ban for SSH Protection

**Verification**:

```bash
# Check fail2ban is running
sudo systemctl status fail2ban

# View SSH jail status
sudo fail2ban-client status sshd

# Check banned IPs
sudo fail2ban-client status sshd | grep "Banned IP"
```

**Configuration** (already set via Ansible):
- Max retry: 5 attempts
- Ban time: 3600 seconds (1 hour)
- Find time: 600 seconds (10 minutes)

**To manually ban/unban**:

```bash
# Ban an IP
sudo fail2ban-client set sshd banip 192.168.1.100

# Unban an IP
sudo fail2ban-client set sshd unbanip 192.168.1.100
```

#### 3. Firewall Configuration (UFW)

Currently, firewall is disabled as Cloudflare Tunnel handles all ingress. This is acceptable but you can enable UFW for additional protection:

```bash
# Enable UFW (optional)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from YOUR_IP to any port 22
sudo ufw enable

# Check status
sudo ufw status verbose
```

#### 4. SSH Hardening

**Additional SSH security** (beyond Ansible configuration):

```bash
sudo nano /etc/ssh/sshd_config
```

Recommended settings:

```conf
# Disable password authentication (key-only)
PasswordAuthentication no
PubkeyAuthentication yes

# Disable root login
PermitRootLogin no

# Limit authentication attempts
MaxAuthTries 3

# Disconnect idle sessions
ClientAliveInterval 300
ClientAliveCountMax 2

# Disable X11 forwarding
X11Forwarding no

# Use strong ciphers only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

#### 5. Audit Logging

**Enable auditd for security monitoring**:

```bash
sudo apt install auditd audispd-plugins -y

# Monitor sensitive files
sudo auditctl -w /etc/passwd -p wa -k passwd_changes
sudo auditctl -w /etc/shadow -p wa -k shadow_changes
sudo auditctl -w /etc/ssh/sshd_config -p wa -k sshd_config_changes

# Monitor Docker
sudo auditctl -w /usr/bin/docker -p wa -k docker_commands

# View audit logs
sudo ausearch -k passwd_changes
```

### Disk Encryption

**Current Status**: Data disk is NOT encrypted by default

**To enable encryption** (requires recreating disk):

1. **Backup all data first**

2. **Update Terraform**:

```hcl
# In infra/terraform/main.tf
resource "google_compute_disk" "data_disk" {
  # ... existing config ...

  disk_encryption_key {
    kms_key_self_link = google_kms_crypto_key.n8n_disk_key.id
  }
}

# Create KMS key
resource "google_kms_key_ring" "n8n_keyring" {
  name     = "n8n-keyring"
  location = "us-central1"
}

resource "google_kms_crypto_key" "n8n_disk_key" {
  name            = "n8n-disk-key"
  key_ring        = google_kms_key_ring.n8n_keyring.id
  rotation_period = "7776000s"  # 90 days
}
```

---

## n8n Application Security

### Basic Authentication

**Current Configuration**: Basic auth enabled

**Strengthen**:

```bash
# Edit vault.yml
ansible-vault edit infra/ansible/vault.yml

# Use a strong password (20+ characters)
n8n_basic_auth_password: "<generate-strong-password>"
```

Generate strong password:

```bash
openssl rand -base64 20
```

### Two-Factor Authentication

n8n doesn't natively support 2FA, but you can add it via Cloudflare Access:

1. **Cloudflare Dashboard** → Access → Applications
2. **Create Application**:
   - Name: n8n
   - Domain: n8n.yourdomain.com
3. **Add Authentication Method**:
   - One-time PIN via email
   - Google/GitHub OAuth
   - Hardware security keys
4. **Create Policy**:
   - Include: Emails ending in @yourdomain.com
   - Require: 2FA enabled

This adds a second authentication layer before reaching n8n.

### Session Security

**Configure session timeout**:

```bash
# Edit .env on server or vault.yml for Ansible
N8N_USER_MANAGEMENT_JWT_DURATION_HOURS=12  # Session expires after 12 hours
```

### Webhook Security

**Use webhook authentication**:

When creating webhooks in n8n:
1. Use "Header Auth" with custom header
2. Generate secret token:
   ```bash
   openssl rand -hex 32
   ```
3. Configure calling service to include header:
   ```
   X-Webhook-Secret: <your-secret-token>
   ```

### Credential Encryption

**CRITICAL: Backup Encryption Key**

Your n8n encryption key encrypts all stored credentials. If lost, credentials cannot be recovered.

**Backup Process**:

```bash
# Store in 1Password, password manager, or encrypted backup
# DO NOT store in git or unencrypted files

# Method 1: Add to 1Password
op item create --category=password \
  --title="n8n Encryption Key" \
  --vault="Your Vault" \
  'encryption_key=<your-key>'

# Method 2: Encrypted file
echo "YOUR_ENCRYPTION_KEY" | gpg --symmetric --armor > n8n-encryption-key.gpg
# Store n8n-encryption-key.gpg in secure location
```

### Workflow Security

**Best Practices**:

1. **Limit Workflow Permissions**:
   - Don't use admin API keys in workflows
   - Create service accounts with minimal permissions

2. **Validate Input Data**:
   - Use "IF" nodes to validate webhook data
   - Sanitize user input before processing

3. **Secure API Keys**:
   - Use n8n credentials feature (encrypted)
   - Never hardcode keys in workflow nodes

4. **Audit Workflows**:
   - Regularly review active workflows
   - Disable unused workflows
   - Monitor execution logs for anomalies

---

## Network Security

### Cloudflare Tunnel Security

**Best Practices**:

1. **Rotate Tunnel Token Periodically**:
   ```bash
   # Every 90-180 days, create new tunnel
   # Update token in vault.yml
   ansible-vault edit infra/ansible/vault.yml
   ```

2. **Enable Cloudflare WAF**:
   - Cloudflare Dashboard → Security → WAF
   - Enable OWASP Core Ruleset
   - Create custom rules for your use case

3. **Configure Rate Limiting**:
   - Security → Rate Limiting Rules
   - Example: Limit to 100 requests/minute per IP

4. **Enable Bot Protection**:
   - Security → Bots
   - Block known bots
   - Challenge suspicious traffic

### Docker Network Isolation

**Current Configuration**:
- All containers on `n8n-network` bridge
- n8n only exposes to localhost (127.0.0.1:5678)
- Cloudflared connects via internal network

**Verification**:

```bash
# Check network configuration
docker network inspect n8n-network

# Verify n8n not exposed externally
sudo netstat -tulpn | grep 5678
# Should show: 127.0.0.1:5678 (NOT 0.0.0.0:5678)
```

### DNS Security

**Enable DNSSEC** (optional but recommended):

1. Cloudflare Dashboard → DNS → Settings
2. Enable DNSSEC
3. Add DS records to your domain registrar

**Enable CAA Records**:

```
yourdomain.com. CAA 0 issue "letsencrypt.org"
yourdomain.com. CAA 0 issuewild "letsencrypt.org"
yourdomain.com. CAA 0 iodef "mailto:security@yourdomain.com"
```

---

## Secrets Management

### Ansible Vault

**Current Setup**: Encrypted vault.yml with AES256

**Best Practices**:

1. **Use Strong Vault Password**:
   ```bash
   # Generate strong password
   openssl rand -base64 24
   ```

2. **Store Vault Password Securely**:
   ```bash
   # Method 1: Password file (restrict permissions)
   echo "YOUR_VAULT_PASSWORD" > ~/.ansible_vault_pass
   chmod 600 ~/.ansible_vault_pass

   # Update ansible.cfg
   echo "vault_password_file = ~/.ansible_vault_pass" >> infra/ansible/ansible.cfg
   ```

3. **Rotate Vault Password**:
   ```bash
   cd infra/ansible
   ansible-vault rekey vault.yml
   # Enter old password, then new password
   ```

### 1Password Integration

**Current Setup**: SSH key retrieval from 1Password

**Extend to Other Secrets**:

```bash
# Store all deployment secrets in 1Password

# Cloudflare token
op item create --category=password \
  --title="n8n Cloudflare Tunnel" \
  cloudflare_token=<your-token>

# PostgreSQL password
op item create --category=password \
  --title="n8n PostgreSQL" \
  postgres_password=<your-password>

# Retrieve during deployment
CLOUDFLARE_TOKEN=$(op item get "n8n Cloudflare Tunnel" --fields label=cloudflare_token)
```

### Environment File Security

**Current Configuration**: `.env` file mode 0600 (owner read/write only)

**Verification**:

```bash
ssh ubuntu@YOUR_SERVER_IP
ls -la /opt/n8n/.env
# Should show: -rw------- ubuntu ubuntu .env
```

**If permissions are wrong**:

```bash
sudo chmod 600 /opt/n8n/.env
sudo chown ubuntu:ubuntu /opt/n8n/.env
```

---

## Backup Security

### Current Backup Strategy

**Automated Backups**:
- Daily backups via cron (2 AM)
- 30-day retention
- Includes: database, n8n data, configuration

**Security Gaps**:
1. Backups are NOT encrypted
2. `.env` file stored in plaintext in backups
3. Backups stored only on same server (single point of failure)

### Hardened Backup Strategy

#### 1. Encrypt Backups

**Update backup script** to add GPG encryption:

```bash
sudo nano /opt/n8n/scripts/backup.sh
```

Add after database backup (around line 62):

```bash
# Encrypt database backup
GPG_PASSPHRASE_FILE="/root/.backup-passphrase"
if [ ! -f "$GPG_PASSPHRASE_FILE" ]; then
    openssl rand -base64 32 > "$GPG_PASSPHRASE_FILE"
    chmod 600 "$GPG_PASSPHRASE_FILE"
    echo "Created backup encryption passphrase at $GPG_PASSPHRASE_FILE"
    echo "BACKUP THIS FILE SECURELY!"
fi

gpg --symmetric --cipher-algo AES256 --batch --yes \
    --passphrase-file "$GPG_PASSPHRASE_FILE" \
    "$backup_path/database.sql.gz"
rm "$backup_path/database.sql.gz"
mv "$backup_path/database.sql.gz.gpg" "$backup_path/database.sql.gz.gpg"

# Encrypt .env file
gpg --symmetric --cipher-algo AES256 --batch --yes \
    --passphrase-file "$GPG_PASSPHRASE_FILE" \
    "$backup_path/.env"
rm "$backup_path/.env"
mv "$backup_path/.env.gpg" "$backup_path/.env.gpg"
```

**Backup the passphrase**:

```bash
# Copy /root/.backup-passphrase to 1Password
ssh ubuntu@YOUR_SERVER_IP "sudo cat /root/.backup-passphrase" | \
  op item create --category=password \
    --title="n8n Backup Encryption" \
    passphrase[password]=-
```

#### 2. Off-Site Backup Storage

**Option A: Google Cloud Storage**

```bash
# Create GCS bucket
gsutil mb -l us-central1 -b on gs://your-n8n-backups

# Enable versioning
gsutil versioning set on gs://your-n8n-backups

# Set lifecycle (delete after 90 days)
cat > lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [{
      "action": {"type": "Delete"},
      "condition": {"age": 90}
    }]
  }
}
EOF
gsutil lifecycle set lifecycle.json gs://your-n8n-backups

# Add to backup script
gsutil -m cp -r /mnt/data/backups/$(date +%Y%m%d_*)  gs://your-n8n-backups/
```

**Option B: Backblaze B2 (cheaper)**

```bash
# Install B2 CLI
sudo apt install b2 -y

# Authenticate
b2 authorize-account <keyId> <applicationKey>

# Create bucket
b2 create-bucket --defaultServerSideEncryption=SSE-B2 n8n-backups allPrivate

# Add to backup script
b2 sync /mnt/data/backups b2://n8n-backups
```

#### 3. Backup Verification

Add integrity checks to backup script:

```bash
# Create checksums
cd "$backup_path"
sha256sum *.gpg > checksums.txt

# Verify (add to restore process)
sha256sum -c checksums.txt
```

#### 4. Backup Retention

**Current**: 30 days on server

**Recommended**: Tiered retention

```bash
# On server: 7 days (quick recovery)
find /mnt/data/backups -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

# Off-site: 90 days (GCS lifecycle policy handles this)
```

### Restore Procedure

**Document restore process**:

```bash
#!/bin/bash
# /opt/n8n/scripts/restore.sh

set -euo pipefail

BACKUP_DATE=$1  # Format: YYYYMMDD_HHMMSS
BACKUP_PATH="/mnt/data/backups/$BACKUP_DATE"
GPG_PASSPHRASE_FILE="/root/.backup-passphrase"

if [ ! -d "$BACKUP_PATH" ]; then
    echo "Backup not found: $BACKUP_PATH"
    exit 1
fi

# Verify checksums
cd "$BACKUP_PATH"
sha256sum -c checksums.txt || exit 1

# Decrypt database
gpg --decrypt --batch --yes \
    --passphrase-file "$GPG_PASSPHRASE_FILE" \
    database.sql.gz.gpg > database.sql.gz

# Stop n8n
cd /opt/n8n
docker compose stop n8n

# Restore database
gunzip -c "$BACKUP_PATH/database.sql.gz" | \
    docker compose exec -T postgres psql -U n8n n8n

# Restore n8n data
tar -xzf "$BACKUP_PATH/n8n_data.tar.gz" -C /mnt/data

# Start n8n
docker compose up -d n8n

echo "Restore complete from $BACKUP_DATE"
```

---

## Monitoring and Auditing

### Log Aggregation

**Centralized Logging** (recommended for production):

```yaml
# Add to docker-compose.yml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
    labels: "service,environment"
```

**Ship logs to Google Cloud Logging**:

```bash
# Install logging agent
curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
sudo bash add-logging-agent-repo.sh
sudo apt-get install google-fluentd
```

### Security Monitoring

**1. Monitor Failed SSH Attempts**:

```bash
# Create alert script
cat > /opt/n8n/scripts/ssh-alert.sh <<'EOF'
#!/bin/bash
FAILED_LOGINS=$(journalctl -u sshd -S today | grep "Failed password" | wc -l)
if [ $FAILED_LOGINS -gt 10 ]; then
    echo "WARNING: $FAILED_LOGINS failed SSH attempts today" | \
        mail -s "SSH Security Alert" you@example.com
fi
EOF

chmod +x /opt/n8n/scripts/ssh-alert.sh

# Add to cron
crontab -e
0 */4 * * * /opt/n8n/scripts/ssh-alert.sh
```

**2. Monitor Disk Usage**:

```bash
# Alert on 80% disk usage
cat > /opt/n8n/scripts/disk-alert.sh <<'EOF'
#!/bin/bash
USAGE=$(df /mnt/data | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $USAGE -gt 80 ]; then
    echo "WARNING: Disk usage at ${USAGE}%" | \
        mail -s "Disk Space Alert" you@example.com
fi
EOF

chmod +x /opt/n8n/scripts/disk-alert.sh

# Add to cron (daily)
0 9 * * * /opt/n8n/scripts/disk-alert.sh
```

**3. Monitor Container Health**:

```bash
# Check container health status
cat > /opt/n8n/scripts/health-check.sh <<'EOF'
#!/bin/bash
cd /opt/n8n
for container in n8n postgres cloudflared; do
    health=$(docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null || echo "not found")
    if [ "$health" != "healthy" ]; then
        echo "WARNING: Container $container health: $health" | \
            mail -s "Container Health Alert" you@example.com
    fi
done
EOF

chmod +x /opt/n8n/scripts/health-check.sh

# Add to cron (every 15 minutes)
*/15 * * * * /opt/n8n/scripts/health-check.sh
```

### GCP Monitoring

**Enable Cloud Monitoring** (free tier available):

```bash
# Install monitoring agent
curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
sudo bash add-monitoring-agent-repo.sh
sudo apt-get install stackdriver-agent
```

**Create Alerts** in GCP Console:
1. Monitoring → Alerting → Create Policy
2. Alerts to create:
   - CPU usage > 80% for 5 minutes
   - Disk usage > 80%
   - Memory usage > 90%
   - Instance down for 5 minutes

### Audit Logs

**Review logs regularly**:

```bash
# SSH access logs
sudo journalctl -u sshd -S yesterday

# fail2ban bans
sudo fail2ban-client status sshd

# Docker logs
docker compose logs --since 24h

# System authentication
sudo journalctl -u systemd-logind -S yesterday

# Check for sudo usage
sudo journalctl _COMM=sudo -S yesterday
```

---

## Incident Response

### Security Incident Playbook

#### 1. Suspected Compromise

**If you suspect the server has been compromised**:

```bash
# Immediate actions:

# 1. Isolate server (block all SSH)
gcloud compute firewall-rules update allow-ssh-n8n \
    --source-ranges=0.0.0.0/32

# 2. Create snapshot for forensics
gcloud compute disks snapshot n8n-server-disk \
    --snapshot-names=incident-$(date +%Y%m%d-%H%M%S) \
    --zone=us-central1-a

# 3. Check for unauthorized access
ssh ubuntu@SERVER_IP
sudo last -f /var/log/wtmp
sudo journalctl -u sshd | grep "Accepted"

# 4. Check for malicious processes
ps aux
sudo netstat -tulpn
docker ps -a

# 5. Review modifications
sudo find / -type f -mtime -1  # Files modified in last 24h

# 6. Check cron jobs
crontab -l
sudo cat /etc/crontab
ls -la /etc/cron.*

# 7. Review Docker containers
docker diff n8n
docker diff postgres
```

#### 2. Data Breach Response

**If credentials or data may have been exposed**:

```bash
# 1. Rotate all secrets immediately
ansible-vault edit infra/ansible/vault.yml
# Update: postgres_password, n8n_basic_auth_password

# 2. Rotate n8n encryption key (CAREFUL!)
# This will invalidate all stored credentials
# Only if you're certain old key is compromised

# 3. Re-deploy with new secrets
ansible-playbook playbook.yml --ask-vault-pass

# 4. Notify users (if applicable)

# 5. Review audit logs
docker compose logs n8n | grep -i "login\|auth"

# 6. Reset workflows using compromised credentials
```

#### 3. Ransomware/Malware

**If ransomware or malware detected**:

```bash
# 1. DO NOT pay ransom

# 2. Immediately power off instance
gcloud compute instances stop n8n-server --zone=us-central1-a

# 3. Create snapshot of current state (evidence)
gcloud compute disks snapshot n8n-server-disk \
    --snapshot-names=ransomware-$(date +%Y%m%d) \
    --zone=us-central1-a

# 4. Restore from clean backup
# Follow restore procedure in Backup Security section

# 5. Deploy to NEW instance
# Don't reuse potentially compromised instance
cd infra/terraform
terraform taint google_compute_instance.n8n_instance
terraform apply

# 6. Restore data from backup
# 7. Review how malware entered system
```

### Contact Information

**Maintain emergency contact list**:

```
Security Contact: Your Name
Email: you@example.com
Phone: +1-XXX-XXX-XXXX

GCP Support: https://cloud.google.com/support
Cloudflare Support: https://support.cloudflare.com

Backup Location: gs://your-n8n-backups
Backup Encryption Key: [stored in 1Password: "n8n Backup Encryption"]
Terraform State: [gs://your-terraform-state-bucket or local]
```

---

## Security Checklist

### Pre-Deployment Checklist

- [ ] Strong vault password set (20+ characters)
- [ ] Encryption key generated (32+ characters, random)
- [ ] Encryption key backed up to 1Password
- [ ] SSH source IP restricted in terraform.tfvars
- [ ] PostgreSQL password set (20+ characters)
- [ ] n8n basic auth password set (20+ characters)
- [ ] Cloudflare Tunnel token obtained
- [ ] All secrets stored in vault.yml
- [ ] Terraform state using remote backend (GCS)
- [ ] SSH public key added to terraform.tfvars
- [ ] `.gitignore` properly configured

### Post-Deployment Checklist

- [ ] SSH access restricted to your IP only
- [ ] fail2ban active and configured
- [ ] Automatic security updates enabled
- [ ] Cloudflare WAF rules enabled
- [ ] Rate limiting configured
- [ ] Backups running successfully (check cron)
- [ ] Backup encryption tested
- [ ] Off-site backup configured (GCS/B2)
- [ ] Monitoring alerts configured
- [ ] Health check scripts deployed
- [ ] Audit logging enabled (auditd)
- [ ] Log rotation configured
- [ ] Docker containers running as expected
- [ ] n8n accessible via Cloudflare domain
- [ ] SSL/TLS working correctly
- [ ] Test restore from backup

### Monthly Security Review

- [ ] Review SSH access logs
- [ ] Check fail2ban ban list
- [ ] Verify backups are completing
- [ ] Test backup restoration
- [ ] Review workflow executions for anomalies
- [ ] Check disk usage
- [ ] Review Docker image versions (update if needed)
- [ ] Review Cloudflare security events
- [ ] Check for OS security updates
- [ ] Review n8n audit logs
- [ ] Verify monitoring alerts working

### Quarterly Security Tasks

- [ ] Rotate Cloudflare Tunnel token
- [ ] Update Docker images to latest versions
- [ ] Review and update firewall rules
- [ ] Audit user access and credentials
- [ ] Review and update workflow permissions
- [ ] Test incident response procedures
- [ ] Review and update documentation
- [ ] Security assessment/penetration test

### Annual Security Tasks

- [ ] Rotate ansible vault password
- [ ] Full security audit
- [ ] Disaster recovery drill (full restore)
- [ ] Review and update security policies
- [ ] Update contact information
- [ ] Review compliance requirements

---

## Additional Resources

### Security Tools

**Recommended Security Tools**:

1. **rkhunter** - Rootkit detection
   ```bash
   sudo apt install rkhunter -y
   sudo rkhunter --update
   sudo rkhunter --check
   ```

2. **AIDE** - File integrity monitoring
   ```bash
   sudo apt install aide -y
   sudo aideinit
   sudo aide --check
   ```

3. **ClamAV** - Antivirus scanning
   ```bash
   sudo apt install clamav clamav-daemon -y
   sudo freshclam
   sudo clamscan -r /opt/n8n /mnt/data
   ```

4. **Lynis** - Security auditing
   ```bash
   sudo apt install lynis -y
   sudo lynis audit system
   ```

### Security References

- **OWASP Top 10**: https://owasp.org/www-project-top-ten/
- **CIS Docker Benchmark**: https://www.cisecurity.org/benchmark/docker
- **GCP Security Best Practices**: https://cloud.google.com/security/best-practices
- **Cloudflare Security**: https://www.cloudflare.com/learning/security/
- **n8n Security**: https://docs.n8n.io/security/

### Compliance Frameworks

If you need to comply with specific regulations:

**GDPR** (Data Protection):
- Encryption at rest: ✅ (n8n credentials encrypted)
- Encryption in transit: ✅ (Cloudflare SSL/TLS)
- Right to erasure: Implement workflow to delete user data
- Data breach notification: Document incident response process

**SOC 2** (Security Controls):
- Access controls: ✅ (SSH keys, basic auth, Cloudflare)
- Monitoring: Implement logging and alerting (above)
- Backups: ✅ (encrypted, automated, tested)
- Incident response: Document procedures (above)

**PCI DSS** (Payment Card Data):
- Network segmentation: ✅ (Docker network isolation)
- Encryption: ✅ (SSL/TLS, credential encryption)
- Access control: ✅ (minimal privileges)
- Monitoring: Implement logging (above)
- Vulnerability management: Automatic security updates ✅

---

## Summary

This n8n GCP deployment has a solid security foundation:

**Strengths**:
- Zero-trust architecture with Cloudflare Tunnel
- No direct internet exposure
- Automated security updates
- Fail2ban SSH protection
- Encrypted credentials
- Automated backups

**Critical Actions Required**:
1. Restrict SSH access to your IP (currently open to internet)
2. Fix SSH host key checking in Ansible
3. Move Terraform state to remote backend
4. Encrypt backups

**Recommended Enhancements**:
- Enable backup encryption
- Configure off-site backups
- Implement monitoring alerts
- Add two-factor authentication via Cloudflare Access
- Enable audit logging
- Regular security reviews

Follow the checklists in this document and you'll have a well-secured n8n deployment.

---

**Last Updated**: 2025-10-19
**Version**: 1.0
**Maintained By**: Infrastructure Team

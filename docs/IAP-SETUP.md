# Google Identity-Aware Proxy (IAP) Setup for SSH Access

This document describes how to set up secure SSH access to the n8n GCP instance using Google Identity-Aware Proxy (IAP) without requiring a public IP address.

## Overview

Identity-Aware Proxy (IAP) provides secure access to your GCP VM instances through Google's private network. With IAP:
- **No public IP needed** - VM has only private IP
- **No VPN required** - Works from anywhere
- **Identity-based access** - Uses Google account authentication + IAM
- **Encrypted tunnel** - Traffic goes through Google's backbone network
- **Audit logs** - All access logged in GCP Console
- **Free tier** - No cost for < 1000 hours/month

## Architecture

```
Your Mac → Google IAP (iap.googleapis.com)
           ↓ (encrypted tunnel through Google's private network)
           GCP VPC → n8n-server (private IP only)
```

## Prerequisites

- `gcloud` CLI installed and authenticated
- GCP project with billing enabled
- Owner or Editor role on the project (or specific IAM permissions listed below)

## Setup Steps

### 1. Enable Required APIs

These APIs must be enabled in your GCP project:

```bash
# Enable IAP and Compute Engine APIs
gcloud services enable iap.googleapis.com
gcloud services enable compute.googleapis.com
```

**Note:** Terraform does NOT automatically enable the IAP API. You must enable it manually or add this to your Terraform configuration:

```hcl
resource "google_project_service" "iap_api" {
  project = var.project_id
  service = "iap.googleapis.com"

  disable_on_destroy = false
}
```

### 2. Grant IAM Permissions

Each user who needs SSH access must have these IAM roles:

```bash
# Get your Google account email
ACCOUNT_EMAIL=$(gcloud config get-value account)

# Grant IAP tunnel access
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:${ACCOUNT_EMAIL}" \
  --role="roles/iap.tunnelResourceAccessor"

# Grant compute instance access
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:${ACCOUNT_EMAIL}" \
  --role="roles/compute.instanceAdmin.v1"
```

**Alternative roles** (if you don't want full instanceAdmin):
- Minimum: `roles/compute.instances.get` + `roles/iap.tunnelResourceAccessor`
- View-only: `roles/compute.viewer` + `roles/iap.tunnelResourceAccessor`

### 3. Configure Firewall Rules

Terraform creates this firewall rule automatically:

```hcl
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.instance_name}-allow-ssh-iap"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google IAP IP range (fixed, globally used by IAP)
  source_ranges = ["35.235.240.0/20"]

  target_tags = ["n8n"]

  description = "Allow SSH via Google Identity-Aware Proxy"
}
```

**Important:** The source range `35.235.240.0/20` is Google's official IAP IP range and should not be changed.

### 4. Configure SSH Access

#### Option A: Using gcloud Command

```bash
# Connect to VM via IAP
gcloud compute ssh n8n-server \
  --zone=us-central1-a \
  --tunnel-through-iap
```

#### Option B: SSH Config (Recommended)

Add to `~/.ssh/config`:

```ssh-config
# n8n server via Google Identity-Aware Proxy
Host n8n
  HostName n8n-server
  User ubuntu
  ProxyCommand gcloud compute start-iap-tunnel n8n-server 22 --listen-on-stdin --project=PROJECT_ID --zone=us-central1-a --verbosity=warning
```

Then simply:
```bash
ssh n8n
```

#### Option C: With 1Password SSH Agent

If using 1Password SSH agent, the config becomes:

```ssh-config
# n8n server via Google Identity-Aware Proxy
Host n8n
  HostName n8n-server
  User ubuntu
  ProxyCommand gcloud compute start-iap-tunnel n8n-server 22 --listen-on-stdin --project=PROJECT_ID --zone=us-central1-a --verbosity=warning

# Global 1Password SSH agent config
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

### 5. Configure Ansible (Optional)

If using Ansible, update `infra/ansible/inventory.ini`:

```ini
[n8n_servers]
n8n-server ansible_ssh_common_args='-o ProxyCommand="gcloud compute start-iap-tunnel %h 22 --listen-on-stdin --project=PROJECT_ID --zone=us-central1-a --verbosity=warning"'

[n8n_servers:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
```

Test Ansible connectivity:
```bash
cd infra/ansible
ansible n8n_servers -m ping
```

## Verification

### Test IAP Connection

```bash
# Test SSH connection
gcloud compute ssh n8n-server \
  --zone=us-central1-a \
  --tunnel-through-iap

# Or with SSH config
ssh n8n
```

### Verify Connection Source

Once connected, check the connection source:

```bash
# Show active SSH connections
who
# or
w

# Should show connection from IAP IP range (35.235.240.x)
```

### Check IAP Logs

View IAP access logs in GCP Console:
1. **IAM & Admin** → **Identity-Aware Proxy**
2. **SSH and TCP Resources** tab
3. View access logs and audit trail

## Troubleshooting

### Error: "Permission denied"

**Cause:** Missing IAM permissions

**Solution:**
```bash
# Verify you have the required roles
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:YOUR_EMAIL"

# Grant missing permissions (see Step 2 above)
```

### Error: "Failed to connect to backend"

**Cause:** Firewall rule not allowing IAP IP range

**Solution:**
```bash
# Verify firewall rule exists
gcloud compute firewall-rules describe n8n-server-allow-ssh-iap

# Check VM has correct network tags
gcloud compute instances describe n8n-server \
  --zone=us-central1-a \
  --format='get(tags.items)'
# Should include "n8n"
```

### Error: "Connection timeout"

**Cause:** SSH daemon not running on VM

**Solution:**
```bash
# Use GCP Serial Console as emergency access
gcloud compute connect-to-serial-port n8n-server \
  --zone=us-central1-a

# Check SSH status
sudo systemctl status sshd
sudo systemctl restart sshd
```

### Error: "Could not start IAP tunnel"

**Cause:** IAP API not enabled

**Solution:**
```bash
# Enable IAP API
gcloud services enable iap.googleapis.com

# Wait a few minutes for API to fully propagate
```

## Security Considerations

### IAM Best Practices

1. **Principle of Least Privilege**: Grant minimum required roles
2. **Regular Audits**: Review IAM permissions quarterly
3. **Enable 2FA**: Require 2-factor authentication for Google accounts
4. **Service Accounts**: Use service accounts for automated access

### Network Security

1. **IAP IP Range**: Never change `35.235.240.0/20` - this is Google's official range
2. **Remove Public IP**: After IAP is working, remove public IP from VM
3. **Disable Password Auth**: Use SSH keys only (already configured)
4. **Monitor Access**: Enable audit logging and review regularly

### Emergency Access

If IAP fails, use **GCP Serial Console**:

```bash
# Enable serial console
gcloud compute instances add-metadata n8n-server \
  --zone=us-central1-a \
  --metadata=serial-port-enable=TRUE

# Access via serial console
gcloud compute connect-to-serial-port n8n-server \
  --zone=us-central1-a
```

## IAM Roles Reference

### Required for SSH Access

| Role | Permission | Purpose |
|------|------------|---------|
| `roles/iap.tunnelResourceAccessor` | `iap.tunnelInstances.accessViaIAP` | Create IAP tunnel |
| `roles/compute.instanceAdmin.v1` | `compute.instances.*` | View and manage instances |

### Optional Roles

| Role | Use Case |
|------|----------|
| `roles/compute.viewer` | Read-only access to compute resources |
| `roles/compute.osLogin` | Use Google account as SSH user |
| `roles/iam.serviceAccountUser` | Impersonate service accounts |

## Cost

IAP for SSH access is **free** for:
- First 1,000 tunnel-hours per month (per project)
- Typical usage: ~720 hours/month for 24/7 access

**Billing:** After 1,000 hours: $0.01/hour (~$7.20/month if you exceed)

For a single VM accessed occasionally, you'll stay well within the free tier.

## Additional Resources

- [Google IAP Documentation](https://cloud.google.com/iap/docs)
- [IAP for SSH and TCP](https://cloud.google.com/iap/docs/using-tcp-forwarding)
- [IAP Pricing](https://cloud.google.com/iap/pricing)
- [GCP Firewall Rules](https://cloud.google.com/vpc/docs/firewalls)

## Migration Phases

### Phase 1: Enable IAP (Current)
- ✅ IAP firewall rule added
- ✅ Direct SSH still works (backup)
- ✅ Both access methods available

### Phase 2: Remove Public IP (Next)
- Remove public IP from VM
- Delete direct SSH firewall rule
- IAP becomes primary access method

See [ROADMAP.md](../ROADMAP.md) for full migration plan.

---

**Last Updated:** 2025-10-24
**Terraform Version:** >= 1.5.0
**GCP APIs Required:** `iap.googleapis.com`, `compute.googleapis.com`

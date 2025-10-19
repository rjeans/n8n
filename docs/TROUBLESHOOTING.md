# n8n Troubleshooting Guide

Common issues and solutions for the GCP n8n deployment.

## Table of Contents

1. [Terraform & GCP Authentication Issues](#terraform--gcp-authentication-issues)
2. [Infrastructure Issues](#infrastructure-issues)
3. [Docker & Container Issues](#docker--container-issues)
4. [Database Issues](#database-issues)
5. [n8n Application Issues](#n8n-application-issues)
6. [Cloudflare Tunnel Issues](#cloudflare-tunnel-issues)
7. [Performance Issues](#performance-issues)
8. [Migration Issues](#migration-issues)
9. [Backup & Restore Issues](#backup--restore-issues)

---

## Terraform & GCP Authentication Issues

### Terraform Cannot Authenticate to GCP

**Symptoms:**
- `Error: No credentials loaded`
- `Error: Attempted to load application default credentials`
- `google: could not find default credentials`

**Error Example:**
```
Error: Attempted to load application default credentials since neither
`credentials` nor `access_token` was set in the provider block. No credentials loaded.
```

**Solutions:**

#### Solution 1: Use Application Default Credentials (Quickest)

```bash
# Run this command to authenticate
gcloud auth application-default login

# This will open a browser window for you to login
# After login, try terraform again
cd infra/terraform
terraform apply
```

#### Solution 2: Verify gcloud Authentication

```bash
# Check if you're authenticated
gcloud auth list

# If not authenticated, login
gcloud auth login

# Set your project
gcloud config set project YOUR_PROJECT_ID

# Verify project is set
gcloud config get-value project

# Then authenticate for application default
gcloud auth application-default login
```

#### Solution 3: Use Service Account (Production)

```bash
# Create service account
export PROJECT_ID=$(gcloud config get-value project)

gcloud iam service-accounts create terraform \
    --display-name="Terraform Service Account"

# Grant permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"

# Create key
gcloud iam service-accounts keys create ~/terraform-gcp-key.json \
    --iam-account=terraform@${PROJECT_ID}.iam.gserviceaccount.com

# Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS=~/terraform-gcp-key.json

# Make permanent (add to shell profile)
echo 'export GOOGLE_APPLICATION_CREDENTIALS=~/terraform-gcp-key.json' >> ~/.zshrc

# Try terraform again
terraform apply
```

#### Solution 4: Specify Credentials in Terraform Provider (Not Recommended)

If you need a temporary workaround, you can specify the credentials file directly in `main.tf`:

```hcl
provider "google" {
  project     = var.project_id
  region      = var.region
  zone        = var.zone
  credentials = file("~/terraform-gcp-key.json")  # Add this line
}
```

**Note:** This is not recommended as it can expose credentials in your code. Use environment variables instead.

### Terraform Says APIs Not Enabled

**Symptoms:**
- `Error: Error creating instance: googleapi: Error 403: Access Not Configured`
- `Compute Engine API has not been used in project`

**Solutions:**

```bash
# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# Wait 1-2 minutes for APIs to activate
sleep 120

# Try terraform again
terraform apply
```

### Permission Denied Errors in Terraform

**Symptoms:**
- `Error 403: The caller does not have permission`
- `IAM permission 'compute.instances.create' denied`

**Solutions:**

```bash
# Check your current permissions
gcloud projects get-iam-policy $(gcloud config get-value project)

# If using service account, grant proper roles
export PROJECT_ID=$(gcloud config get-value project)

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"
```

### Billing Not Enabled Error

**Symptoms:**
- `Error: Project cannot access Compute Engine API`
- `Billing must be enabled`

**Solutions:**

1. Enable billing in GCP Console:
   - Go to: https://console.cloud.google.com/billing
   - Link your project to a billing account

2. Verify billing is enabled:
   ```bash
   gcloud beta billing projects describe $(gcloud config get-value project)
   ```

### Project ID Not Set

**Symptoms:**
- `Error: Required field 'project' is not set`
- Terraform asks for project_id repeatedly

**Solutions:**

```bash
# Set project in gcloud
gcloud config set project YOUR_PROJECT_ID

# Verify it's set
gcloud config get-value project

# Make sure terraform.tfvars has the project_id
cd infra/terraform
grep project_id terraform.tfvars

# If missing, add it
echo 'project_id = "YOUR_PROJECT_ID"' >> terraform.tfvars
```

---

## Infrastructure Issues

### Cannot SSH to Instance

**Symptoms:**
- Connection timeout when trying to SSH
- Permission denied errors

**Solutions:**

1. **Check instance is running:**
   ```bash
   gcloud compute instances list
   gcloud compute instances describe n8n-server --zone=us-central1-a
   ```

2. **Verify firewall rules:**
   ```bash
   gcloud compute firewall-rules list
   ```

3. **Check SSH from GCP console:**
   ```bash
   # Use browser SSH from GCP Console
   # Compute Engine → VM instances → SSH button
   ```

4. **Verify SSH key:**
   ```bash
   # Check your public key is correct
   cat ~/.ssh/id_rsa.pub

   # Verify it matches in GCP
   gcloud compute instances describe n8n-server --zone=us-central1-a --format="value(metadata.ssh-keys)"
   ```

5. **Add SSH key manually:**
   ```bash
   gcloud compute instances add-metadata n8n-server \
       --zone=us-central1-a \
       --metadata ssh-keys="ubuntu:$(cat ~/.ssh/id_rsa.pub)"
   ```

### Data Disk Not Mounted

**Symptoms:**
- `/mnt/data` directory not accessible
- Disk space not showing increased capacity

**Solutions:**

1. **Check disk attachment:**
   ```bash
   lsblk
   # Should show /dev/sdb or similar
   ```

2. **Check mount:**
   ```bash
   df -h /mnt/data
   mount | grep /mnt/data
   ```

3. **Manual mount:**
   ```bash
   # Check if disk exists
   sudo fdisk -l

   # Mount if needed
   sudo mkdir -p /mnt/data
   sudo mount /dev/sdb /mnt/data

   # Make permanent
   echo "/dev/sdb /mnt/data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
   ```

4. **Format disk (if new):**
   ```bash
   sudo mkfs.ext4 /dev/sdb
   sudo mount /dev/sdb /mnt/data
   ```

### High Costs / Unexpected Charges

**Symptoms:**
- GCP billing higher than expected

**Solutions:**

1. **Check instance type:**
   ```bash
   gcloud compute instances describe n8n-server --zone=us-central1-a --format="value(machineType)"
   ```

2. **Verify region (must be us-central1, us-east1, or us-west1 for free tier):**
   ```bash
   gcloud compute instances describe n8n-server --zone=us-central1-a --format="value(zone)"
   ```

3. **Check for unexpected resources:**
   ```bash
   gcloud compute instances list
   gcloud compute disks list
   gcloud compute addresses list
   ```

4. **Stop instance when not in use (for testing):**
   ```bash
   gcloud compute instances stop n8n-server --zone=us-central1-a
   ```

---

## Docker & Container Issues

### Docker Daemon Not Running

**Symptoms:**
- `Cannot connect to the Docker daemon` error

**Solutions:**

```bash
# Check Docker status
sudo systemctl status docker

# Start Docker
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker

# Check Docker info
docker info
```

### Permission Denied When Running Docker

**Symptoms:**
- `permission denied while trying to connect to the Docker daemon socket`

**Solutions:**

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login again
exit
# SSH back in

# Verify group membership
groups
```

### Container Fails to Start

**Symptoms:**
- Container keeps restarting
- Container exits immediately

**Solutions:**

1. **Check logs:**
   ```bash
   cd ~/n8n/docker
   docker compose logs <service-name>
   docker compose logs n8n
   docker compose logs postgres
   ```

2. **Check container status:**
   ```bash
   docker compose ps
   docker ps -a
   ```

3. **Check for port conflicts:**
   ```bash
   sudo netstat -tulpn | grep 5678
   sudo lsof -i :5678
   ```

4. **Check environment variables:**
   ```bash
   docker compose config
   # Verify all variables are set correctly
   ```

5. **Recreate containers:**
   ```bash
   docker compose down
   docker compose up -d
   ```

### Out of Disk Space

**Symptoms:**
- Containers fail to start
- `no space left on device` errors

**Solutions:**

1. **Check disk usage:**
   ```bash
   df -h
   du -sh /mnt/data/*
   ```

2. **Clean Docker resources:**
   ```bash
   # Remove unused containers
   docker container prune -f

   # Remove unused images
   docker image prune -a -f

   # Remove unused volumes (BE CAREFUL!)
   docker volume prune -f

   # Clean everything (BE CAREFUL!)
   docker system prune -a -f
   ```

3. **Clean old backups:**
   ```bash
   # Remove backups older than 30 days
   find /mnt/data/backups -mtime +30 -delete
   ```

4. **Check PostgreSQL data:**
   ```bash
   du -sh /mnt/data/postgres

   # Clean old execution data in n8n
   # (Set EXECUTIONS_DATA_PRUNE=true in .env)
   ```

---

## Database Issues

### Cannot Connect to Database

**Symptoms:**
- n8n shows database connection errors
- `ECONNREFUSED` or `connection refused` errors

**Solutions:**

1. **Check PostgreSQL is running:**
   ```bash
   docker compose ps postgres
   docker compose logs postgres
   ```

2. **Check PostgreSQL health:**
   ```bash
   docker compose exec postgres pg_isready -U n8n
   ```

3. **Verify database credentials:**
   ```bash
   # Check .env file
   grep POSTGRES ~/n8n/docker/.env

   # Test connection
   docker compose exec postgres psql -U n8n -d n8n -c "SELECT 1;"
   ```

4. **Restart database:**
   ```bash
   docker compose restart postgres
   ```

### Database Corruption

**Symptoms:**
- PostgreSQL won't start
- Errors about corrupt data

**Solutions:**

1. **Check logs:**
   ```bash
   docker compose logs postgres
   ```

2. **Restore from backup:**
   ```bash
   # Stop services
   docker compose down

   # Remove corrupt data
   sudo rm -rf /mnt/data/postgres/*

   # Start PostgreSQL
   docker compose up -d postgres

   # Restore from backup
   gunzip -c /mnt/data/backups/<timestamp>/database.sql.gz | \
       docker compose exec -T postgres psql -U n8n n8n

   # Start n8n
   docker compose up -d n8n
   ```

### Slow Database Performance

**Symptoms:**
- Workflows execute slowly
- High database CPU usage

**Solutions:**

1. **Clean old executions:**
   ```bash
   # Set in .env
   EXECUTIONS_DATA_PRUNE=true
   EXECUTIONS_DATA_MAX_AGE=168  # 7 days

   # Restart n8n
   docker compose restart n8n
   ```

2. **Manual cleanup:**
   ```bash
   docker compose exec postgres psql -U n8n -d n8n

   -- Delete old executions
   DELETE FROM execution_entity WHERE "startedAt" < NOW() - INTERVAL '30 days';

   -- Vacuum database
   VACUUM ANALYZE;
   ```

3. **Check database size:**
   ```bash
   docker compose exec postgres psql -U n8n -d n8n -c \
       "SELECT pg_size_pretty(pg_database_size('n8n'));"
   ```

---

## n8n Application Issues

### Cannot Access n8n UI

**Symptoms:**
- n8n URL not loading
- Timeout or connection refused errors

**Solutions:**

1. **Check n8n is running:**
   ```bash
   docker compose ps n8n
   docker compose logs n8n
   ```

2. **Check local access:**
   ```bash
   curl -I http://localhost:5678
   ```

3. **Check Cloudflare Tunnel:**
   ```bash
   docker compose logs cloudflared
   ```

4. **Verify DNS:**
   ```bash
   dig n8n.yourdomain.com
   nslookup n8n.yourdomain.com
   ```

5. **Check environment:**
   ```bash
   docker compose exec n8n env | grep N8N
   ```

### Workflows Not Executing

**Symptoms:**
- Manual execution works but scheduled workflows don't run
- Webhooks not triggering

**Solutions:**

1. **Check n8n logs:**
   ```bash
   docker compose logs -f n8n
   ```

2. **Verify timezone:**
   ```bash
   # Check .env file
   grep TIMEZONE ~/n8n/docker/.env

   # Should match your timezone
   ```

3. **Check webhook URL:**
   ```bash
   # Verify N8N_HOST and WEBHOOK_URL in .env
   grep N8N_HOST ~/n8n/docker/.env

   # Should be: https://n8n.yourdomain.com
   ```

4. **Restart n8n:**
   ```bash
   docker compose restart n8n
   ```

### Credentials Not Working

**Symptoms:**
- Cannot decrypt credentials
- "Invalid credentials" errors

**Solutions:**

1. **CRITICAL: Check encryption key:**
   ```bash
   # Encryption key MUST match old instance
   grep N8N_ENCRYPTION_KEY ~/n8n/docker/.env
   ```

2. **If migrating, verify key matches:**
   ```bash
   # Old key from K8s
   cat ~/migration_package/encryption_key.txt

   # New key from .env
   grep N8N_ENCRYPTION_KEY ~/n8n/docker/.env

   # These MUST be identical!
   ```

3. **Update encryption key:**
   ```bash
   # Edit .env
   nano ~/n8n/docker/.env

   # Update N8N_ENCRYPTION_KEY

   # Restart n8n
   docker compose restart n8n
   ```

**WARNING:** If encryption keys don't match, credentials cannot be recovered!

### High Memory Usage

**Symptoms:**
- n8n container using excessive memory
- System OOM (out of memory) errors

**Solutions:**

1. **Check memory usage:**
   ```bash
   docker stats
   free -h
   ```

2. **Limit executions:**
   ```bash
   # In .env, reduce concurrent executions
   EXECUTIONS_PROCESS=main
   ```

3. **Clean execution history:**
   ```bash
   EXECUTIONS_DATA_MAX_AGE=168  # Keep only 7 days
   docker compose restart n8n
   ```

4. **Upgrade instance (if necessary):**
   ```bash
   # Consider e2-small if e2-micro is insufficient
   # Update in infra/terraform/terraform.tfvars
   machine_type = "e2-small"
   ```

---

## Cloudflare Tunnel Issues

### Tunnel Not Connecting

**Symptoms:**
- `cloudflared` container running but tunnel offline
- "Connection refused" in cloudflared logs

**Solutions:**

1. **Check cloudflared logs:**
   ```bash
   docker compose logs cloudflared
   ```

2. **Verify token:**
   ```bash
   # Check .env has correct token
   grep CLOUDFLARE_TUNNEL_TOKEN ~/n8n/docker/.env

   # Token should start with "ey"
   ```

3. **Test n8n accessibility from cloudflared:**
   ```bash
   docker compose exec cloudflared wget -O- http://n8n:5678/healthz
   ```

4. **Restart cloudflared:**
   ```bash
   docker compose restart cloudflared
   ```

5. **Check Cloudflare dashboard:**
   - Go to: https://one.dash.cloudflare.com/
   - Access → Tunnels
   - Verify tunnel status

### SSL/TLS Errors

**Symptoms:**
- "Your connection is not private" warnings
- SSL certificate errors

**Solutions:**

1. **Check Cloudflare SSL settings:**
   - Cloudflare Dashboard → SSL/TLS
   - Set to "Full" or "Full (strict)"

2. **Verify DNS proxy:**
   - DNS → Records
   - Ensure orange cloud (proxied) is enabled

3. **Wait for propagation:**
   - DNS changes can take 5-15 minutes
   - Check status: `dig n8n.yourdomain.com`

### Tunnel Disconnects Frequently

**Symptoms:**
- Intermittent connection issues
- Tunnel goes offline periodically

**Solutions:**

1. **Check system resources:**
   ```bash
   htop
   docker stats
   ```

2. **Review cloudflared logs:**
   ```bash
   docker compose logs cloudflared | grep -i error
   ```

3. **Increase keepalive:**
   - Use config file instead of token
   - Set `keepAliveTimeout: 90s` in config.yml

4. **Check network connectivity:**
   ```bash
   ping -c 10 1.1.1.1
   traceroute 1.1.1.1
   ```

---

## Performance Issues

### Slow Workflow Execution

**Symptoms:**
- Workflows take longer than expected
- High latency

**Solutions:**

1. **Check system resources:**
   ```bash
   htop
   docker stats
   df -h
   ```

2. **Optimize workflows:**
   - Reduce number of nodes
   - Use batch operations
   - Implement caching

3. **Check database performance:**
   ```bash
   docker compose exec postgres psql -U n8n -d n8n -c \
       "SELECT pg_stat_statements_reset();"
   ```

4. **Consider upgrading instance:**
   - e2-micro may be insufficient for heavy workloads
   - Upgrade to e2-small or e2-medium

### High CPU Usage

**Symptoms:**
- System sluggish
- CPU at 100%

**Solutions:**

1. **Identify culprit:**
   ```bash
   htop
   docker stats
   ```

2. **Check running workflows:**
   - Review active executions in n8n UI
   - Pause problematic workflows

3. **Limit concurrent executions:**
   ```bash
   # In .env
   EXECUTIONS_PROCESS=main
   ```

### Disk I/O Issues

**Symptoms:**
- Slow database operations
- High disk wait times

**Solutions:**

1. **Check disk usage:**
   ```bash
   iostat -x 1
   df -h
   ```

2. **Upgrade disk:**
   - Consider SSD persistent disk (pd-ssd)
   - Update in Terraform: `type = "pd-ssd"`

---

## Migration Issues

### Encryption Key Mismatch

**Symptoms:**
- Cannot decrypt credentials after migration
- "Credentials are invalid" errors

**Solutions:**

**CRITICAL:** This is the most common migration issue!

```bash
# Stop n8n
docker compose stop n8n

# Verify old encryption key
cat ~/migration_package/encryption_key.txt

# Update .env with EXACT key from old instance
nano ~/n8n/docker/.env
# N8N_ENCRYPTION_KEY=<exact-key-from-old-instance>

# Start n8n
docker compose up -d n8n
```

**If keys already don't match and data is encrypted:**
- Credentials cannot be recovered
- You must restore from old instance
- Re-migrate with correct key

### Workflows Missing After Migration

**Symptoms:**
- Some or all workflows don't appear after migration

**Solutions:**

1. **Check database restoration:**
   ```bash
   docker compose exec postgres psql -U n8n -d n8n -c \
       "SELECT COUNT(*) FROM workflow_entity;"
   ```

2. **Verify database backup integrity:**
   ```bash
   # Check backup file size
   ls -lh ~/migration_package/database.sql.gz

   # Test decompression
   gunzip -t ~/migration_package/database.sql.gz
   ```

3. **Re-import database:**
   ```bash
   docker compose down
   docker compose up -d postgres
   gunzip -c ~/migration_package/database.sql.gz | \
       docker compose exec -T postgres psql -U n8n n8n
   docker compose up -d n8n
   ```

---

## Backup & Restore Issues

### Backup Script Fails

**Symptoms:**
- Backup script exits with errors
- Incomplete backups

**Solutions:**

1. **Check permissions:**
   ```bash
   ls -la /mnt/data/backups
   sudo chown -R $USER:$USER /mnt/data/backups
   ```

2. **Check disk space:**
   ```bash
   df -h /mnt/data
   ```

3. **Run backup manually:**
   ```bash
   cd ~/n8n/scripts
   ./backup.sh
   ```

4. **Check logs:**
   ```bash
   cat /var/log/n8n-backup.log
   ```

### Restore Fails

**Symptoms:**
- Database restore errors
- Data corruption after restore

**Solutions:**

1. **Verify backup integrity:**
   ```bash
   cd /mnt/data/backups/<timestamp>
   sha256sum -c checksums.txt
   ```

2. **Test backup file:**
   ```bash
   gunzip -t database.sql.gz
   ```

3. **Manual restore:**
   ```bash
   # Stop n8n
   docker compose stop n8n

   # Clear database
   docker compose exec postgres psql -U n8n -d postgres -c "DROP DATABASE n8n;"
   docker compose exec postgres psql -U n8n -d postgres -c "CREATE DATABASE n8n;"

   # Restore
   gunzip -c /mnt/data/backups/<timestamp>/database.sql.gz | \
       docker compose exec -T postgres psql -U n8n n8n

   # Start n8n
   docker compose up -d n8n
   ```

---

## General Debugging

### Collect Diagnostic Information

```bash
#!/bin/bash
# Save as: ~/n8n/scripts/diagnostic.sh

echo "=== n8n Diagnostic Report ===" > diagnostic.txt
echo "Date: $(date)" >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Docker Compose Status ===" >> diagnostic.txt
docker compose ps >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Container Logs ===" >> diagnostic.txt
docker compose logs --tail=100 >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== System Resources ===" >> diagnostic.txt
free -h >> diagnostic.txt
df -h >> diagnostic.txt
docker stats --no-stream >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Environment ===" >> diagnostic.txt
docker compose config >> diagnostic.txt
echo "" >> diagnostic.txt

echo "Report saved to: diagnostic.txt"
```

### Enable Debug Logging

```bash
# Edit .env
nano ~/n8n/docker/.env

# Set
N8N_LOG_LEVEL=debug

# Restart
docker compose restart n8n

# View logs
docker compose logs -f n8n
```

---

## Getting Help

### n8n Community
- Forum: https://community.n8n.io/
- GitHub Issues: https://github.com/n8n-io/n8n/issues

### Cloudflare Support
- Documentation: https://developers.cloudflare.com/cloudflare-one/
- Community: https://community.cloudflare.com/

### GCP Support
- Documentation: https://cloud.google.com/docs
- Stack Overflow: Tag `google-cloud-platform`

### When Asking for Help

Include:
1. Error messages (exact text)
2. Relevant logs
3. What you've tried
4. Your configuration (remove secrets!)
5. Diagnostic report output

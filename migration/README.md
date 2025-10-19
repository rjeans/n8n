# n8n Migration Guide - Kubernetes to GCP

This guide provides step-by-step instructions for migrating your n8n instance from a Kubernetes cluster to the new GCP e2-micro instance.

## Overview

**Source**: Kubernetes cluster (homelab)
**Target**: GCP e2-micro with Docker Compose
**Downtime**: Estimated 30-60 minutes

## Pre-Migration Checklist

- [ ] Access to source Kubernetes cluster
- [ ] kubectl configured and working
- [ ] GCP instance provisioned and accessible
- [ ] Docker Compose stack deployed and tested on GCP
- [ ] Cloudflare Tunnel configured
- [ ] **CRITICAL**: Encryption key from K8s instance obtained
- [ ] Backup of current n8n data completed
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified

## Critical Warning

**ENCRYPTION KEY**: Your n8n encryption key MUST match between the old and new instances. If the keys don't match, all stored credentials will be unrecoverable!

Get your current encryption key:
```bash
kubectl get secret n8n-secret -n <namespace> -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' | base64 -d
```

## Migration Steps

### Phase 1: Export from Kubernetes (30-45 minutes)

#### 1.1 Identify Your n8n Resources

```bash
# Find your n8n namespace
kubectl get namespaces | grep n8n

# List n8n resources
kubectl get all -n <namespace>

# Find the n8n pod name
kubectl get pods -n <namespace> | grep n8n
```

#### 1.2 Export Configuration

```bash
# Export encryption key (CRITICAL!)
kubectl get secret n8n-secret -n <namespace> -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' | base64 -d > encryption_key.txt

# Export all environment variables
kubectl get deployment n8n -n <namespace> -o yaml > n8n-deployment.yaml

# Review environment variables
kubectl exec -n <namespace> <n8n-pod> -- env | grep N8N_
```

#### 1.3 Export Workflows and Credentials

Option A: Using n8n CLI (Recommended)
```bash
# Port forward to n8n
kubectl port-forward -n <namespace> svc/n8n 5678:5678 &

# Export workflows using n8n CLI or API
# Install n8n CLI locally if needed: npm install -g n8n

# Export all workflows
curl -u admin:password http://localhost:5678/api/v1/workflows > workflows_export.json

# Export credentials (will be encrypted)
curl -u admin:password http://localhost:5678/api/v1/credentials > credentials_export.json
```

Option B: Direct Database Export (More Complete)
```bash
# Run the export script
cd migration
./export-k8s-data.sh
```

#### 1.4 Backup PostgreSQL Database

```bash
# Find PostgreSQL pod
kubectl get pods -n <namespace> | grep postgres

# Export database
kubectl exec -n <namespace> <postgres-pod> -- pg_dump -U n8n n8n > n8n_database_backup.sql

# Verify backup
ls -lh n8n_database_backup.sql
head -n 50 n8n_database_backup.sql

# Compress for transfer
gzip n8n_database_backup.sql
```

#### 1.5 Create Migration Package

```bash
# Create migration directory
mkdir -p migration_package
cd migration_package

# Copy all exports
cp ../encryption_key.txt .
cp ../workflows_export.json .
cp ../credentials_export.json .
cp ../n8n_database_backup.sql.gz .
cp ../n8n-deployment.yaml .

# Create checksum file
sha256sum * > checksums.txt

# Create archive
cd ..
tar -czf migration_package_$(date +%Y%m%d_%H%M%S).tar.gz migration_package/
```

### Phase 2: Prepare GCP Instance (15-20 minutes)

#### 2.1 Transfer Migration Package

```bash
# From your local machine
export GCP_IP="<your-gcp-instance-ip>"
export SSH_USER="ubuntu"

# Transfer migration package
scp migration_package_*.tar.gz ${SSH_USER}@${GCP_IP}:~/

# SSH to instance
ssh ${SSH_USER}@${GCP_IP}
```

#### 2.2 Extract and Verify

```bash
# On GCP instance
tar -xzf migration_package_*.tar.gz
cd migration_package

# Verify checksums
sha256sum -c checksums.txt

# View encryption key
cat encryption_key.txt
```

#### 2.3 Update Environment Configuration

```bash
# Navigate to docker directory
cd ~/n8n/docker

# Update .env file with encryption key from old instance
# CRITICAL: Use the EXACT key from encryption_key.txt
nano .env

# Update these values:
# N8N_ENCRYPTION_KEY=<value-from-encryption_key.txt>
# N8N_HOST=<your-new-domain>
# Other environment variables as needed
```

### Phase 3: Import to GCP Instance (20-30 minutes)

#### 3.1 Stop New n8n Instance

```bash
cd ~/n8n/docker
docker-compose down
```

#### 3.2 Restore Database

```bash
# Decompress backup
cd ~/migration_package
gunzip n8n_database_backup.sql.gz

# Copy to PostgreSQL container location
sudo mkdir -p /mnt/data/backups
sudo cp n8n_database_backup.sql /mnt/data/backups/

# Start only PostgreSQL
cd ~/n8n/docker
docker-compose up -d postgres

# Wait for PostgreSQL to be ready
docker-compose logs -f postgres
# Look for: "database system is ready to accept connections"

# Restore database
docker exec -i n8n-postgres psql -U n8n -d n8n < /mnt/data/backups/n8n_database_backup.sql

# Verify restoration
docker exec -i n8n-postgres psql -U n8n -d n8n -c "\dt"
docker exec -i n8n-postgres psql -U n8n -d n8n -c "SELECT COUNT(*) FROM workflow_entity;"
```

#### 3.3 Verify Encryption Key

```bash
# CRITICAL CHECK: Verify encryption key in .env matches the old instance
grep N8N_ENCRYPTION_KEY ~/n8n/docker/.env
cat ~/migration_package/encryption_key.txt

# These MUST match EXACTLY!
```

#### 3.4 Start n8n

```bash
cd ~/n8n/docker
docker-compose up -d

# Monitor startup
docker-compose logs -f n8n

# Wait for: "Editor is now accessible via:"
```

#### 3.5 Verify Migration

```bash
# Check all containers are running
docker-compose ps

# Test n8n accessibility
curl -I http://localhost:5678

# Check via Cloudflare domain
curl -I https://n8n.yourdomain.com
```

### Phase 4: Validation (15-20 minutes)

#### 4.1 Login and Verify Workflows

1. Navigate to https://n8n.yourdomain.com
2. Login with your credentials
3. Verify all workflows are present
4. Check workflow counts match old instance
5. Open several workflows to verify they load correctly

#### 4.2 Test Credentials

```bash
# In n8n UI:
# 1. Go to Settings -> Credentials
# 2. Verify all credentials are listed
# 3. Open a few credentials to verify they decrypt correctly
# 4. If you see decryption errors, STOP - encryption key mismatch!
```

#### 4.3 Test Workflow Execution

1. Select a simple workflow
2. Execute manually
3. Verify successful execution
4. Check execution history
5. Test a webhook-based workflow if applicable

#### 4.4 Update Webhooks (If Applicable)

If you use webhooks, you'll need to update external systems:

```bash
# Old webhook URL format:
# https://old-domain.com/webhook/<webhook-id>

# New webhook URL format:
# https://n8n.yourdomain.com/webhook/<webhook-id>

# Update in external systems:
# - GitHub webhooks
# - Stripe webhooks
# - Other services sending webhooks
```

### Phase 5: Cutover (5-10 minutes)

#### 5.1 Pre-Cutover Checklist

- [ ] All workflows visible and accessible
- [ ] All credentials decrypt successfully
- [ ] Test workflow executions successful
- [ ] Cloudflare Tunnel connected
- [ ] HTTPS working correctly
- [ ] Monitoring in place

#### 5.2 Stop Old K8s Instance

```bash
# On your local machine with kubectl access
kubectl scale deployment n8n -n <namespace> --replicas=0

# Verify stopped
kubectl get pods -n <namespace> | grep n8n
```

#### 5.3 Update DNS/Routing

If you're using a domain that pointed to your K8s cluster:

1. Update DNS to point to new Cloudflare Tunnel
2. Wait for DNS propagation (check with: `dig n8n.yourdomain.com`)

#### 5.4 Monitor New Instance

```bash
# Monitor logs for any errors
docker-compose logs -f

# Check resource usage
docker stats

# Monitor system resources
htop
df -h
```

### Phase 6: Post-Migration (24-48 hours)

#### 6.1 Monitoring Checklist

- [ ] Monitor for 24 hours minimum
- [ ] Check all scheduled workflows trigger correctly
- [ ] Verify webhook endpoints receiving data
- [ ] Monitor error logs
- [ ] Check system resource usage
- [ ] Verify backup automation working

#### 6.2 Performance Validation

```bash
# Check workflow execution times
# In n8n UI: Executions tab -> Compare execution times

# Monitor resource usage
docker stats --no-stream

# Check disk usage
df -h /mnt/data
```

#### 6.3 Backup Validation

```bash
# Run manual backup
cd ~/n8n/scripts
./backup.sh

# Verify backup created
ls -lh /mnt/data/backups/
```

## Rollback Procedure

If you encounter critical issues, you can rollback to the K8s instance:

### Rollback Steps

1. **Stop GCP instance**:
   ```bash
   docker-compose down
   ```

2. **Restart K8s deployment**:
   ```bash
   kubectl scale deployment n8n -n <namespace> --replicas=1
   ```

3. **Verify K8s instance running**:
   ```bash
   kubectl get pods -n <namespace>
   kubectl logs -n <namespace> <n8n-pod>
   ```

4. **Update DNS/routing back to K8s** (if changed)

5. **Investigate issues** before attempting migration again

## Troubleshooting

### Credentials Won't Decrypt

**Cause**: Encryption key mismatch
**Solution**:
```bash
# Verify encryption keys match
grep N8N_ENCRYPTION_KEY ~/n8n/docker/.env
cat ~/migration_package/encryption_key.txt

# Update .env with correct key
nano ~/n8n/docker/.env

# Restart n8n
docker-compose restart n8n
```

### Database Restoration Fails

**Cause**: Version mismatch or corrupted backup
**Solution**:
```bash
# Check PostgreSQL version
docker exec n8n-postgres psql --version

# Try restoring with --clean --if-exists flags
docker exec -i n8n-postgres psql -U n8n -d postgres -c "DROP DATABASE IF EXISTS n8n;"
docker exec -i n8n-postgres psql -U n8n -d postgres -c "CREATE DATABASE n8n;"
docker exec -i n8n-postgres psql -U n8n -d n8n < /mnt/data/backups/n8n_database_backup.sql
```

### Workflows Not Appearing

**Cause**: Database not restored or n8n version incompatibility
**Solution**:
```bash
# Verify database has data
docker exec n8n-postgres psql -U n8n -d n8n -c "SELECT COUNT(*) FROM workflow_entity;"

# Check n8n version
docker exec n8n n8n --version

# Check n8n logs for migration errors
docker-compose logs n8n | grep -i error
```

### Cloudflare Tunnel Not Connecting

**Cause**: Incorrect token or configuration
**Solution**:
```bash
# Check cloudflared logs
docker-compose logs cloudflared

# Verify tunnel token in .env
grep CLOUDFLARE_TUNNEL_TOKEN ~/n8n/docker/.env

# Restart cloudflared
docker-compose restart cloudflared
```

### High Memory Usage on e2-micro

**Cause**: e2-micro has limited resources (1GB RAM)
**Solution**:
```bash
# Check current usage
free -h
docker stats --no-stream

# Optimize PostgreSQL memory settings
# Edit docker-compose.yml and add to postgres service:
# environment:
#   POSTGRES_SHARED_BUFFERS: "128MB"
#   POSTGRES_EFFECTIVE_CACHE_SIZE: "256MB"

# Consider upgrading to e2-small if needed
```

## Data Verification Checklist

After migration, verify:

- [ ] All workflows present (count matches)
- [ ] All credentials accessible
- [ ] Execution history preserved
- [ ] Manual workflow execution works
- [ ] Scheduled workflows trigger correctly
- [ ] Webhook workflows receive data
- [ ] No error spikes in logs
- [ ] System resources acceptable
- [ ] Backups running automatically
- [ ] HTTPS access working
- [ ] Domain resolving correctly

## Post-Migration Cleanup

After successful validation (1-2 weeks):

```bash
# On GCP instance (keep for now)
# - Keep migration package for reference
# - Backups are stored in /mnt/data/backups

# On K8s cluster (after 2 weeks of stable operation)
kubectl delete deployment n8n -n <namespace>
kubectl delete service n8n -n <namespace>
kubectl delete pvc n8n-data -n <namespace>
# etc.
```

## Support

For issues during migration:
- Check logs: `docker-compose logs`
- Review troubleshooting section above
- Consult n8n documentation: https://docs.n8n.io
- Review TROUBLESHOOTING.md in docs folder

## Migration Timing Recommendations

**Best time to migrate**:
- Low traffic period
- Weekend or after hours
- Not during critical business operations
- Allow extra time for unexpected issues

**Estimated timeline**:
- Preparation: 1-2 hours
- Export: 30-45 minutes
- Transfer & Import: 30-45 minutes
- Validation: 20-30 minutes
- **Total: 2-4 hours**

**Plus**:
- Monitoring period: 24-48 hours
- Full validation: 1-2 weeks

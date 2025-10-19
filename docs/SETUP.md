# n8n GCP Setup Guide

Complete setup instructions for deploying n8n on Google Cloud Platform with Docker Compose and Cloudflare Tunnel.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: GCP Infrastructure](#phase-1-gcp-infrastructure)
3. [Phase 2: Server Setup](#phase-2-server-setup)
4. [Phase 3: Application Deployment](#phase-3-application-deployment)
5. [Phase 4: Cloudflare Tunnel](#phase-4-cloudflare-tunnel)
6. [Phase 5: Verification](#phase-5-verification)
7. [Post-Deployment](#post-deployment)

---

## Prerequisites

### Required Accounts
- Google Cloud Platform account
- Cloudflare account with domain
- GitHub account (optional, for repository)

### Required Tools (Local Machine)
```bash
# Terraform
brew install terraform  # macOS
# or download from: https://www.terraform.io/downloads

# Google Cloud SDK
brew install google-cloud-sdk  # macOS
# or download from: https://cloud.google.com/sdk/docs/install

# Git
brew install git  # macOS
```

### Required Information
- [ ] GCP Project ID
- [ ] SSH Public Key
- [ ] Domain name (e.g., yourdomain.com)
- [ ] Cloudflare account credentials

---

## Phase 1: GCP Infrastructure

### 1.1 Setup GCP Project

```bash
# Login to GCP
gcloud auth login

# Create a new project (or use existing)
gcloud projects create n8n-production --name="n8n Production"

# Set as active project
gcloud config set project n8n-production

# Enable billing (required for Compute Engine)
# Do this in console: https://console.cloud.google.com/billing

# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

### 1.2 Setup Terraform Authentication

You have two options for authenticating Terraform with GCP:

#### Option A: Application Default Credentials (Quick Setup)

**Recommended for getting started quickly:**

```bash
# Authenticate with your Google account
gcloud auth application-default login
```

This will:
- Open a browser window for you to login with your Google account
- Store credentials that Terraform can use automatically
- Work immediately for local development

**Pros:**
- Quick and easy setup
- No service account management
- Good for personal projects and testing

**Cons:**
- Uses your personal Google credentials
- Not recommended for production/team environments

#### Option B: Service Account (Production Recommended)

**Recommended for production deployments:**

```bash
# Set your project ID variable
export PROJECT_ID="n8n-production"

# Create service account for Terraform
gcloud iam service-accounts create terraform \
    --display-name="Terraform Service Account" \
    --description="Service account for Terraform infrastructure management"

# Grant necessary permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"

# Create and download key
gcloud iam service-accounts keys create ~/terraform-gcp-key.json \
    --iam-account=terraform@${PROJECT_ID}.iam.gserviceaccount.com

# Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS=~/terraform-gcp-key.json

# Add to shell profile for persistence (choose your shell)
echo 'export GOOGLE_APPLICATION_CREDENTIALS=~/terraform-gcp-key.json' >> ~/.zshrc   # macOS
# or
echo 'export GOOGLE_APPLICATION_CREDENTIALS=~/terraform-gcp-key.json' >> ~/.bashrc  # Linux
```

**Pros:**
- More secure and controlled access
- Recommended for production
- Better for team environments
- Easier to rotate credentials

**Cons:**
- More setup steps
- Need to manage service account keys

#### Verify Authentication

After choosing either option, verify your authentication:

```bash
# Check authentication status
gcloud auth list

# Check current project
gcloud config get-value project

# Test Terraform can authenticate
cd infra/terraform
terraform init
```

If you see an error like `No credentials loaded`, run:
```bash
gcloud auth application-default login
```

### 1.3 Configure Terraform

```bash
# Clone repository (or navigate to your n8n directory)
cd ~/n8n

# Navigate to Terraform directory
cd infra/terraform

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

Update these values in `terraform.tfvars`:
```hcl
project_id = "n8n-production"
region     = "us-central1"  # Free tier eligible
zone       = "us-central1-a"

instance_name = "n8n-server"
machine_type  = "e2-micro"

ssh_user       = "ubuntu"
ssh_public_key = "ssh-rsa AAAAB3... your-public-key"

# Optional: Restrict SSH to your IP
ssh_source_ranges = ["YOUR_IP/32"]
```

### 1.4 Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Apply configuration
terraform apply

# Note the outputs
# Save the external IP and SSH command
```

After successful deployment, you should see output like:
```
external_ip = "34.123.45.67"
ssh_command = "ssh -i ~/.ssh/id_rsa ubuntu@34.123.45.67"
```

**Save these values!**

---

## Phase 2: Server Setup

### 2.1 Connect to Instance

```bash
# Use the SSH command from Terraform output
ssh -i ~/.ssh/id_rsa ubuntu@<EXTERNAL_IP>

# Or use gcloud
gcloud compute ssh n8n-server --zone=us-central1-a
```

### 2.2 Update System

```bash
# Update package lists
sudo apt update

# Upgrade packages
sudo apt upgrade -y

# Install basic utilities
sudo apt install -y curl wget git vim htop
```

### 2.3 Install Docker

```bash
# Install Docker using official script
curl -fsSL https://get.docker.com | sh

# Add user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose plugin
sudo apt install -y docker-compose-plugin

# Logout and login again for group changes
exit
# SSH back in
```

Verify Docker installation:
```bash
docker --version
docker compose version
```

### 2.4 Verify Data Disk

```bash
# Check if data disk is mounted
df -h /mnt/data

# Should show something like:
# /dev/sdb  20G  45M  19G  1% /mnt/data

# If not mounted, check Terraform startup script logs
sudo journalctl -u google-startup-scripts
```

---

## Phase 3: Application Deployment

### 3.1 Clone Repository

```bash
# Clone your repository (if using git)
git clone https://github.com/yourusername/n8n.git
cd n8n

# Or create directory structure manually
mkdir -p ~/n8n
cd ~/n8n
```

### 3.2 Configure Environment

```bash
# Navigate to docker directory
cd docker

# Copy example environment file
cp .env.example .env

# Edit with your values
nano .env
```

**Critical values to update:**

```bash
# Database
POSTGRES_PASSWORD=<secure-random-password>

# n8n Domain
N8N_HOST=n8n.yourdomain.com

# n8n Authentication
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=<secure-password>

# CRITICAL: Encryption Key
# Generate with: openssl rand -base64 32
N8N_ENCRYPTION_KEY=<32-character-key>

# Cloudflare Tunnel (we'll add this in next phase)
CLOUDFLARE_TUNNEL_TOKEN=<will-add-later>

# Timezone
GENERIC_TIMEZONE=America/New_York
TZ=America/New_York
```

**Generate secure passwords:**
```bash
# Generate random password
openssl rand -base64 24

# Generate encryption key
openssl rand -base64 32
```

### 3.3 Setup Data Directories

```bash
# Create necessary directories
sudo mkdir -p /mnt/data/n8n
sudo mkdir -p /mnt/data/postgres
sudo mkdir -p /mnt/data/backups

# Set ownership
sudo chown -R $USER:$USER /mnt/data/n8n
sudo chown -R $USER:$USER /mnt/data/backups

# PostgreSQL needs specific user
sudo chown -R 999:999 /mnt/data/postgres
sudo chmod -R 700 /mnt/data/postgres
```

### 3.4 Initial Deployment (Without Cloudflared)

For initial testing, we'll deploy without Cloudflare Tunnel:

```bash
cd ~/n8n/docker

# Start only n8n and postgres
docker compose up -d postgres n8n

# Wait for services to start
sleep 30

# Check status
docker compose ps

# View logs
docker compose logs -f
```

Look for: `Editor is now accessible via: http://localhost:5678/`

### 3.5 Test Local Access

```bash
# Test from server
curl -I http://localhost:5678

# Should return: HTTP/1.1 200 OK
```

---

## Phase 4: Cloudflare Tunnel

### 4.1 Create Tunnel in Cloudflare

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Access → Tunnels**
3. Click **Create a tunnel**
4. Select **Cloudflared** connector
5. Name it: `n8n-tunnel`
6. **Save the tunnel token** (starts with `ey...`)

### 4.2 Configure Tunnel

In the Cloudflare dashboard:

**Public Hostname:**
- Subdomain: `n8n` (or your choice)
- Domain: `yourdomain.com`
- Service Type: `HTTP`
- URL: `http://n8n:5678`

**Save** the configuration.

### 4.3 Add DNS Record

Cloudflare should automatically create a CNAME record:
- Type: `CNAME`
- Name: `n8n`
- Target: `<tunnel-id>.cfargotunnel.com`
- Proxy: ✓ (orange cloud)

Verify in **DNS → Records** section.

### 4.4 Update Environment

Back on your GCP instance:

```bash
# Edit .env file
nano ~/n8n/docker/.env

# Add your tunnel token
CLOUDFLARE_TUNNEL_TOKEN=eyJh...your-token-here
```

### 4.5 Deploy Cloudflared

```bash
cd ~/n8n/docker

# Start cloudflared
docker compose up -d cloudflared

# Check status
docker compose ps

# View logs
docker compose logs -f cloudflared
```

Look for: `Registered tunnel connection`

---

## Phase 5: Verification

### 5.1 Check All Services

```bash
cd ~/n8n/docker

# All services should be "Up"
docker compose ps

# Should show:
# n8n-postgres    Up
# n8n             Up
# cloudflared     Up
```

### 5.2 Test External Access

```bash
# From your local machine or browser
curl -I https://n8n.yourdomain.com

# Should return: HTTP/2 200
```

### 5.3 Login to n8n

1. Navigate to: `https://n8n.yourdomain.com`
2. Login with credentials from `.env`:
   - Username: `N8N_BASIC_AUTH_USER`
   - Password: `N8N_BASIC_AUTH_PASSWORD`

### 5.4 Create Test Workflow

1. Create a simple workflow
2. Execute it manually
3. Verify execution succeeds

---

## Post-Deployment

### Setup Automated Backups

```bash
# Test backup script
cd ~/n8n/scripts
./backup.sh

# Setup cron for daily backups
crontab -e

# Add this line (daily at 2 AM)
0 2 * * * /home/ubuntu/n8n/scripts/backup.sh >> /var/log/n8n-backup.log 2>&1
```

### Setup Monitoring

```bash
# Create simple health check script
cat > ~/n8n/scripts/health-check.sh <<'EOF'
#!/bin/bash
if ! curl -sf http://localhost:5678/healthz > /dev/null; then
    echo "n8n is down!" | mail -s "n8n Alert" your@email.com
fi
EOF

chmod +x ~/n8n/scripts/health-check.sh

# Add to cron (every 5 minutes)
crontab -e
*/5 * * * * /home/ubuntu/n8n/scripts/health-check.sh
```

### Enable Automatic Security Updates

```bash
# Install unattended-upgrades
sudo apt install -y unattended-upgrades

# Enable automatic security updates
sudo dpkg-reconfigure -plow unattended-upgrades
```

### Configure Log Rotation

```bash
# Docker logs can grow large
cat > ~/n8n/docker/docker-compose.override.yml <<EOF
version: '3.8'

services:
  n8n:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  postgres:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  cloudflared:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

# Restart to apply
cd ~/n8n/docker
docker compose up -d
```

### Setup Watchtower (Optional Auto-updates)

```bash
# Enable watchtower profile
cd ~/n8n/docker
docker compose --profile autoupdate up -d

# Watchtower will check for updates daily
# and automatically update containers with the label
```

---

## Useful Commands

### Docker Management

```bash
# View all services
docker compose ps

# View logs
docker compose logs -f

# Restart service
docker compose restart n8n

# Stop all services
docker compose down

# Update images and restart
docker compose pull && docker compose up -d
```

### Database Management

```bash
# Connect to database
docker compose exec postgres psql -U n8n n8n

# Backup database
docker compose exec -T postgres pg_dump -U n8n n8n > backup.sql

# Restore database
docker compose exec -T postgres psql -U n8n n8n < backup.sql

# Check database size
docker compose exec postgres psql -U n8n -d n8n -c "SELECT pg_size_pretty(pg_database_size('n8n'));"
```

### System Monitoring

```bash
# Check disk usage
df -h /mnt/data

# Check memory
free -h

# Check container resources
docker stats

# View system logs
sudo journalctl -f
```

### Cloudflare Tunnel

```bash
# Check tunnel status
docker compose logs cloudflared

# Restart tunnel
docker compose restart cloudflared

# Test tunnel connectivity
docker compose exec cloudflared cloudflared tunnel info
```

---

## Security Recommendations

### Firewall (Optional)

```bash
# Install UFW
sudo apt install -y ufw

# Allow SSH
sudo ufw allow 22/tcp

# Enable firewall
sudo ufw enable

# Status
sudo ufw status
```

Note: We don't need to allow ports 80/443 since Cloudflare Tunnel handles ingress.

### SSH Hardening

```bash
# Disable password authentication
sudo nano /etc/ssh/sshd_config

# Set these values:
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes

# Restart SSH
sudo systemctl restart sshd
```

### Fail2Ban (Brute Force Protection)

```bash
# Install fail2ban
sudo apt install -y fail2ban

# Enable for SSH
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check status
sudo fail2ban-client status sshd
```

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

---

## Next Steps

1. **Configure n8n workflows** - Start creating your automation
2. **Setup webhooks** - Configure external services
3. **Enable notifications** - Get alerts for workflow failures
4. **Backup validation** - Test restore procedure
5. **Documentation** - Document your workflows

---

## Support Resources

- n8n Documentation: https://docs.n8n.io/
- n8n Community Forum: https://community.n8n.io/
- Cloudflare Tunnel Docs: https://developers.cloudflare.com/cloudflare-one/
- GCP Documentation: https://cloud.google.com/docs

---

## Maintenance Schedule

**Daily:**
- Automated backups (via cron)
- Health checks (via cron)

**Weekly:**
- Review logs for errors
- Check disk usage
- Review backup integrity

**Monthly:**
- Update Docker images
- Review security patches
- Test restore procedure
- Clean old backups

**Quarterly:**
- Full system audit
- Review access logs
- Update documentation
- Performance optimization

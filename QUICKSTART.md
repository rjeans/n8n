# n8n GCP Migration - Quick Start Guide

Fast-track guide for experienced users. For detailed instructions, see [docs/SETUP.md](docs/SETUP.md).

## TL;DR

1. **Provision GCP Instance**
2. **Deploy Docker Stack**
3. **Setup Cloudflare Tunnel**
4. **Migrate Data** (if applicable)
5. **Verify & Go Live**

---

## Prerequisites

- GCP account with billing enabled
- Cloudflare account with domain
- Terraform & gcloud CLI installed
- SSH key generated

---

## Step 1: Infrastructure (10 min)

```bash
# Setup GCP Authentication
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Authenticate Terraform (choose one option)

# Option A: Quick setup (recommended for getting started)
gcloud auth application-default login

# Option B: Service account (production recommended)
# See docs/SETUP.md for detailed service account setup

# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# Configure Terraform
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Update with your values (project_id, ssh_public_key, etc.)

# Deploy infrastructure
terraform init
terraform validate
terraform plan
terraform apply

# Note the external IP
terraform output external_ip
```

---

## Step 2: Deploy with Ansible (5 min - RECOMMENDED)

```bash
# Install Ansible
pip3 install ansible

# Configure inventory
cd infra/ansible
cp inventory.ini.example inventory.ini
nano inventory.ini  # Add your instance IP from terraform output

# Create vault for secrets
ansible-vault create vault.yml
# Add your secrets (see vault.yml.example for structure):
#   n8n_encryption_key: $(openssl rand -base64 32)
#   postgres_password: <secure-password>
#   n8n_basic_auth_password: <secure-password>
#   cloudflare_tunnel_token: <your-token>

# Deploy everything (system setup, Docker, n8n, backups)
ansible-playbook playbook.yml --ask-vault-pass

# Skip to Step 5 - Verify
```

See [infra/ansible/README.md](infra/ansible/README.md) for details.

---

## Step 3: Manual Deployment (Alternative to Ansible)

**Only if not using Ansible above**

```bash
# SSH to instance
ssh ubuntu@<EXTERNAL_IP>

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo apt install -y docker-compose-plugin

# Logout and login again
exit
ssh ubuntu@<EXTERNAL_IP>

# Clone repository
git clone <your-repo> n8n
cd n8n/docker

# Configure environment
cp .env.example .env
nano .env  # Update all CHANGE_THIS values

# Generate encryption key
openssl rand -base64 32

# Setup data directories
sudo mkdir -p /mnt/data/{n8n,postgres,backups}
sudo chown -R $USER:$USER /mnt/data/n8n /mnt/data/backups
sudo chown -R 999:999 /mnt/data/postgres
sudo chmod 700 /mnt/data/postgres

# Start PostgreSQL and n8n
docker compose up -d postgres n8n

# Check status
docker compose ps
docker compose logs -f
```

---

## Step 4: Cloudflare Tunnel (if not using Ansible - 10 min)

```bash
# 1. Go to: https://one.dash.cloudflare.com/
# 2. Access → Tunnels → Create tunnel
# 3. Name: n8n-tunnel
# 4. Copy the tunnel token

# 5. Configure public hostname:
#    - Subdomain: n8n
#    - Domain: yourdomain.com
#    - Service: http://n8n:5678

# 6. Add token to .env
nano ~/n8n/docker/.env
# CLOUDFLARE_TUNNEL_TOKEN=eyJh...

# 7. Start tunnel
docker compose up -d cloudflared

# 8. Verify
docker compose logs cloudflared
```

---

## Step 5: Verify (5 min)

```bash
# Check all services
docker compose ps

# Test access
curl -I https://n8n.yourdomain.com

# Login
# Open: https://n8n.yourdomain.com
# Use credentials from .env file
```

---

## Post-Deployment

### Setup Backups

```bash
# Test backup
cd ~/n8n/scripts
./backup.sh

# Schedule daily backups
crontab -e
# Add: 0 2 * * * /home/ubuntu/n8n/scripts/backup.sh
```

### Enable Auto-Updates (Optional)

```bash
cd ~/n8n/docker
docker compose --profile autoupdate up -d
```

---

## Common Commands

```bash
# View logs
docker compose logs -f

# Restart service
docker compose restart n8n

# Update images
docker compose pull && docker compose up -d

# Backup
~/n8n/scripts/backup.sh

# Check status
docker compose ps
docker stats
df -h /mnt/data
```

---

## Troubleshooting

### Terraform authentication error
```bash
# Error: No credentials loaded
# Fix: Run application default login
gcloud auth application-default login

# Verify authentication
gcloud auth list
gcloud config get-value project
```

### Cannot access n8n
```bash
docker compose logs n8n
docker compose logs cloudflared
curl -I http://localhost:5678
```

### Database issues
```bash
docker compose logs postgres
docker compose exec postgres pg_isready -U n8n
```

### Disk space
```bash
df -h
docker system prune -a
```

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed solutions.

---

## Estimated Time

- **With Ansible**: 20-30 minutes (recommended)
- **Manual deployment**: 45 minutes
- **With migration**: 2-3 hours
- Plus 24h monitoring

---

## Important Notes

⚠️ **Encryption Key**: Keep your N8N_ENCRYPTION_KEY secure and consistent!

⚠️ **Backups**: Test restore procedure before going live

⚠️ **Monitoring**: Monitor for 24-48 hours before decommissioning old instance

⚠️ **Costs**: Verify free tier eligibility (us-central1/east1/west1, e2-micro)

---

## Resources

- **Full Setup Guide**: [docs/SETUP.md](docs/SETUP.md)
- **Troubleshooting**: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- **Security Guide**: [docs/SECURITY.md](docs/SECURITY.md)
- **Roadmap**: [ROADMAP.md](ROADMAP.md)

---

## Support

- n8n Docs: https://docs.n8n.io/
- Cloudflare Tunnel: https://developers.cloudflare.com/cloudflare-one/
- GCP Docs: https://cloud.google.com/docs

Good luck! 🚀

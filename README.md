# n8n GCP Migration - Infrastructure as Code

This repository contains all the infrastructure-as-code and deployment automation for migrating an n8n instance from a homelab Kubernetes cluster to a Google Cloud Platform (GCP) e2-micro instance using Docker Compose and Cloudflare Tunnel.

## Architecture Overview

```
┌─────────────────┐
│   Cloudflare    │
│     Tunnel      │
└────────┬────────┘
         │ (encrypted tunnel)
         │
┌────────▼────────────────────────┐
│  GCP e2-micro Instance          │
│  ┌──────────────────────────┐  │
│  │  Docker Compose Stack    │  │
│  │  ┌────────────────────┐  │  │
│  │  │  n8n Container     │  │  │
│  │  └────────────────────┘  │  │
│  │  ┌────────────────────┐  │  │
│  │  │  PostgreSQL        │  │  │
│  │  └────────────────────┘  │  │
│  │  ┌────────────────────┐  │  │
│  │  │  cloudflared       │  │  │
│  │  └────────────────────┘  │  │
│  └──────────────────────────┘  │
└─────────────────────────────────┘
```

### Key Features

- **Infrastructure as Code**: Complete Terraform configuration for GCP provisioning
- **Container Orchestration**: Docker Compose for simple, reliable deployments
- **Secure Ingress**: Cloudflare Tunnel (no exposed ports, no firewall management)
- **Free Tier Eligible**: Uses GCP e2-micro instance (within free tier limits)
- **Automated Migration**: Scripts to migrate from Kubernetes to GCP
- **Persistent Storage**: Docker volumes for database and n8n data

## Project Structure

```
.
├── README.md                    # This file
├── ROADMAP.md                   # Implementation roadmap and progress
├── infra/
│   ├── terraform/              # GCP infrastructure provisioning
│   │   ├── main.tf             # Main Terraform configuration
│   │   ├── variables.tf        # Input variables
│   │   ├── outputs.tf          # Output values
│   │   └── terraform.tfvars.example  # Example variables file
│   └── ansible/                # Optional server configuration automation
│       └── playbook.yml        # Ansible playbook for server setup
├── docker/
│   ├── docker-compose.yml      # n8n stack definition
│   ├── .env.example            # Environment variables template
│   └── cloudflared/
│       └── config.yml          # Cloudflare Tunnel configuration
├── scripts/
│   ├── setup-gcp.sh            # Automated GCP setup and authentication
│   ├── deploy.sh               # Main deployment script
│   ├── backup.sh               # Backup automation
│   ├── migrate-from-k8s.sh     # Migration helper from K8s
│   └── setup-cloudflared.sh    # Cloudflare Tunnel setup
├── migration/
│   ├── README.md               # Migration guide
│   └── export-k8s-data.sh      # Export data from K8s cluster
└── docs/
    ├── SETUP.md                # Complete setup instructions
    └── TROUBLESHOOTING.md      # Common issues and solutions
```

## Quick Start

### Prerequisites

- Google Cloud Platform account
- `gcloud` CLI installed and configured
- Terraform >= 1.5.0
- Docker and Docker Compose (for local testing)
- Cloudflare account with domain
- Access to existing n8n K8s cluster (for migration)

### 1. Clone and Configure

```bash
# Clone this repository
git clone <your-repo-url>
cd n8n
```

### 2. Setup GCP (Automated)

**Option A: Automated Setup (Recommended)**

```bash
# Run the automated GCP setup script
./scripts/setup-gcp.sh
```

This script will:
- Authenticate with GCP
- Setup/select your project
- Enable required APIs
- Configure Terraform authentication (choose ADC or Service Account)
- Create terraform.tfvars with your project details

**Option B: Manual Setup**

```bash
# Authenticate with GCP
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default login

# Enable APIs
gcloud services enable compute.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# Configure Terraform
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit with your values
vim terraform.tfvars
```

See [docs/SETUP.md](docs/SETUP.md) for detailed authentication options.

### 3. Provision Infrastructure

```bash
cd infra/terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply configuration
terraform apply
```

### 4. Deploy n8n Stack

```bash
# SSH to the instance (output from Terraform)
ssh -i ~/.ssh/id_rsa user@<instance-ip>

# Clone this repo on the instance
git clone <your-repo-url>
cd n8n

# Setup environment
cp docker/.env.example docker/.env
# Edit .env with your values

# Deploy
cd docker
docker-compose up -d
```

### 5. Setup Cloudflare Tunnel

```bash
# Run setup script
cd scripts
./setup-cloudflared.sh
```

### 6. Migrate from K8s (Optional)

```bash
# On your local machine with K8s access
cd migration
./export-k8s-data.sh

# Transfer data to GCP instance
# Follow migration/README.md for detailed steps

# On GCP instance
cd scripts
./migrate-from-k8s.sh
```

## Documentation

- [ROADMAP.md](ROADMAP.md) - Implementation roadmap and progress tracking
- [docs/SETUP.md](docs/SETUP.md) - Detailed setup instructions
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [migration/README.md](migration/README.md) - Step-by-step migration guide

## Configuration

### Terraform Variables

Key variables to configure in `infra/terraform/terraform.tfvars`:

- `project_id` - Your GCP project ID
- `region` - GCP region (default: us-central1)
- `zone` - GCP zone (default: us-central1-a)
- `instance_name` - Name for the compute instance
- `ssh_user` - SSH username
- `ssh_public_key` - Your SSH public key

### Docker Environment

Key variables to configure in `docker/.env`:

- `N8N_BASIC_AUTH_USER` - n8n admin username
- `N8N_BASIC_AUTH_PASSWORD` - n8n admin password
- `N8N_ENCRYPTION_KEY` - Encryption key for credentials
- `POSTGRES_PASSWORD` - PostgreSQL password
- `N8N_HOST` - Your domain (e.g., n8n.yourdomain.com)

### Cloudflare Tunnel

Configure in `docker/cloudflared/config.yml`:

- Tunnel UUID and credentials
- Ingress rules mapping to n8n service

## Maintenance

### Backups

```bash
# Manual backup
./scripts/backup.sh

# Setup automated backups (cron)
# See docs/SETUP.md for details
```

### Updates

```bash
# Update n8n to latest version
cd docker
docker-compose pull
docker-compose up -d
```

### Monitoring

```bash
# View logs
docker-compose logs -f n8n

# Check service status
docker-compose ps
```

## Cost Estimation

- **GCP e2-micro**: Free tier (1 instance per month in us-central1, us-east1, us-west1)
- **Persistent Disk**: ~$0.40/month for 10GB standard persistent disk (free tier: 30GB)
- **Network Egress**: Free tier: 1GB/month, then ~$0.12/GB
- **Cloudflare Tunnel**: Free

**Estimated Monthly Cost**: $0-5 (depending on usage)

## Security Considerations

- No ports exposed to the internet (Cloudflare Tunnel only)
- SSH access via key-based authentication only
- n8n credentials encrypted at rest
- PostgreSQL not exposed externally
- Regular automated backups recommended
- Keep Docker images updated

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.

## Contributing

This is a personal infrastructure project, but feel free to fork and adapt for your own use.

## License

MIT

## Support

For issues specific to:
- **n8n**: See [n8n documentation](https://docs.n8n.io/)
- **Cloudflare Tunnel**: See [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- **GCP**: See [GCP documentation](https://cloud.google.com/docs)

## Acknowledgments

- [n8n](https://n8n.io/) - Workflow automation platform
- [Cloudflare](https://www.cloudflare.com/) - Cloudflare Tunnel for secure ingress
- [Terraform](https://www.terraform.io/) - Infrastructure as Code

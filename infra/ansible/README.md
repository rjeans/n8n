

# n8n Ansible Deployment

Automated provisioning and deployment of n8n to GCP using Ansible.

## Overview

This Ansible playbook automates the complete setup of n8n on a GCP e2-micro instance, including:

- System configuration and security hardening
- Docker and Docker Compose installation
- n8n deployment with PostgreSQL database
- Cloudflare Tunnel configuration
- Automated backups

## Prerequisites

### Local Machine

```bash
# Install Ansible
pip3 install ansible

# Or on macOS
brew install ansible

# Verify installation
ansible --version
```

### GCP Instance

- Instance provisioned via Terraform
- Instance IP address available
- SSH key configured
- Instance accessible via SSH

### Required Information

- [ ] GCP instance IP address (from `terraform output external_ip`)
- [ ] n8n domain name (e.g., n8n.yourdomain.com)
- [ ] Cloudflare Tunnel token
- [ ] n8n encryption key (generate or use existing)
- [ ] Secure passwords for n8n and PostgreSQL

## Quick Start

### 1. Update Inventory

```bash
cd infra/ansible

# Edit inventory with your GCP instance IP
nano inventory.ini

# Update this line:
n8n-server ansible_host=YOUR_GCP_INSTANCE_IP ansible_user=ubuntu
```

### 2. Configure Variables

**Option A: Direct Configuration (Not Recommended for Production)**

```bash
# Edit group variables
nano group_vars/n8n_servers.yml

# Update these values:
# - n8n_host: your domain
# - n8n_basic_auth_password
# - n8n_encryption_key
# - postgres_password
# - cloudflare_tunnel_token
```

**Option B: Use Ansible Vault (Recommended)**

```bash
# Create vault for sensitive variables
ansible-vault create vault.yml

# Add variables following vault.yml.example structure
# Save and exit

# Or copy from example
cp vault.yml.example vault.yml
ansible-vault encrypt vault.yml
ansible-vault edit vault.yml  # Edit with your values
```

### 3. Test Connection

```bash
# Test SSH connectivity
ansible n8n_servers -m ping

# Should return:
# n8n-server | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }
```

### 4. Run Playbook

**Without vault:**

```bash
ansible-playbook playbook.yml
```

**With vault:**

```bash
# Interactive password prompt
ansible-playbook playbook.yml --ask-vault-pass

# Or with password file
echo 'your-vault-password' > ~/.vault_pass.txt
chmod 600 ~/.vault_pass.txt
ansible-playbook playbook.yml --vault-password-file ~/.vault_pass.txt
```

**Dry run (check mode):**

```bash
ansible-playbook playbook.yml --check
```

## Directory Structure

```
infra/ansible/
├── ansible.cfg                 # Ansible configuration
├── inventory.ini               # Inventory file
├── playbook.yml                # Main playbook
├── vault.yml.example           # Example vault structure
├── group_vars/
│   ├── all.yml                 # Global variables
│   └── n8n_servers.yml         # n8n-specific variables
└── roles/
    ├── common/                 # System setup role
    │   ├── tasks/
    │   │   └── main.yml
    │   └── handlers/
    │       └── main.yml
    ├── docker/                 # Docker installation role
    │   ├── tasks/
    │   │   └── main.yml
    │   └── handlers/
    │       └── main.yml
    └── n8n/                    # n8n deployment role
        ├── tasks/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        └── templates/
            ├── docker-compose.yml.j2
            ├── env.j2
            └── backup.sh.j2
```

## Roles

### Common Role

System configuration and hardening:
- Package updates
- Timezone configuration
- Data disk verification
- Directory creation
- Unattended upgrades
- fail2ban installation

**Tags:** `common`, `system`, `security`

### Docker Role

Docker and Docker Compose installation:
- Docker CE installation
- Docker Compose plugin
- User permissions
- Docker daemon configuration

**Tags:** `docker`, `install`

### n8n Role

n8n application deployment:
- Docker Compose configuration
- Environment setup
- Container deployment
- Health checks
- Backup script deployment
- Cron job configuration

**Tags:** `n8n`, `deploy`, `config`, `backup`

## Common Tasks

### Deploy Everything

```bash
ansible-playbook playbook.yml
```

### Update n8n Configuration Only

```bash
ansible-playbook playbook.yml --tags n8n,config
```

### Redeploy n8n Containers

```bash
ansible-playbook playbook.yml --tags deploy
```

### Update System Packages Only

```bash
ansible-playbook playbook.yml --tags common,packages
```

### Setup Backups Only

```bash
ansible-playbook playbook.yml --tags backup
```

### Skip Tags

```bash
# Deploy without security updates
ansible-playbook playbook.yml --skip-tags security
```

## Configuration

### Required Variables

These must be set in `group_vars/n8n_servers.yml` or `vault.yml`:

```yaml
# Domain
n8n_host: n8n.yourdomain.com

# Authentication
n8n_basic_auth_password: "secure-password"

# Encryption Key (CRITICAL!)
n8n_encryption_key: "32-character-key"

# Database
postgres_password: "secure-password"

# Cloudflare
cloudflare_tunnel_token: "your-token"
```

### Optional Variables

Set in `group_vars/all.yml`:

```yaml
# Timezone
timezone: America/New_York

# Backup retention
backup_retention_days: 30

# Auto-updates
auto_updates_enabled: true

# Watchtower
watchtower_enabled: false
```

## Ansible Vault

### Create Vault

```bash
ansible-vault create vault.yml
```

### Edit Vault

```bash
ansible-vault edit vault.yml
```

### View Vault

```bash
ansible-vault view vault.yml
```

### Encrypt Existing File

```bash
ansible-vault encrypt group_vars/n8n_servers.yml
```

### Decrypt File

```bash
ansible-vault decrypt group_vars/n8n_servers.yml
```

### Use Vault Password File

```bash
# Create password file
echo 'your-vault-password' > ~/.vault_pass.txt
chmod 600 ~/.vault_pass.txt

# Run playbook
ansible-playbook playbook.yml --vault-password-file ~/.vault_pass.txt
```

## Verification

### Check Deployment

```bash
# SSH to server
ssh ubuntu@<instance-ip>

# Check containers
cd /opt/n8n
docker compose ps

# Check logs
docker compose logs -f

# Test n8n health
curl http://localhost:5678/healthz
```

### Verify Backup

```bash
# Run backup manually
sudo /usr/local/bin/n8n-backup

# Check backup files
ls -lh /mnt/data/backups/

# View latest backup manifest
cat /mnt/data/backups/$(ls -t /mnt/data/backups/ | head -1)/MANIFEST.txt
```

## Troubleshooting

### Connection Issues

```bash
# Test SSH connection
ssh -v ubuntu@<instance-ip>

# Test Ansible ping
ansible n8n_servers -m ping -vvv
```

### Permission Denied

```bash
# Check SSH key
ssh-add -l

# Add SSH key
ssh-add ~/.ssh/id_rsa

# Or specify key in inventory
nano inventory.ini
# Add: ansible_ssh_private_key_file=/path/to/key
```

### Playbook Fails

```bash
# Run with verbose output
ansible-playbook playbook.yml -vvv

# Run in check mode
ansible-playbook playbook.yml --check

# Run specific tags
ansible-playbook playbook.yml --tags common -vvv
```

### Container Issues

```bash
# SSH to server
ssh ubuntu@<instance-ip>

# Check container logs
cd /opt/n8n
docker compose logs

# Restart containers
docker compose restart

# Rebuild and restart
docker compose down
docker compose up -d
```

## Advanced Usage

### Limit to Specific Hosts

```bash
ansible-playbook playbook.yml --limit n8n-server
```

### Override Variables

```bash
ansible-playbook playbook.yml -e "n8n_version=1.45.1"
```

### List Tasks

```bash
ansible-playbook playbook.yml --list-tasks
```

### List Tags

```bash
ansible-playbook playbook.yml --list-tags
```

### Syntax Check

```bash
ansible-playbook playbook.yml --syntax-check
```

## Migration with Ansible

To migrate from Kubernetes:

1. **Export data from K8s** (run locally):
   ```bash
   cd migration
   ./export-k8s-data.sh
   ```

2. **Transfer to Ansible control machine**

3. **Deploy fresh n8n with Ansible**:
   ```bash
   # IMPORTANT: Use the same encryption key!
   ansible-vault edit vault.yml
   # Set n8n_encryption_key to your old key

   ansible-playbook playbook.yml --ask-vault-pass
   ```

4. **Import data** (SSH to server):
   ```bash
   # Transfer migration package to server
   scp migration_package_*.tar.gz ubuntu@<ip>:~/

   # SSH to server
   ssh ubuntu@<ip>

   # Import data
   cd /opt/n8n/scripts
   ./migrate-from-k8s.sh ~/migration_package_*
   ```

## Security Best Practices

1. **Use Ansible Vault** for all sensitive variables
2. **Restrict SSH access** in Terraform firewall rules
3. **Use strong passwords** (20+ characters)
4. **Rotate credentials** regularly
5. **Keep vault password secure** (use password manager)
6. **Don't commit** vault password files to git
7. **Use service account** SSH keys (not personal)
8. **Enable fail2ban** (included in common role)
9. **Keep systems updated** (auto-updates enabled)

## Integration with Terraform

Get instance IP from Terraform:

```bash
cd ../../terraform
terraform output -raw external_ip

# Or programmatically
INSTANCE_IP=$(cd ../../terraform && terraform output -raw external_ip)
echo "n8n-server ansible_host=$INSTANCE_IP ansible_user=ubuntu" > ../ansible/inventory.ini
```

## Next Steps

After successful deployment:

1. Access n8n at https://your-domain.com
2. Login with configured credentials
3. Create a test workflow
4. Verify backup is running (check `/var/log/n8n-backup.log`)
5. Setup monitoring
6. Configure additional workflows

## Support

For issues:
- Check [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md)
- Review Ansible logs: `ansible-playbook playbook.yml -vvv`
- Check container logs on server
- Consult Ansible documentation: https://docs.ansible.com/

## Tips

- **Use tags** for targeted deployments
- **Test in check mode** before applying changes
- **Keep vault password secure** and backed up
- **Version control** your variables (except vault.yml)
- **Document changes** to group_vars
- **Test backups** regularly
- **Monitor disk space** on /mnt/data

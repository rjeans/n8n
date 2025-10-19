# Using 1Password with Ansible

This guide explains how to use 1Password to securely manage SSH keys and secrets for Ansible deployment.

## Overview

Instead of storing SSH private keys on disk, you can retrieve them from 1Password on-demand. This provides:

✅ **Enhanced Security**: Keys stored encrypted in 1Password
✅ **Centralized Management**: One source of truth for secrets
✅ **Audit Trail**: 1Password tracks key access
✅ **Easy Rotation**: Update in 1Password, re-run script
✅ **Team Collaboration**: Share keys securely with team members

## Prerequisites

### 1. Install 1Password CLI

**macOS:**
```bash
brew install 1password-cli
```

**Linux:**
```bash
# Download from https://1password.com/downloads/command-line/
# Or install via package manager
```

**Verify installation:**
```bash
op --version
```

### 2. Sign in to 1Password

```bash
# Interactive sign-in
op signin

# Or with account shorthand
eval $(op signin my.1password.com user@example.com)
```

### 3. Store SSH Key in 1Password

#### Option A: Via 1Password App (Recommended)

1. Open 1Password app
2. Create new **SSH Key** item or **Secure Note**
3. Name it: `n8n-gcp-ssh-key`
4. Add a field labeled `private_key`
5. Paste your SSH private key content
6. Save

#### Option B: Via CLI

```bash
# Create item with SSH key
op item create \
  --category="SSH Key" \
  --title="n8n-gcp-ssh-key" \
  --vault="Private" \
  private_key="$(cat ~/.ssh/id_rsa)"
```

## Quick Start with 1Password

### Automated Setup (Recommended)

```bash
cd infra/ansible

# Run the setup script
./scripts/setup-1password-ssh.sh

# This will:
# 1. Check 1Password CLI is installed
# 2. Ensure you're signed in
# 3. Retrieve SSH key from 1Password
# 4. Save to ~/.ssh/ansible/n8n-gcp
# 5. Update inventory.ini automatically
# 6. Add key to SSH agent
```

### Custom Item Name

If your 1Password item has a different name:

```bash
./scripts/setup-1password-ssh.sh "my-custom-ssh-key"
```

## Manual 1Password Integration

If you prefer manual setup:

### 1. Retrieve SSH Key

```bash
# Retrieve and save to file
op item get "n8n-gcp-ssh-key" --fields label=private_key > ~/.ssh/ansible/n8n-gcp

# Set correct permissions
chmod 600 ~/.ssh/ansible/n8n-gcp

# Verify it's a valid key
ssh-keygen -l -f ~/.ssh/ansible/n8n-gcp
```

### 2. Update Inventory

Edit `inventory.ini`:
```ini
n8n-server ansible_host=YOUR_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/ansible/n8n-gcp
```

### 3. Add to SSH Agent

```bash
ssh-add ~/.ssh/ansible/n8n-gcp
```

## Storing Ansible Vault Password in 1Password

You can also store your Ansible vault password in 1Password:

### 1. Store Password in 1Password

Via 1Password app:
1. Create new **Password** item
2. Name it: `n8n-ansible-vault`
3. Set the password field
4. Save

### 2. Create Password File Script

```bash
cat > ~/.ansible-vault-password.sh <<'EOF'
#!/bin/bash
op item get "n8n-ansible-vault" --fields label=password
EOF

chmod +x ~/.ansible-vault-password.sh
```

### 3. Use with Ansible

```bash
# Now run playbooks without entering password
ansible-playbook playbook.yml --vault-password-file ~/.ansible-vault-password.sh
```

## Storing All Secrets in 1Password

You can retrieve all secrets from 1Password instead of using ansible vault:

### 1. Store Secrets in 1Password

Create items for each secret:
- `n8n-encryption-key`
- `n8n-postgres-password`
- `n8n-admin-password`
- `cloudflare-tunnel-token`

### 2. Retrieve at Runtime

Create a script `scripts/get-secrets.sh`:

```bash
#!/bin/bash
# Retrieve all secrets from 1Password

export N8N_ENCRYPTION_KEY=$(op item get "n8n-encryption-key" --fields label=password)
export POSTGRES_PASSWORD=$(op item get "n8n-postgres-password" --fields label=password)
export N8N_BASIC_AUTH_PASSWORD=$(op item get "n8n-admin-password" --fields label=password)
export CLOUDFLARE_TUNNEL_TOKEN=$(op item get "cloudflare-tunnel-token" --fields label=password)

# Run ansible with these variables
ansible-playbook playbook.yml \
  -e "n8n_encryption_key=${N8N_ENCRYPTION_KEY}" \
  -e "postgres_password=${POSTGRES_PASSWORD}" \
  -e "n8n_basic_auth_password=${N8N_BASIC_AUTH_PASSWORD}" \
  -e "cloudflare_tunnel_token=${CLOUDFLARE_TUNNEL_TOKEN}"
```

### 3. Run Deployment

```bash
./scripts/get-secrets.sh
```

## Automated Key Retrieval

The setup script creates a wrapper for automated retrieval:

```bash
# Re-retrieve key anytime
~/.ssh/ansible/retrieve-key.sh

# Or integrate into your workflow
~/.ssh/ansible/retrieve-key.sh && ansible-playbook playbook.yml
```

## Troubleshooting

### "not currently signed in" Error

```bash
# Sign in to 1Password
op signin

# Or
eval $(op signin)
```

### "item not found" Error

```bash
# List available items
op item list --categories "SSH Key,Secure Note"

# Verify item name matches
op item get "n8n-gcp-ssh-key"
```

### Permission Denied (SSH Key)

```bash
# Ensure correct permissions
chmod 600 ~/.ssh/ansible/n8n-gcp

# Check key fingerprint
ssh-keygen -l -f ~/.ssh/ansible/n8n-gcp

# Add to agent
ssh-add ~/.ssh/ansible/n8n-gcp
```

### Field Not Found

The script looks for a field labeled `private_key`. Ensure your 1Password item has this field:

```bash
# View item structure
op item get "n8n-gcp-ssh-key" --format json

# If field has different name, update script
op item get "n8n-gcp-ssh-key" --fields label=YOUR_FIELD_NAME
```

## Security Best Practices

1. **Use Service Accounts**: Create a separate 1Password service account for automation
2. **Limit Access**: Restrict vault access to only required items
3. **Rotate Keys**: Regularly rotate SSH keys and update in 1Password
4. **Audit Access**: Review 1Password activity logs
5. **Use Session Tokens**: Don't hardcode credentials in scripts
6. **Secure Scripts**: Set proper permissions on wrapper scripts (chmod 700)

## CI/CD Integration

For automated deployments in CI/CD:

### 1. Use 1Password Connect Server

Set up 1Password Connect for automated access:
- https://developer.1password.com/docs/connect/

### 2. Use Environment Variables

```yaml
# GitHub Actions example
- name: Retrieve SSH Key
  env:
    OP_CONNECT_HOST: ${{ secrets.OP_CONNECT_HOST }}
    OP_CONNECT_TOKEN: ${{ secrets.OP_CONNECT_TOKEN }}
  run: |
    op item get "n8n-gcp-ssh-key" --fields label=private_key > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
```

## References

- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)
- [1Password Connect](https://developer.1password.com/docs/connect/)
- [Ansible Vault Best Practices](https://docs.ansible.com/ansible/latest/user_guide/vault.html)

## Support

For 1Password CLI issues:
- Documentation: https://developer.1password.com/docs/cli/
- Community: https://1password.community/

For Ansible integration:
- See [README.md](README.md)
- See [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md)

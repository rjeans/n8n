#!/bin/bash

################################################################################
# 1Password SSH Key Setup for Ansible
#
# This script retrieves the SSH private key from 1Password and configures
# it for use with Ansible.
#
# Prerequisites:
# - 1Password CLI (op) installed
# - Signed in to 1Password: op signin
#
# Usage: ./setup-1password-ssh.sh [item-name]
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
SSH_KEY_DIR="${HOME}/.ssh/ansible"
SSH_KEY_FILE="${SSH_KEY_DIR}/n8n-gcp"
ITEM_NAME="${1:-n8n-gcp-ssh-key}"

# Check if 1Password CLI is installed
check_op_cli() {
    print_info "Checking for 1Password CLI..."

    if ! command -v op &> /dev/null; then
        print_error "1Password CLI (op) is not installed"
        echo ""
        print_info "Install from: https://1password.com/downloads/command-line/"
        echo ""
        print_info "macOS: brew install 1password-cli"
        print_info "Linux: See https://developer.1password.com/docs/cli/get-started/"
        exit 1
    fi

    print_success "1Password CLI found: $(op --version)"
}

# Check if signed in to 1Password
check_op_signin() {
    print_info "Checking 1Password authentication..."

    if ! op account list &> /dev/null; then
        print_warning "Not signed in to 1Password"
        print_info "Signing in..."
        eval $(op signin)
    else
        print_success "Already signed in to 1Password"
    fi
}

# Create SSH key directory
create_ssh_dir() {
    print_info "Creating SSH key directory..."

    mkdir -p "${SSH_KEY_DIR}"
    chmod 700 "${SSH_KEY_DIR}"

    print_success "Directory created: ${SSH_KEY_DIR}"
}

# Retrieve SSH key from 1Password
retrieve_ssh_key() {
    print_info "Retrieving SSH key from 1Password..."
    print_info "Item name: ${ITEM_NAME}"

    # Try to get the SSH key from 1Password
    if op item get "${ITEM_NAME}" --fields label=private_key > "${SSH_KEY_FILE}" 2>/dev/null; then
        print_success "SSH key retrieved successfully"
    else
        print_error "Failed to retrieve SSH key from 1Password"
        echo ""
        print_info "Make sure the item exists in 1Password with:"
        print_info "  - Item name: ${ITEM_NAME}"
        print_info "  - Field label: private_key"
        echo ""
        print_info "Available items:"
        op item list --categories "SSH Key,Secure Note" | head -10
        exit 1
    fi

    # Set correct permissions
    chmod 600 "${SSH_KEY_FILE}"

    # Verify the key is valid
    if ssh-keygen -l -f "${SSH_KEY_FILE}" &> /dev/null; then
        print_success "SSH key is valid"
        ssh-keygen -l -f "${SSH_KEY_FILE}"
    else
        print_error "Retrieved key is not a valid SSH private key"
        rm -f "${SSH_KEY_FILE}"
        exit 1
    fi
}

# Update inventory.ini
update_inventory() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ansible_dir="$(dirname "$script_dir")"
    local inventory_file="${ansible_dir}/inventory.ini"

    print_info "Updating inventory.ini..."

    if [ -f "${inventory_file}" ]; then
        # Update the SSH key path in inventory
        if grep -q "ansible_ssh_private_key_file" "${inventory_file}"; then
            # Use different delimiters for sed to avoid issues with paths
            sed -i.bak "s|ansible_ssh_private_key_file=.*|ansible_ssh_private_key_file=${SSH_KEY_FILE}|g" "${inventory_file}"
            rm -f "${inventory_file}.bak"
            print_success "Updated inventory.ini with SSH key path"
        else
            print_warning "Could not find ansible_ssh_private_key_file in inventory.ini"
            print_info "Manually add to inventory.ini:"
            echo "  ansible_ssh_private_key_file=${SSH_KEY_FILE}"
        fi
    else
        print_warning "inventory.ini not found"
        print_info "Create it from inventory.ini.example and add:"
        echo "  ansible_ssh_private_key_file=${SSH_KEY_FILE}"
    fi
}

# Add to SSH agent
add_to_ssh_agent() {
    print_info "Adding key to SSH agent..."

    # Start ssh-agent if not running
    if [ -z "${SSH_AUTH_SOCK:-}" ]; then
        eval $(ssh-agent -s)
    fi

    # Add the key
    ssh-add "${SSH_KEY_FILE}"

    print_success "Key added to SSH agent"
}

# Create wrapper script for automated retrieval
create_wrapper_script() {
    local wrapper_script="${SSH_KEY_DIR}/retrieve-key.sh"

    print_info "Creating wrapper script for automated retrieval..."

    cat > "${wrapper_script}" <<'WRAPPER_EOF'
#!/bin/bash
# Automated SSH key retrieval from 1Password
# This script can be called before running Ansible

set -euo pipefail

SSH_KEY_FILE="${HOME}/.ssh/ansible/n8n-gcp"
ITEM_NAME="n8n-gcp-ssh-key"

# Ensure we're signed in
if ! op account list &> /dev/null; then
    eval $(op signin)
fi

# Retrieve the key
op item get "${ITEM_NAME}" --fields label=private_key > "${SSH_KEY_FILE}"
chmod 600 "${SSH_KEY_FILE}"

echo "SSH key retrieved from 1Password"
WRAPPER_EOF

    chmod +x "${wrapper_script}"

    print_success "Wrapper script created: ${wrapper_script}"
}

# Display summary
show_summary() {
    echo ""
    echo "========================================="
    print_success "1Password SSH Setup Complete!"
    echo "========================================="
    echo ""
    print_info "SSH Key Location: ${SSH_KEY_FILE}"
    print_info "Key Fingerprint:"
    ssh-keygen -l -f "${SSH_KEY_FILE}"
    echo ""
    print_info "Inventory Configuration:"
    echo "  ansible_ssh_private_key_file=${SSH_KEY_FILE}"
    echo ""
    print_info "Next Steps:"
    echo "  1. Verify inventory.ini has the correct key path"
    echo "  2. Test connection: ansible n8n_servers -m ping"
    echo "  3. Run playbook: ansible-playbook playbook.yml --ask-vault-pass"
    echo ""
    print_info "To retrieve key again in the future:"
    echo "  ${SSH_KEY_DIR}/retrieve-key.sh"
    echo ""
}

# Main function
main() {
    echo ""
    echo "========================================="
    echo "  1Password SSH Key Setup"
    echo "========================================="
    echo ""

    check_op_cli
    check_op_signin
    create_ssh_dir
    retrieve_ssh_key
    update_inventory
    add_to_ssh_agent
    create_wrapper_script
    show_summary
}

# Run main function
main

#!/bin/bash

################################################################################
# Kubernetes Secrets Retrieval Script
#
# This script helps retrieve all necessary secrets from your existing
# Kubernetes-based n8n instance for migration to GCP.
#
# Usage: ./get-k8s-secrets.sh [namespace]
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
NAMESPACE="${1:-default}"
OUTPUT_FILE="k8s_secrets_$(date +%Y%m%d_%H%M%S).txt"

# Check kubectl
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    print_success "Connected to Kubernetes cluster"
}

# Find n8n resources
find_n8n_resources() {
    print_info "Finding n8n resources in namespace: $NAMESPACE"

    # Find n8n pod
    N8N_POD=$(kubectl get pods -n "$NAMESPACE" -l app=n8n -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$N8N_POD" ]; then
        # Try without label selector
        N8N_POD=$(kubectl get pods -n "$NAMESPACE" -o name | grep n8n | head -1 | cut -d'/' -f2 || echo "")
    fi

    if [ -n "$N8N_POD" ]; then
        print_success "Found n8n pod: $N8N_POD"
    else
        print_warning "Could not find n8n pod automatically"
    fi
}

# Retrieve encryption key
get_encryption_key() {
    print_info "Retrieving n8n encryption key..."

    local key=""

    # Try from secret
    for secret_name in "n8n-secret" "n8n-config" "n8n-env" "n8n"; do
        if kubectl get secret "$secret_name" -n "$NAMESPACE" &>/dev/null; then
            key=$(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' 2>/dev/null | base64 -d || echo "")
            if [ -n "$key" ]; then
                echo "N8N_ENCRYPTION_KEY=$key"
                print_success "Found in secret: $secret_name"
                return 0
            fi
        fi
    done

    # Try from pod environment
    if [ -n "$N8N_POD" ]; then
        key=$(kubectl exec -n "$NAMESPACE" "$N8N_POD" -- env 2>/dev/null | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 || echo "")
        if [ -n "$key" ]; then
            echo "N8N_ENCRYPTION_KEY=$key"
            print_success "Found in pod environment"
            return 0
        fi
    fi

    print_warning "Could not retrieve encryption key automatically"
    echo "N8N_ENCRYPTION_KEY=NOT_FOUND"
}

# Retrieve PostgreSQL password
get_postgres_password() {
    print_info "Retrieving PostgreSQL password..."

    local password=""

    # Try from secrets
    for secret_name in "n8n-postgres-secret" "postgresql" "postgres-secret" "n8n-secret"; do
        if kubectl get secret "$secret_name" -n "$NAMESPACE" &>/dev/null; then
            # Try different key names
            for key_name in "POSTGRES_PASSWORD" "postgresql-password" "password"; do
                password=$(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath="{.data.$key_name}" 2>/dev/null | base64 -d || echo "")
                if [ -n "$password" ]; then
                    echo "POSTGRES_PASSWORD=$password"
                    print_success "Found in secret: $secret_name (key: $key_name)"
                    return 0
                fi
            done
        fi
    done

    # Try from n8n pod environment
    if [ -n "$N8N_POD" ]; then
        password=$(kubectl exec -n "$NAMESPACE" "$N8N_POD" -- env 2>/dev/null | grep DB_POSTGRESDB_PASSWORD | cut -d'=' -f2 || echo "")
        if [ -n "$password" ]; then
            echo "POSTGRES_PASSWORD=$password"
            print_success "Found in pod environment"
            return 0
        fi
    fi

    print_warning "Could not retrieve PostgreSQL password automatically"
    echo "POSTGRES_PASSWORD=NOT_FOUND"
}

# Retrieve n8n basic auth password
get_n8n_auth_password() {
    print_info "Retrieving n8n basic auth password..."

    local password=""

    # Try from secret
    for secret_name in "n8n-secret" "n8n-config" "n8n-env"; do
        if kubectl get secret "$secret_name" -n "$NAMESPACE" &>/dev/null; then
            password=$(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.N8N_BASIC_AUTH_PASSWORD}' 2>/dev/null | base64 -d || echo "")
            if [ -n "$password" ]; then
                echo "N8N_BASIC_AUTH_PASSWORD=$password"
                print_success "Found in secret: $secret_name"
                return 0
            fi
        fi
    done

    # Try from pod environment
    if [ -n "$N8N_POD" ]; then
        password=$(kubectl exec -n "$NAMESPACE" "$N8N_POD" -- env 2>/dev/null | grep N8N_BASIC_AUTH_PASSWORD | cut -d'=' -f2 || echo "")
        if [ -n "$password" ]; then
            echo "N8N_BASIC_AUTH_PASSWORD=$password"
            print_success "Found in pod environment"
            return 0
        fi
    fi

    print_warning "Could not retrieve n8n auth password automatically"
    echo "N8N_BASIC_AUTH_PASSWORD=NOT_FOUND"
}

# Retrieve n8n basic auth user
get_n8n_auth_user() {
    print_info "Retrieving n8n basic auth user..."

    local user=""

    # Try from secret
    for secret_name in "n8n-secret" "n8n-config" "n8n-env"; do
        if kubectl get secret "$secret_name" -n "$NAMESPACE" &>/dev/null; then
            user=$(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.N8N_BASIC_AUTH_USER}' 2>/dev/null | base64 -d || echo "")
            if [ -n "$user" ]; then
                echo "N8N_BASIC_AUTH_USER=$user"
                print_success "Found in secret: $secret_name"
                return 0
            fi
        fi
    done

    # Try from pod environment
    if [ -n "$N8N_POD" ]; then
        user=$(kubectl exec -n "$NAMESPACE" "$N8N_POD" -- env 2>/dev/null | grep N8N_BASIC_AUTH_USER | cut -d'=' -f2 || echo "")
        if [ -n "$user" ]; then
            echo "N8N_BASIC_AUTH_USER=$user"
            print_success "Found in pod environment"
            return 0
        fi
    fi

    echo "N8N_BASIC_AUTH_USER=admin"  # Default value
}

# List all secrets for manual inspection
list_all_secrets() {
    print_info "Listing all secrets in namespace for manual inspection..."
    echo ""
    echo "Available secrets:"
    kubectl get secrets -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp
}

# Create output file
create_output() {
    print_info "Creating secrets file: $OUTPUT_FILE"

    cat > "$OUTPUT_FILE" <<EOF
# Kubernetes Secrets Retrieved from n8n Instance
# Date: $(date)
# Namespace: $NAMESPACE
# Pod: ${N8N_POD:-N/A}
#
# ⚠️  CRITICAL: Keep this file secure and delete after migration!
#
# Use these values in your Ansible vault.yml or group_vars

# Retrieved Secrets:
# ==================

$(get_encryption_key)

$(get_postgres_password)

$(get_n8n_auth_user)

$(get_n8n_auth_password)

# Additional Information:
# =======================

# Available secrets in namespace:
$(kubectl get secrets -n "$NAMESPACE" -o name)

# For manual inspection of any secret:
# kubectl get secret <secret-name> -n $NAMESPACE -o jsonpath='{.data}' | jq 'map_values(@base64d)'

# To view all environment variables from n8n pod:
# kubectl exec -n $NAMESPACE ${N8N_POD:-<pod-name>} -- env | grep -E '(N8N|POSTGRES|DB_)'

EOF

    print_success "Secrets saved to: $OUTPUT_FILE"
}

# Display summary
show_summary() {
    echo ""
    echo "========================================="
    print_success "Secrets Retrieval Complete"
    echo "========================================="
    echo ""
    print_info "Secrets saved to: $OUTPUT_FILE"
    echo ""
    print_warning "⚠️  IMPORTANT NOTES:"
    echo ""
    echo "1. CRITICAL: The N8N_ENCRYPTION_KEY must be used in your new deployment"
    echo "   If this key is different, all saved credentials will be unrecoverable!"
    echo ""
    echo "2. Review the output file and verify all secrets were found"
    echo "   If any show 'NOT_FOUND', you'll need to retrieve them manually"
    echo ""
    echo "3. Keep this file secure and delete it after migration"
    echo "   It contains sensitive passwords and keys"
    echo ""
    echo "4. To use with Ansible:"
    echo "   - Create vault: ansible-vault create vault.yml"
    echo "   - Copy values from $OUTPUT_FILE to vault.yml"
    echo "   - Delete $OUTPUT_FILE securely: shred -u $OUTPUT_FILE"
    echo ""
    print_info "Next Steps:"
    echo "1. Review: cat $OUTPUT_FILE"
    echo "2. Create Ansible vault with these values"
    echo "3. Run migration/export-k8s-data.sh to export workflows"
    echo "4. Deploy to GCP with Ansible"
    echo ""
}

# Manual inspection guide
show_manual_guide() {
    if grep -q "NOT_FOUND" "$OUTPUT_FILE"; then
        echo ""
        print_warning "Some secrets were not found automatically."
        echo ""
        print_info "Manual retrieval commands:"
        echo ""
        echo "# List all secrets:"
        echo "kubectl get secrets -n $NAMESPACE"
        echo ""
        echo "# View a specific secret (all keys):"
        echo "kubectl get secret <secret-name> -n $NAMESPACE -o jsonpath='{.data}' | jq 'map_values(@base64d)'"
        echo ""
        echo "# View specific key from secret:"
        echo "kubectl get secret <secret-name> -n $NAMESPACE -o jsonpath='{.data.KEY_NAME}' | base64 -d"
        echo ""
        echo "# View environment variables from n8n pod:"
        echo "kubectl exec -n $NAMESPACE ${N8N_POD:-<pod-name>} -- env | grep -E '(N8N|POSTGRES|DB_)'"
        echo ""
    fi
}

# Main function
main() {
    echo ""
    echo "========================================="
    echo "  Kubernetes Secrets Retrieval"
    echo "========================================="
    echo ""

    check_kubectl
    find_n8n_resources
    create_output
    show_summary
    show_manual_guide
}

# Run main function
main

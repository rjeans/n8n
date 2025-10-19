#!/bin/bash

################################################################################
# n8n Kubernetes Data Export Script
#
# This script exports all necessary data from your Kubernetes-based n8n instance
# for migration to the new GCP instance.
#
# Usage: ./export-k8s-data.sh [namespace]
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${1:-default}"
EXPORT_DIR="n8n_k8s_export_$(date +%Y%m%d_%H%M%S)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Function to create export directory
create_export_dir() {
    print_info "Creating export directory: $EXPORT_DIR"
    mkdir -p "$EXPORT_DIR"
    cd "$EXPORT_DIR"
}

# Function to export encryption key
export_encryption_key() {
    print_info "Exporting n8n encryption key..."

    # Try common secret names
    local secret_names=("n8n-secret" "n8n-config" "n8n-env" "n8n")
    local found=false

    for secret_name in "${secret_names[@]}"; do
        if kubectl get secret "$secret_name" -n "$NAMESPACE" &> /dev/null; then
            print_info "Found secret: $secret_name"

            # Try to extract encryption key
            if kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' | base64 -d > encryption_key.txt 2>/dev/null; then
                if [ -s encryption_key.txt ]; then
                    print_success "Encryption key exported to encryption_key.txt"
                    print_warning "CRITICAL: Keep this file secure! You'll need this exact key in the new instance."
                    found=true
                    break
                fi
            fi
        fi
    done

    if [ "$found" = false ]; then
        print_warning "Could not find encryption key in secrets"
        print_warning "You'll need to manually obtain the N8N_ENCRYPTION_KEY from your deployment"
        echo "MANUAL_EXTRACTION_NEEDED" > encryption_key.txt
    fi
}

# Function to export environment variables
export_env_vars() {
    print_info "Exporting environment variables..."

    # Find n8n deployment
    local deployment=$(kubectl get deployments -n "$NAMESPACE" -o name | grep n8n | head -n 1)

    if [ -z "$deployment" ]; then
        print_warning "No n8n deployment found"
        return 1
    fi

    print_info "Found deployment: $deployment"

    # Export full deployment YAML
    kubectl get "$deployment" -n "$NAMESPACE" -o yaml > n8n-deployment.yaml
    print_success "Deployment exported to n8n-deployment.yaml"

    # Extract environment variables
    kubectl get "$deployment" -n "$NAMESPACE" -o yaml | grep -A 100 "env:" > env-vars.txt || true
    print_success "Environment variables extracted to env-vars.txt"
}

# Function to export workflows via API
export_workflows_api() {
    print_info "Attempting to export workflows via n8n API..."

    # Find n8n pod
    local pod=$(kubectl get pods -n "$NAMESPACE" -l app=n8n -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod" ]; then
        print_warning "No n8n pod found, skipping API export"
        return 1
    fi

    print_info "Found pod: $pod"

    # Port forward in background
    print_info "Setting up port forward..."
    kubectl port-forward -n "$NAMESPACE" "$pod" 5678:5678 &
    PF_PID=$!
    sleep 5

    # Try to export workflows
    print_info "Attempting to export workflows..."
    if curl -f -u "${N8N_USER:-admin}:${N8N_PASSWORD:-admin}" http://localhost:5678/api/v1/workflows > workflows_export.json 2>/dev/null; then
        print_success "Workflows exported to workflows_export.json"
    else
        print_warning "Could not export workflows via API (check credentials)"
        rm -f workflows_export.json
    fi

    # Try to export credentials
    print_info "Attempting to export credentials..."
    if curl -f -u "${N8N_USER:-admin}:${N8N_PASSWORD:-admin}" http://localhost:5678/api/v1/credentials > credentials_export.json 2>/dev/null; then
        print_success "Credentials exported to credentials_export.json"
    else
        print_warning "Could not export credentials via API (check credentials)"
        rm -f credentials_export.json
    fi

    # Clean up port forward
    kill $PF_PID 2>/dev/null || true
}

# Function to export PostgreSQL database
export_database() {
    print_info "Exporting PostgreSQL database..."

    # Find PostgreSQL pod
    local pg_pod=$(kubectl get pods -n "$NAMESPACE" -o name | grep -i postgres | head -n 1 | cut -d'/' -f2)

    if [ -z "$pg_pod" ]; then
        print_warning "No PostgreSQL pod found"
        print_warning "You'll need to manually export the database"
        return 1
    fi

    print_info "Found PostgreSQL pod: $pg_pod"

    # Try to export database
    print_info "Creating database backup..."

    # Try common database names and users
    local db_names=("n8n" "postgres")
    local db_users=("n8n" "postgres")
    local exported=false

    for db_name in "${db_names[@]}"; do
        for db_user in "${db_users[@]}"; do
            if kubectl exec -n "$NAMESPACE" "$pg_pod" -- pg_dump -U "$db_user" "$db_name" > n8n_database_backup.sql 2>/dev/null; then
                if [ -s n8n_database_backup.sql ]; then
                    print_success "Database exported successfully"
                    print_info "Database: $db_name, User: $db_user"

                    # Compress the backup
                    gzip n8n_database_backup.sql
                    print_success "Database backup compressed to n8n_database_backup.sql.gz"

                    # Save database info
                    echo "Database: $db_name" > database_info.txt
                    echo "User: $db_user" >> database_info.txt

                    exported=true
                    break 2
                fi
            fi
        done
    done

    if [ "$exported" = false ]; then
        print_warning "Could not automatically export database"
        print_warning "Manual export required. Try:"
        echo "  kubectl exec -n $NAMESPACE $pg_pod -- pg_dump -U <user> <database> > n8n_database_backup.sql"
    fi
}

# Function to export persistent volume data
export_pv_data() {
    print_info "Collecting persistent volume information..."

    kubectl get pvc -n "$NAMESPACE" -o yaml > pvc-info.yaml
    kubectl get pv -o yaml > pv-info.yaml

    print_success "Persistent volume information saved"
}

# Function to export resource definitions
export_resources() {
    print_info "Exporting Kubernetes resource definitions..."

    kubectl get all -n "$NAMESPACE" -o yaml > all-resources.yaml
    kubectl get secrets -n "$NAMESPACE" -o yaml > secrets.yaml
    kubectl get configmaps -n "$NAMESPACE" -o yaml > configmaps.yaml

    print_success "Resource definitions exported"
}

# Function to create checksums
create_checksums() {
    print_info "Creating checksums for verification..."

    sha256sum * > checksums.txt 2>/dev/null || shasum -a 256 * > checksums.txt

    print_success "Checksums created"
}

# Function to create summary
create_summary() {
    print_info "Creating export summary..."

    cat > EXPORT_SUMMARY.txt <<EOF
n8n Kubernetes Export Summary
========================================
Export Date: $(date)
Namespace: $NAMESPACE
Export Directory: $EXPORT_DIR

Files Exported:
----------------------------------------
$(ls -lh)

Critical Files:
----------------------------------------
- encryption_key.txt: n8n encryption key (CRITICAL!)
- n8n_database_backup.sql.gz: PostgreSQL database backup
- n8n-deployment.yaml: n8n deployment configuration
- env-vars.txt: Environment variables

Optional Files:
----------------------------------------
- workflows_export.json: Workflows (if API export succeeded)
- credentials_export.json: Credentials (if API export succeeded)
- database_info.txt: Database connection details
- pvc-info.yaml: Persistent volume claims
- pv-info.yaml: Persistent volumes
- all-resources.yaml: All Kubernetes resources
- secrets.yaml: Secrets (encrypted)
- configmaps.yaml: ConfigMaps

Next Steps:
----------------------------------------
1. Review encryption_key.txt - you MUST use this exact key in new instance
2. Transfer this export to your GCP instance:
   scp -r $EXPORT_DIR user@gcp-instance:~/
3. Follow migration guide in migration/README.md

Verification:
----------------------------------------
Run: sha256sum -c checksums.txt
All files should show: OK

IMPORTANT NOTES:
----------------------------------------
- Keep encryption_key.txt secure and private
- Verify database backup integrity before proceeding
- Test restoration on GCP instance before switching over
- Do NOT delete this export until migration is verified

For detailed migration steps, see: migration/README.md
EOF

    print_success "Export summary created"
}

# Main execution
main() {
    echo ""
    echo "========================================="
    echo "  n8n Kubernetes Data Export Tool"
    echo "========================================="
    echo ""

    print_info "Namespace: $NAMESPACE"
    print_info "Export directory: $EXPORT_DIR"
    echo ""

    check_prerequisites
    create_export_dir

    echo ""
    print_info "Starting export process..."
    echo ""

    export_encryption_key
    export_env_vars
    export_workflows_api
    export_database
    export_pv_data
    export_resources
    create_checksums
    create_summary

    cd ..

    # Create compressed archive
    print_info "Creating compressed archive..."
    tar -czf "${EXPORT_DIR}.tar.gz" "$EXPORT_DIR"

    echo ""
    echo "========================================="
    print_success "Export completed successfully!"
    echo "========================================="
    echo ""
    print_info "Export location: $(pwd)/$EXPORT_DIR"
    print_info "Archive created: $(pwd)/${EXPORT_DIR}.tar.gz"
    echo ""
    print_warning "NEXT STEPS:"
    echo "  1. Review: $EXPORT_DIR/EXPORT_SUMMARY.txt"
    echo "  2. Verify: cd $EXPORT_DIR && sha256sum -c checksums.txt"
    echo "  3. Transfer: scp ${EXPORT_DIR}.tar.gz user@gcp-instance:~/"
    echo "  4. Follow migration guide: migration/README.md"
    echo ""
    print_warning "CRITICAL: Secure the encryption_key.txt file!"
    echo ""
}

# Run main function
main

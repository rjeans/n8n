#!/bin/bash

################################################################################
# GCP Setup Script for n8n Terraform
#
# This script automates the GCP authentication and project setup for Terraform
#
# Usage: ./setup-gcp.sh
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

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed"
        print_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        print_info "Install from: https://www.terraform.io/downloads"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Authenticate with gcloud
authenticate_gcloud() {
    print_info "Checking gcloud authentication..."

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_warning "Not authenticated with gcloud"
        print_info "Opening browser for authentication..."
        gcloud auth login
    else
        local account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
        print_success "Already authenticated as: $account"
    fi
}

# Select or create project
setup_project() {
    print_info "Setting up GCP project..."

    local current_project=$(gcloud config get-value project 2>/dev/null || echo "")

    if [ -n "$current_project" ]; then
        print_info "Current project: $current_project"
        read -p "Use this project? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            current_project=""
        fi
    fi

    if [ -z "$current_project" ]; then
        echo ""
        print_info "Available projects:"
        gcloud projects list --format="table(projectId,name)"
        echo ""
        read -p "Enter project ID (or 'new' to create): " project_id

        if [ "$project_id" = "new" ]; then
            read -p "Enter new project ID: " new_project_id
            read -p "Enter project name: " project_name

            print_info "Creating project: $new_project_id"
            gcloud projects create "$new_project_id" --name="$project_name"
            project_id="$new_project_id"

            print_warning "Don't forget to enable billing for this project!"
            print_info "Go to: https://console.cloud.google.com/billing"
            read -p "Press Enter when billing is enabled..."
        fi

        gcloud config set project "$project_id"
    else
        project_id="$current_project"
    fi

    print_success "Using project: $project_id"
    export PROJECT_ID="$project_id"
}

# Enable required APIs
enable_apis() {
    print_info "Enabling required GCP APIs..."

    local apis=(
        "compute.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )

    for api in "${apis[@]}"; do
        print_info "Enabling: $api"
        gcloud services enable "$api" --project="$PROJECT_ID"
    done

    print_success "APIs enabled"
    print_info "Waiting for APIs to be fully active (30 seconds)..."
    sleep 30
}

# Setup Terraform authentication
setup_terraform_auth() {
    echo ""
    print_info "Setting up Terraform authentication..."
    echo ""
    echo "Choose authentication method:"
    echo "1) Application Default Credentials (Quick - Recommended for getting started)"
    echo "2) Service Account (Production - Recommended for production)"
    echo ""
    read -p "Select option (1 or 2): " auth_choice

    case $auth_choice in
        1)
            setup_adc
            ;;
        2)
            setup_service_account
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
}

# Setup Application Default Credentials
setup_adc() {
    print_info "Setting up Application Default Credentials..."

    gcloud auth application-default login

    print_success "Application Default Credentials configured"
    print_info "Terraform will use your personal Google credentials"
}

# Setup Service Account
setup_service_account() {
    print_info "Setting up Terraform service account..."

    local sa_name="terraform"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    local key_file="$HOME/terraform-gcp-key.json"

    # Check if service account exists
    if gcloud iam service-accounts describe "$sa_email" --project="$PROJECT_ID" &>/dev/null; then
        print_warning "Service account already exists: $sa_email"
        read -p "Use existing service account? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            return
        fi
    else
        # Create service account
        print_info "Creating service account: $sa_name"
        gcloud iam service-accounts create "$sa_name" \
            --display-name="Terraform Service Account" \
            --description="Service account for Terraform infrastructure management" \
            --project="$PROJECT_ID"
    fi

    # Grant permissions
    print_info "Granting permissions..."

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$sa_email" \
        --role="roles/compute.admin" \
        --condition=None

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$sa_email" \
        --role="roles/iam.serviceAccountUser" \
        --condition=None

    # Create key
    if [ -f "$key_file" ]; then
        print_warning "Key file already exists: $key_file"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Using existing key file"
        else
            print_info "Creating new service account key..."
            gcloud iam service-accounts keys create "$key_file" \
                --iam-account="$sa_email" \
                --project="$PROJECT_ID"
        fi
    else
        print_info "Creating service account key..."
        gcloud iam service-accounts keys create "$key_file" \
            --iam-account="$sa_email" \
            --project="$PROJECT_ID"
    fi

    # Set environment variable
    export GOOGLE_APPLICATION_CREDENTIALS="$key_file"

    print_success "Service account configured"
    echo ""
    print_info "To make this permanent, add to your shell profile:"
    echo ""
    echo "  export GOOGLE_APPLICATION_CREDENTIALS=$key_file"
    echo ""

    # Detect shell
    local shell_profile=""
    if [ -n "${ZSH_VERSION:-}" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ -n "${BASH_VERSION:-}" ]; then
        shell_profile="$HOME/.bashrc"
    fi

    if [ -n "$shell_profile" ]; then
        read -p "Add to $shell_profile now? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "" >> "$shell_profile"
            echo "# GCP Terraform credentials" >> "$shell_profile"
            echo "export GOOGLE_APPLICATION_CREDENTIALS=$key_file" >> "$shell_profile"
            print_success "Added to $shell_profile"
            print_warning "Run: source $shell_profile (or restart your terminal)"
        fi
    fi
}

# Verify Terraform can authenticate
verify_terraform() {
    print_info "Verifying Terraform authentication..."

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local terraform_dir="$(dirname "$script_dir")/infra/terraform"

    if [ ! -d "$terraform_dir" ]; then
        print_warning "Terraform directory not found: $terraform_dir"
        return
    fi

    cd "$terraform_dir"

    # Initialize Terraform
    print_info "Initializing Terraform..."
    if terraform init; then
        print_success "Terraform initialized successfully"
    else
        print_error "Terraform initialization failed"
        return 1
    fi

    # Validate
    print_info "Validating Terraform configuration..."
    if terraform validate; then
        print_success "Terraform validation passed"
    else
        print_warning "Terraform validation had issues"
    fi
}

# Create terraform.tfvars if needed
setup_terraform_vars() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local terraform_dir="$(dirname "$script_dir")/infra/terraform"
    local tfvars_file="$terraform_dir/terraform.tfvars"

    if [ -f "$tfvars_file" ]; then
        print_info "terraform.tfvars already exists"
        return
    fi

    print_info "Creating terraform.tfvars..."

    # Get SSH public key
    local ssh_key=""
    if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
        ssh_key=$(cat "$HOME/.ssh/id_rsa.pub")
    elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        ssh_key=$(cat "$HOME/.ssh/id_ed25519.pub")
    else
        print_warning "No SSH public key found"
        print_info "Generate one with: ssh-keygen -t rsa -b 4096"
        ssh_key="YOUR_SSH_PUBLIC_KEY_HERE"
    fi

    # Create tfvars file
    cat > "$tfvars_file" <<EOF
# GCP Project Configuration
project_id = "$PROJECT_ID"
region     = "us-central1"  # Free tier eligible
zone       = "us-central1-a"

# Instance Configuration
instance_name = "n8n-server"
machine_type  = "e2-micro"  # Free tier eligible
environment   = "production"

# Disk Configuration
boot_disk_size_gb = 10
data_disk_size_gb = 20

# SSH Configuration
ssh_user       = "ubuntu"
ssh_public_key = "$ssh_key"

# Security: Restrict SSH to your IP (optional)
ssh_source_ranges = []

# Static IP (optional)
use_static_ip = false
EOF

    print_success "Created: $tfvars_file"
    print_info "Review and edit if needed: $tfvars_file"
}

# Main function
main() {
    echo ""
    echo "========================================="
    echo "  GCP Setup for n8n Terraform"
    echo "========================================="
    echo ""

    check_prerequisites
    authenticate_gcloud
    setup_project
    enable_apis
    setup_terraform_auth
    setup_terraform_vars
    verify_terraform

    echo ""
    echo "========================================="
    print_success "GCP setup completed successfully!"
    echo "========================================="
    echo ""
    print_info "Next steps:"
    echo "  1. Review terraform.tfvars: infra/terraform/terraform.tfvars"
    echo "  2. Run: cd infra/terraform"
    echo "  3. Run: terraform plan"
    echo "  4. Run: terraform apply"
    echo ""
    print_info "Project ID: $PROJECT_ID"
    echo ""
}

# Run main function
main

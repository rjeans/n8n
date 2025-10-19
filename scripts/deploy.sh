#!/bin/bash

################################################################################
# n8n Deployment Script
#
# This script handles the complete deployment of the n8n stack on GCP
#
# Usage: ./deploy.sh [options]
# Options:
#   --fresh     Fresh deployment (will create directories)
#   --update    Update existing deployment
#   --restart   Restart all services
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"
DATA_DIR="/mnt/data"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root. This is not recommended."
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        print_info "Install with: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi

    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed"
        print_info "Install with: sudo apt install docker-compose-plugin -y"
        exit 1
    fi

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        print_info "Start with: sudo systemctl start docker"
        exit 1
    fi

    # Check if user is in docker group
    if ! groups | grep -q docker; then
        print_warning "User is not in docker group"
        print_info "Add to group: sudo usermod -aG docker $USER"
        print_info "Then logout and login again"
    fi

    print_success "Prerequisites check passed"
}

# Setup data directories
setup_directories() {
    print_info "Setting up data directories..."

    # Check if data disk is mounted
    if ! mountpoint -q "$DATA_DIR"; then
        print_error "Data disk not mounted at $DATA_DIR"
        print_info "Mount it first or check Terraform startup script"
        exit 1
    fi

    # Create required directories
    sudo mkdir -p "$DATA_DIR/n8n"
    sudo mkdir -p "$DATA_DIR/postgres"
    sudo mkdir -p "$DATA_DIR/backups"

    # Set permissions
    sudo chown -R $USER:$USER "$DATA_DIR/n8n"
    sudo chown -R $USER:$USER "$DATA_DIR/backups"
    sudo chmod -R 755 "$DATA_DIR/n8n"
    sudo chmod -R 755 "$DATA_DIR/backups"

    # PostgreSQL needs specific permissions
    sudo chown -R 999:999 "$DATA_DIR/postgres" 2>/dev/null || true
    sudo chmod -R 700 "$DATA_DIR/postgres"

    print_success "Data directories created"
}

# Check environment file
check_env_file() {
    print_info "Checking environment configuration..."

    if [ ! -f "$DOCKER_DIR/.env" ]; then
        print_error "Environment file not found: $DOCKER_DIR/.env"
        print_info "Copy from example: cp $DOCKER_DIR/.env.example $DOCKER_DIR/.env"
        print_info "Then edit with your values: nano $DOCKER_DIR/.env"
        exit 1
    fi

    # Check for placeholder values
    if grep -q "CHANGE_THIS" "$DOCKER_DIR/.env"; then
        print_error "Environment file contains placeholder values"
        print_info "Edit: $DOCKER_DIR/.env"
        print_info "Replace all CHANGE_THIS values with actual configuration"
        exit 1
    fi

    # Verify critical variables
    source "$DOCKER_DIR/.env"

    if [ -z "${N8N_ENCRYPTION_KEY:-}" ]; then
        print_error "N8N_ENCRYPTION_KEY is not set"
        exit 1
    fi

    if [ -z "${POSTGRES_PASSWORD:-}" ]; then
        print_error "POSTGRES_PASSWORD is not set"
        exit 1
    fi

    if [ -z "${N8N_HOST:-}" ]; then
        print_error "N8N_HOST is not set"
        exit 1
    fi

    print_success "Environment configuration validated"
}

# Pull latest images
pull_images() {
    print_info "Pulling latest Docker images..."

    cd "$DOCKER_DIR"
    docker compose pull

    print_success "Images pulled successfully"
}

# Deploy stack
deploy_stack() {
    print_info "Deploying n8n stack..."

    cd "$DOCKER_DIR"
    docker compose up -d

    print_success "Stack deployed"
}

# Wait for services
wait_for_services() {
    print_info "Waiting for services to be ready..."

    cd "$DOCKER_DIR"

    # Wait for PostgreSQL
    print_info "Waiting for PostgreSQL..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker compose exec -T postgres pg_isready -U n8n &> /dev/null; then
            print_success "PostgreSQL is ready"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    if [ $attempt -eq $max_attempts ]; then
        print_error "PostgreSQL failed to start"
        return 1
    fi

    # Wait for n8n
    print_info "Waiting for n8n..."
    attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf http://localhost:5678/healthz &> /dev/null; then
            print_success "n8n is ready"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    if [ $attempt -eq $max_attempts ]; then
        print_warning "n8n may not be fully ready yet"
    fi

    print_success "Services are ready"
}

# Show status
show_status() {
    print_info "Service status:"
    cd "$DOCKER_DIR"
    docker compose ps

    echo ""
    print_info "Resource usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

    echo ""
    print_info "Disk usage:"
    df -h "$DATA_DIR"
}

# Show logs
show_logs() {
    print_info "Recent logs:"
    cd "$DOCKER_DIR"
    docker compose logs --tail=50
}

# Main deployment function
deploy() {
    echo ""
    echo "========================================="
    echo "  n8n Deployment Script"
    echo "========================================="
    echo ""

    check_root
    check_prerequisites
    setup_directories
    check_env_file
    pull_images
    deploy_stack
    wait_for_services

    echo ""
    echo "========================================="
    print_success "Deployment completed successfully!"
    echo "========================================="
    echo ""

    show_status

    echo ""
    print_info "n8n is now accessible at: https://${N8N_HOST}"
    print_info "Login with credentials from .env file"
    echo ""
    print_info "Useful commands:"
    echo "  View logs:      cd $DOCKER_DIR && docker compose logs -f"
    echo "  Restart:        cd $DOCKER_DIR && docker compose restart"
    echo "  Stop:           cd $DOCKER_DIR && docker compose down"
    echo "  Backup:         $SCRIPT_DIR/backup.sh"
    echo ""
}

# Update function
update() {
    echo ""
    echo "========================================="
    echo "  n8n Update Script"
    echo "========================================="
    echo ""

    print_info "Creating backup before update..."
    "$SCRIPT_DIR/backup.sh"

    print_info "Pulling latest images..."
    cd "$DOCKER_DIR"
    docker compose pull

    print_info "Restarting services..."
    docker compose up -d

    wait_for_services
    show_status

    print_success "Update completed!"
}

# Restart function
restart() {
    echo ""
    echo "========================================="
    echo "  n8n Restart Script"
    echo "========================================="
    echo ""

    cd "$DOCKER_DIR"
    docker compose restart

    wait_for_services
    show_status

    print_success "Restart completed!"
}

# Parse arguments
case "${1:-}" in
    --fresh)
        deploy
        ;;
    --update)
        update
        ;;
    --restart)
        restart
        ;;
    --status)
        show_status
        ;;
    --logs)
        show_logs
        ;;
    --help)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  --fresh     Fresh deployment (setup directories, deploy stack)"
        echo "  --update    Update deployment (backup, pull images, restart)"
        echo "  --restart   Restart all services"
        echo "  --status    Show service status"
        echo "  --logs      Show recent logs"
        echo "  --help      Show this help message"
        echo ""
        ;;
    *)
        print_error "Invalid option: ${1:-}"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

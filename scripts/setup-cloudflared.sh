#!/bin/bash

################################################################################
# Cloudflare Tunnel Setup Script
#
# This script helps configure Cloudflare Tunnel for n8n
#
# Usage: ./setup-cloudflared.sh
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

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if cloudflared CLI is installed
check_cloudflared_cli() {
    if command -v cloudflared &> /dev/null; then
        print_success "cloudflared CLI is installed"
        return 0
    else
        print_warning "cloudflared CLI is not installed"
        return 1
    fi
}

# Install cloudflared CLI
install_cloudflared() {
    print_info "Installing cloudflared CLI..."

    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Download and install for Linux
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared-linux-amd64.deb
        rm cloudflared-linux-amd64.deb
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        brew install cloudflared
    else
        print_error "Unsupported OS"
        return 1
    fi

    print_success "cloudflared CLI installed"
}

# Guide for token-based setup (recommended)
guide_token_setup() {
    echo ""
    echo "========================================="
    echo "  Token-Based Setup (Recommended)"
    echo "========================================="
    echo ""

    print_info "This is the easiest method - just copy a token from Cloudflare dashboard"
    echo ""

    echo "Steps:"
    echo ""
    echo "1. Login to Cloudflare Zero Trust Dashboard"
    print_info "   URL: https://one.dash.cloudflare.com/"
    echo ""

    echo "2. Navigate to Access → Tunnels"
    echo ""

    echo "3. Click 'Create a tunnel'"
    echo ""

    echo "4. Select 'Cloudflared' as connector type"
    echo ""

    echo "5. Give it a name (e.g., 'n8n-tunnel')"
    echo ""

    echo "6. Copy the tunnel token"
    print_warning "   The token is a long string starting with 'ey...'"
    echo ""

    echo "7. Configure the tunnel:"
    echo "   - Public hostname: n8n.yourdomain.com"
    echo "   - Service Type: HTTP"
    echo "   - Service URL: http://n8n:5678"
    echo ""

    echo "8. Add the token to your .env file:"
    print_info "   CLOUDFLARE_TUNNEL_TOKEN=<your-token-here>"
    echo ""

    echo "9. Restart the stack:"
    print_info "   cd $DOCKER_DIR && docker compose up -d"
    echo ""

    print_success "Done! Your tunnel should now be connected."
}

# Guide for config file setup (advanced)
guide_config_setup() {
    echo ""
    echo "========================================="
    echo "  Config File Setup (Advanced)"
    echo "========================================="
    echo ""

    print_info "This method gives you more control but requires more setup"
    echo ""

    if ! check_cloudflared_cli; then
        read -p "Install cloudflared CLI now? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_cloudflared
        else
            print_warning "You'll need cloudflared CLI for this method"
            return 1
        fi
    fi

    echo ""
    echo "Steps:"
    echo ""

    echo "1. Login to Cloudflare:"
    print_info "   cloudflared tunnel login"
    echo ""

    echo "2. Create a tunnel:"
    print_info "   cloudflared tunnel create n8n-tunnel"
    print_warning "   Note the Tunnel UUID from the output"
    echo ""

    echo "3. Create DNS record:"
    print_info "   cloudflared tunnel route dns n8n-tunnel n8n.yourdomain.com"
    echo ""

    echo "4. Locate credentials file:"
    print_info "   ~/.cloudflared/<TUNNEL-UUID>.json"
    echo ""

    echo "5. Copy credentials to project:"
    print_info "   cp ~/.cloudflared/<TUNNEL-UUID>.json $DOCKER_DIR/cloudflared/credentials.json"
    echo ""

    echo "6. Update config.yml:"
    print_info "   Edit: $DOCKER_DIR/cloudflared/config.yml"
    print_info "   Set tunnel UUID and hostname"
    echo ""

    echo "7. Update docker-compose.yml to use config file instead of token"
    echo ""

    echo "8. Restart the stack:"
    print_info "   cd $DOCKER_DIR && docker compose up -d"
    echo ""
}

# Check tunnel status
check_tunnel_status() {
    print_info "Checking tunnel status..."

    cd "$DOCKER_DIR"

    if ! docker compose ps | grep cloudflared | grep -q "Up"; then
        print_error "Cloudflared container is not running"
        echo ""
        print_info "Start it with: docker compose up -d cloudflared"
        print_info "Check logs: docker compose logs cloudflared"
        return 1
    fi

    print_success "Cloudflared container is running"

    echo ""
    print_info "Recent logs:"
    docker compose logs --tail=20 cloudflared

    echo ""
    print_info "Check full status in Cloudflare dashboard:"
    print_info "https://one.dash.cloudflare.com/ → Access → Tunnels"
}

# Test connection
test_connection() {
    local hostname="${1:-}"

    if [ -z "$hostname" ]; then
        # Try to get from .env
        if [ -f "$DOCKER_DIR/.env" ]; then
            hostname=$(grep N8N_HOST "$DOCKER_DIR/.env" | cut -d'=' -f2)
        fi

        if [ -z "$hostname" ]; then
            read -p "Enter your n8n hostname (e.g., n8n.yourdomain.com): " hostname
        fi
    fi

    echo ""
    print_info "Testing connection to: $hostname"
    echo ""

    # Check DNS resolution
    print_info "Checking DNS resolution..."
    if dig +short "$hostname" | grep -q .; then
        print_success "DNS resolves to: $(dig +short "$hostname" | head -n1)"
    else
        print_warning "DNS not resolving yet (may take a few minutes)"
    fi

    # Check HTTPS connection
    echo ""
    print_info "Checking HTTPS connection..."
    if curl -I -s "https://$hostname" | head -n1 | grep -q "200\|301\|302"; then
        print_success "HTTPS connection successful!"
        echo ""
        curl -I "https://$hostname" | head -n5
    else
        print_warning "Cannot connect via HTTPS yet"
        print_info "This may take a few minutes after tunnel setup"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "  Cloudflare Tunnel Setup"
    echo "========================================="
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "1) Token-based setup guide (Recommended)"
    echo "2) Config file setup guide (Advanced)"
    echo "3) Check tunnel status"
    echo "4) Test connection"
    echo "5) Exit"
    echo ""
    read -p "Select option (1-5): " choice

    case $choice in
        1)
            guide_token_setup
            ;;
        2)
            guide_config_setup
            ;;
        3)
            check_tunnel_status
            ;;
        4)
            test_connection
            ;;
        5)
            print_info "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            show_menu
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
    show_menu
}

# Main
main() {
    echo ""
    echo "========================================="
    echo "  Cloudflare Tunnel Setup Script"
    echo "========================================="
    echo ""

    print_info "This script will help you setup Cloudflare Tunnel for n8n"
    echo ""

    show_menu
}

main

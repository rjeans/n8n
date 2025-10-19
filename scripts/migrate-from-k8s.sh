#!/bin/bash

################################################################################
# n8n Migration Script - Import from Kubernetes
#
# This script imports data from a Kubernetes-based n8n instance
# Run this on the GCP instance after transferring the migration package
#
# Usage: ./migrate-from-k8s.sh <migration-package-dir>
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
MIGRATION_DIR="${1:-}"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate migration directory
validate_migration_dir() {
    if [ -z "$MIGRATION_DIR" ]; then
        print_error "No migration directory specified"
        echo "Usage: $0 <migration-package-dir>"
        exit 1
    fi

    if [ ! -d "$MIGRATION_DIR" ]; then
        print_error "Migration directory not found: $MIGRATION_DIR"
        exit 1
    fi

    print_info "Migration directory: $MIGRATION_DIR"
}

# Verify migration package
verify_package() {
    print_info "Verifying migration package..."

    local required_files=("database.sql.gz" "encryption_key.txt")
    local missing=0

    for file in "${required_files[@]}"; do
        if [ ! -f "$MIGRATION_DIR/$file" ]; then
            print_error "Missing required file: $file"
            missing=$((missing + 1))
        fi
    done

    if [ $missing -gt 0 ]; then
        print_error "Migration package incomplete"
        exit 1
    fi

    # Verify checksums if available
    if [ -f "$MIGRATION_DIR/checksums.txt" ]; then
        print_info "Verifying checksums..."
        cd "$MIGRATION_DIR"
        if sha256sum -c checksums.txt &> /dev/null || shasum -a 256 -c checksums.txt &> /dev/null; then
            print_success "Checksum verification passed"
        else
            print_warning "Checksum verification failed - proceed with caution"
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi

    print_success "Migration package verified"
}

# Check encryption key
check_encryption_key() {
    print_info "Checking encryption key..."

    local old_key=$(cat "$MIGRATION_DIR/encryption_key.txt")
    local new_key=$(grep N8N_ENCRYPTION_KEY "$DOCKER_DIR/.env" | cut -d'=' -f2)

    if [ "$old_key" != "$new_key" ]; then
        print_error "ENCRYPTION KEY MISMATCH!"
        echo ""
        print_error "Old key: $old_key"
        print_error "New key: $new_key"
        echo ""
        print_error "The encryption keys DO NOT match!"
        print_error "Credentials will NOT be accessible if you continue."
        echo ""
        print_warning "You MUST update the .env file with the correct encryption key."
        print_info "Edit: nano $DOCKER_DIR/.env"
        print_info "Set: N8N_ENCRYPTION_KEY=$old_key"
        exit 1
    fi

    print_success "Encryption key verified - keys match!"
}

# Stop n8n service
stop_n8n() {
    print_info "Stopping n8n service..."

    cd "$DOCKER_DIR"
    docker compose stop n8n

    print_success "n8n stopped"
}

# Start n8n service
start_n8n() {
    print_info "Starting n8n service..."

    cd "$DOCKER_DIR"
    docker compose up -d n8n

    # Wait for n8n to be ready
    print_info "Waiting for n8n to be ready..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf http://localhost:5678/healthz &> /dev/null; then
            print_success "n8n is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    print_warning "n8n may not be fully ready yet"
}

# Restore database
restore_database() {
    print_info "Restoring PostgreSQL database..."

    # Ensure PostgreSQL is running
    cd "$DOCKER_DIR"
    docker compose up -d postgres

    # Wait for PostgreSQL
    print_info "Waiting for PostgreSQL to be ready..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker compose exec -T postgres pg_isready -U n8n &> /dev/null; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    # Copy database backup to container accessible location
    print_info "Preparing database backup..."
    sudo mkdir -p /mnt/data/migration
    sudo cp "$MIGRATION_DIR/database.sql.gz" /mnt/data/migration/
    sudo gunzip -f /mnt/data/migration/database.sql.gz

    # Create a backup of current database (just in case)
    print_info "Creating backup of current database..."
    docker compose exec -T postgres pg_dump -U n8n n8n > /mnt/data/migration/pre_migration_backup.sql || true

    # Restore database
    print_info "Importing database..."
    docker compose exec -T postgres psql -U n8n -d n8n < /mnt/data/migration/database.sql

    # Verify restoration
    print_info "Verifying database restoration..."
    local workflow_count=$(docker compose exec -T postgres psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM workflow_entity;" | tr -d ' ')
    local execution_count=$(docker compose exec -T postgres psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM execution_entity;" | tr -d ' ')

    print_success "Database restored successfully"
    print_info "Workflows: $workflow_count"
    print_info "Executions: $execution_count"
}

# Import workflows (if available)
import_workflows() {
    if [ -f "$MIGRATION_DIR/workflows_export.json" ]; then
        print_info "Workflow JSON export found..."
        print_warning "Workflows should already be in the database"
        print_info "Skipping separate workflow import"
    else
        print_info "No separate workflow export found (normal if using database restore)"
    fi
}

# Verify migration
verify_migration() {
    print_info "Verifying migration..."

    cd "$DOCKER_DIR"

    # Check containers
    if ! docker compose ps | grep -q "n8n.*Up"; then
        print_error "n8n container is not running"
        return 1
    fi

    # Check n8n health
    if ! curl -sf http://localhost:5678/healthz &> /dev/null; then
        print_warning "n8n health check failed - may still be starting"
    fi

    # Check database connection
    if docker compose exec -T postgres psql -U n8n -d n8n -c "SELECT 1;" &> /dev/null; then
        print_success "Database connection verified"
    else
        print_error "Database connection failed"
        return 1
    fi

    print_success "Migration verification passed"
}

# Create migration report
create_report() {
    print_info "Creating migration report..."

    local report_file="/mnt/data/migration/migration_report_$(date +%Y%m%d_%H%M%S).txt"

    cat > "$report_file" <<EOF
n8n Migration Report
====================
Migration Date: $(date)
Source: Kubernetes cluster
Target: GCP e2-micro instance

Migration Package:
------------------
Source: $MIGRATION_DIR
$(ls -lh "$MIGRATION_DIR")

Database Statistics:
--------------------
Workflows: $(docker compose -f "$DOCKER_DIR/docker-compose.yml" exec -T postgres psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM workflow_entity;" | tr -d ' ')
Credentials: $(docker compose -f "$DOCKER_DIR/docker-compose.yml" exec -T postgres psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM credentials_entity;" | tr -d ' ')
Executions: $(docker compose -f "$DOCKER_DIR/docker-compose.yml" exec -T postgres psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM execution_entity;" | tr -d ' ')
Database Size: $(docker compose -f "$DOCKER_DIR/docker-compose.yml" exec -T postgres psql -U n8n -d n8n -t -c "SELECT pg_size_pretty(pg_database_size('n8n'));" | tr -d ' ')

Service Status:
---------------
$(cd "$DOCKER_DIR" && docker compose ps)

System Resources:
-----------------
$(df -h /mnt/data)

Container Resources:
--------------------
$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}")

Encryption Key:
---------------
Verified: ✓ (keys match)

Next Steps:
-----------
1. Test n8n access: https://$(grep N8N_HOST "$DOCKER_DIR/.env" | cut -d'=' -f2)
2. Login and verify workflows are visible
3. Test workflow execution
4. Verify credentials decrypt correctly
5. Update webhook URLs in external systems
6. Monitor for 24-48 hours
7. Decommission old K8s instance after validation

Validation Checklist:
---------------------
[ ] Login to n8n UI successful
[ ] All workflows visible
[ ] Workflow count matches source
[ ] All credentials accessible
[ ] Test workflow executes successfully
[ ] Webhook endpoints working
[ ] No errors in logs
[ ] Cloudflare Tunnel connected
[ ] HTTPS access working
[ ] Backups scheduled

Rollback Instructions:
----------------------
If migration fails:
1. Stop GCP instance: cd $DOCKER_DIR && docker compose down
2. Restore from backup: /mnt/data/migration/pre_migration_backup.sql
3. Restart K8s instance
4. Investigate issues before retry

Support:
--------
- Logs: docker compose logs -f
- Database: docker compose exec postgres psql -U n8n n8n
- Troubleshooting: $PROJECT_DIR/docs/TROUBLESHOOTING.md
EOF

    print_success "Migration report created: $report_file"
    echo ""
    cat "$report_file"
}

# Main migration function
main() {
    echo ""
    echo "========================================="
    echo "  n8n Migration Script"
    echo "  Kubernetes → GCP"
    echo "========================================="
    echo ""

    validate_migration_dir
    verify_package

    echo ""
    print_warning "CRITICAL PRE-FLIGHT CHECKS"
    echo ""

    check_encryption_key

    echo ""
    print_warning "This will:"
    print_warning "1. Stop the current n8n instance"
    print_warning "2. Replace the database with K8s data"
    print_warning "3. Restart n8n"
    echo ""
    read -p "Are you sure you want to continue? (yes/NO) " -r
    echo

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Migration cancelled"
        exit 0
    fi

    echo ""
    print_info "Starting migration process..."
    echo ""

    stop_n8n
    restore_database
    import_workflows
    start_n8n
    verify_migration

    echo ""
    echo "========================================="
    print_success "Migration completed successfully!"
    echo "========================================="
    echo ""

    create_report

    echo ""
    print_info "Next steps:"
    echo "  1. Login to n8n: https://$(grep N8N_HOST "$DOCKER_DIR/.env" | cut -d'=' -f2)"
    echo "  2. Verify all workflows are present"
    echo "  3. Test workflow execution"
    echo "  4. Check credentials decrypt correctly"
    echo "  5. Monitor logs: cd $DOCKER_DIR && docker compose logs -f"
    echo ""
    print_warning "Keep K8s instance running until fully validated!"
    echo ""
}

# Run main function
main

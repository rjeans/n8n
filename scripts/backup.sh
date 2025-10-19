#!/bin/bash

################################################################################
# n8n Backup Script
#
# This script creates backups of:
# - PostgreSQL database
# - n8n data directory
# - Docker configurations
#
# Usage: ./backup.sh [--retention-days 30]
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
BACKUP_DIR="/mnt/data/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS="${2:-30}"  # Default: keep backups for 30 days

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create backup directory
create_backup_dir() {
    local backup_path="$BACKUP_DIR/$TIMESTAMP"
    mkdir -p "$backup_path"
    echo "$backup_path"
}

# Backup PostgreSQL database
backup_database() {
    local backup_path="$1"
    print_info "Backing up PostgreSQL database..."

    cd "$DOCKER_DIR"

    # Create database dump
    docker compose exec -T postgres pg_dump -U n8n n8n > "$backup_path/database.sql"

    if [ ! -s "$backup_path/database.sql" ]; then
        print_error "Database backup failed - file is empty"
        return 1
    fi

    # Compress database dump
    gzip "$backup_path/database.sql"

    local size=$(du -h "$backup_path/database.sql.gz" | cut -f1)
    print_success "Database backup created: database.sql.gz ($size)"
}

# Backup n8n data directory
backup_n8n_data() {
    local backup_path="$1"
    print_info "Backing up n8n data directory..."

    # Create tar archive of n8n data
    tar -czf "$backup_path/n8n_data.tar.gz" -C /mnt/data n8n

    local size=$(du -h "$backup_path/n8n_data.tar.gz" | cut -f1)
    print_success "n8n data backup created: n8n_data.tar.gz ($size)"
}

# Backup Docker configurations
backup_docker_configs() {
    local backup_path="$1"
    print_info "Backing up Docker configurations..."

    # Copy docker-compose.yml
    cp "$DOCKER_DIR/docker-compose.yml" "$backup_path/"

    # Copy .env (with sensitive data)
    cp "$DOCKER_DIR/.env" "$backup_path/"

    # Copy cloudflared config if exists
    if [ -f "$DOCKER_DIR/cloudflared/config.yml" ]; then
        mkdir -p "$backup_path/cloudflared"
        cp "$DOCKER_DIR/cloudflared/config.yml" "$backup_path/cloudflared/"
    fi

    print_success "Docker configurations backed up"
}

# Create backup manifest
create_manifest() {
    local backup_path="$1"
    print_info "Creating backup manifest..."

    cat > "$backup_path/MANIFEST.txt" <<EOF
n8n Backup Manifest
===================
Backup Date: $(date)
Backup Path: $backup_path

Contents:
---------
$(ls -lh "$backup_path")

Checksums:
----------
$(cd "$backup_path" && sha256sum * 2>/dev/null || shasum -a 256 * 2>/dev/null)

System Info:
------------
Hostname: $(hostname)
Docker Version: $(docker --version)
Docker Compose Version: $(docker compose version)

Service Status:
---------------
$(cd "$DOCKER_DIR" && docker compose ps)

Disk Usage:
-----------
$(df -h /mnt/data)

Database Size:
--------------
$(docker compose exec -T postgres psql -U n8n -d n8n -c "SELECT pg_size_pretty(pg_database_size('n8n')) as size;" 2>/dev/null || echo "N/A")

Workflow Count:
---------------
$(docker compose exec -T postgres psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null || echo "N/A")

Execution Count:
----------------
$(docker compose exec -T postgres psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM execution_entity;" 2>/dev/null || echo "N/A")

Restoration:
------------
To restore this backup:
1. Extract database: gunzip database.sql.gz
2. Restore database: docker compose exec -T postgres psql -U n8n n8n < database.sql
3. Extract n8n data: tar -xzf n8n_data.tar.gz -C /mnt/data
4. Restart services: docker compose restart
EOF

    print_success "Manifest created"
}

# Cleanup old backups
cleanup_old_backups() {
    print_info "Cleaning up backups older than $RETENTION_DAYS days..."

    local deleted=0
    while IFS= read -r -d '' backup; do
        rm -rf "$backup"
        deleted=$((deleted + 1))
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -print0)

    if [ $deleted -gt 0 ]; then
        print_success "Deleted $deleted old backup(s)"
    else
        print_info "No old backups to delete"
    fi
}

# Verify backup
verify_backup() {
    local backup_path="$1"
    print_info "Verifying backup..."

    # Check if all expected files exist
    local files=("database.sql.gz" "n8n_data.tar.gz" "docker-compose.yml" ".env" "MANIFEST.txt")
    local all_present=true

    for file in "${files[@]}"; do
        if [ ! -f "$backup_path/$file" ]; then
            print_warning "Missing file: $file"
            all_present=false
        fi
    done

    # Check if files are not empty
    for file in "${files[@]}"; do
        if [ -f "$backup_path/$file" ] && [ ! -s "$backup_path/$file" ]; then
            print_warning "Empty file: $file"
            all_present=false
        fi
    done

    if [ "$all_present" = true ]; then
        print_success "Backup verification passed"
        return 0
    else
        print_error "Backup verification failed"
        return 1
    fi
}

# Create compressed archive (optional)
create_archive() {
    local backup_path="$1"
    print_info "Creating compressed archive..."

    cd "$BACKUP_DIR"
    tar -czf "${TIMESTAMP}.tar.gz" "$TIMESTAMP"

    local size=$(du -h "${TIMESTAMP}.tar.gz" | cut -f1)
    print_success "Archive created: ${TIMESTAMP}.tar.gz ($size)"
}

# Main backup function
main() {
    echo ""
    echo "========================================="
    echo "  n8n Backup Script"
    echo "========================================="
    echo ""
    print_info "Starting backup process..."
    print_info "Timestamp: $TIMESTAMP"
    print_info "Retention: $RETENTION_DAYS days"
    echo ""

    # Check if docker-compose is running
    cd "$DOCKER_DIR"
    if ! docker compose ps | grep -q "Up"; then
        print_error "Docker services are not running"
        exit 1
    fi

    # Create backup
    local backup_path=$(create_backup_dir)
    print_info "Backup path: $backup_path"
    echo ""

    backup_database "$backup_path"
    backup_n8n_data "$backup_path"
    backup_docker_configs "$backup_path"
    create_manifest "$backup_path"

    echo ""
    if verify_backup "$backup_path"; then
        # Optional: create archive
        # create_archive "$backup_path"

        echo ""
        print_info "Backup summary:"
        du -sh "$backup_path"
        echo ""
        print_info "Backup contents:"
        ls -lh "$backup_path"
    else
        print_error "Backup verification failed!"
        exit 1
    fi

    echo ""
    cleanup_old_backups

    echo ""
    echo "========================================="
    print_success "Backup completed successfully!"
    echo "========================================="
    echo ""
    print_info "Backup location: $backup_path"
    print_info "View manifest: cat $backup_path/MANIFEST.txt"
    echo ""
    print_info "To restore:"
    echo "  1. Stop services: cd $DOCKER_DIR && docker compose down"
    echo "  2. Restore database: gunzip -c $backup_path/database.sql.gz | docker compose exec -T postgres psql -U n8n n8n"
    echo "  3. Restore data: tar -xzf $backup_path/n8n_data.tar.gz -C /mnt/data"
    echo "  4. Start services: docker compose up -d"
    echo ""

    # Show disk usage
    print_info "Disk usage:"
    df -h /mnt/data
}

# Run main function
main

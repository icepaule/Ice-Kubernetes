#!/bin/bash
# Backup Docker volumes and databases before K3s migration
# Usage: ./backup-docker-volumes.sh [backup_dir]
#
# This script creates backups of:
# - Named Docker volumes (as tar archives)
# - PostgreSQL databases (as SQL dumps)
# - Docker Compose files and .env files

set -euo pipefail

BACKUP_DIR="${1:-/root/k3s-migration-backups/$(date +%Y%m%d_%H%M%S)}"

echo "=== Docker Migration Backup ==="
echo "Backup directory: $BACKUP_DIR"
echo "Date: $(date)"
echo ""

mkdir -p "$BACKUP_DIR"/{volumes,databases,compose-files}

# --- Backup Compose files and .env ---
echo "[1/3] Backing up Compose files..."

COMPOSE_DIRS=(
    "/root/stock-analyzer"
    "/root/ollama-cli"
    "/root/Ice-Leak-Monitoring"
    "/root/ebay-selling-assistant"
    "/root/epstein-research"
    "/root/xwiki-stack"
    "/root/tax-ai-stack"
    "/data/openarchiver/compose"
)
# Add IceDataEmphasise if it exists
[ -d "/home/mpauli/IceDataEmphasise" ] && COMPOSE_DIRS+=("/home/mpauli/IceDataEmphasise")

for dir in "${COMPOSE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        name=$(basename "$dir")
        echo "  Copying compose files from $dir..."
        mkdir -p "$BACKUP_DIR/compose-files/$name"
        cp "$dir"/docker-compose*.yml "$BACKUP_DIR/compose-files/$name/" 2>/dev/null || true
        cp "$dir"/.env "$BACKUP_DIR/compose-files/$name/.env" 2>/dev/null || true
        cp "$dir"/.env.* "$BACKUP_DIR/compose-files/$name/" 2>/dev/null || true
    fi
done

# --- Backup PostgreSQL databases ---
echo "[2/3] Backing up PostgreSQL databases..."

# XWiki PostgreSQL
if docker ps --format '{{.Names}}' | grep -q 'xwiki-db'; then
    echo "  Dumping XWiki database..."
    docker exec xwiki-db pg_dump -U xwiki xwiki > "$BACKUP_DIR/databases/xwiki.sql" 2>/dev/null || \
        echo "  WARNING: XWiki DB dump failed"
fi

# Tax-AI PostgreSQL
if docker ps --format '{{.Names}}' | grep -q 'tax-ai-stack-db'; then
    echo "  Dumping Tax-AI database..."
    docker exec tax-ai-stack-db-1 pg_dump -U paperless paperless > "$BACKUP_DIR/databases/tax-ai-paperless.sql" 2>/dev/null || \
        echo "  WARNING: Tax-AI DB dump failed"
fi

# OpenArchiver PostgreSQL
if docker ps --format '{{.Names}}' | grep -q 'oa-postgres'; then
    echo "  Dumping OpenArchiver database..."
    docker exec oa-postgres pg_dumpall -U postgres > "$BACKUP_DIR/databases/openarchiver.sql" 2>/dev/null || \
        echo "  WARNING: OpenArchiver DB dump failed"
fi

# --- Backup Docker volumes ---
echo "[3/3] Backing up Docker volumes..."

# Get list of named volumes (skip anonymous ones)
VOLUMES=$(docker volume ls --format '{{.Name}}' | grep -v '^[a-f0-9]\{64\}$' || true)

for vol in $VOLUMES; do
    echo "  Backing up volume: $vol"
    docker run --rm \
        -v "$vol":/source:ro \
        -v "$BACKUP_DIR/volumes":/backup \
        alpine tar czf "/backup/${vol}.tar.gz" -C /source . 2>/dev/null || \
        echo "  WARNING: Failed to backup volume $vol"
done

# --- Summary ---
echo ""
echo "=== Backup Complete ==="
echo "Location: $BACKUP_DIR"
echo ""
echo "Contents:"
du -sh "$BACKUP_DIR"/* 2>/dev/null
echo ""
echo "Total size:"
du -sh "$BACKUP_DIR"

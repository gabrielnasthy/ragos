#!/bin/bash
# RAGOS Web Admin - Backup Script
# This script backs up the database and configuration

set -e

INSTALL_DIR="/opt/ragos-web-admin"
BACKUP_DIR="/var/backups/ragos-web-admin"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/ragos-backup-$TIMESTAMP.tar.gz"

echo "======================================"
echo "RAGOS Web Admin Backup"
echo "======================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "[1/3] Backing up database..."
if [ -f "$INSTALL_DIR/database/ragos_web.db" ]; then
    sqlite3 "$INSTALL_DIR/database/ragos_web.db" ".backup '$BACKUP_DIR/ragos_web-$TIMESTAMP.db'"
    echo "Database backed up to: $BACKUP_DIR/ragos_web-$TIMESTAMP.db"
else
    echo "Warning: Database file not found"
fi

echo ""
echo "[2/3] Creating compressed archive..."
tar -czf "$BACKUP_FILE" \
    -C "$INSTALL_DIR" \
    database/ \
    config.py \
    2>/dev/null || echo "Warning: Some files may not exist"

echo "Backup archive created: $BACKUP_FILE"

echo ""
echo "[3/3] Cleaning old backups (keeping last 7 days)..."
find "$BACKUP_DIR" -name "ragos-backup-*.tar.gz" -mtime +7 -delete
find "$BACKUP_DIR" -name "ragos_web-*.db" -mtime +7 -delete
echo "Old backups cleaned"

echo ""
echo "======================================"
echo "Backup Complete!"
echo "======================================"
echo ""
echo "Backup location: $BACKUP_FILE"
echo "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
echo ""
echo "To restore from backup:"
echo "  1. Stop the service: systemctl stop ragos-web-admin"
echo "  2. Extract archive: tar -xzf $BACKUP_FILE -C $INSTALL_DIR"
echo "  3. Start the service: systemctl start ragos-web-admin"
echo ""

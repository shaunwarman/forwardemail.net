#!/bin/bash

set -e  # Exit script on any error

# Configuration
MONGO_HOST="localhost"      # Change if MongoDB is on a different host
MONGO_PORT="27017"          # Default MongoDB port
# MONGO_USER="your_user"    # If authentication is enabled
# MONGO_PASS="your_password"
# MONGO_DB="your_database"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
RETENTION_DAYS=7
CONTAINER_BACKUP_DIR="/backups"
BACKUP_DIR="$HOME/forwardemail.net/mongo-backups"
BACKUP_NAME="mongo-backup-$TIMESTAMP"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
TAR_FILE="$BACKUP_DIR/$BACKUP_NAME.tgz"

USE_S3=true
S3_BUCKET="forwardemail-selfhosted"
S3_PATH="s3://$S3_BUCKET/mongo-backups/"
AWS_S3_ENDPOINT="https://xxx.r2.cloudflarestorage.com"

# */5 * * * * $HOME/forwardemail.net/self-hosting/scripts/backup-mongo.sh >> /var/log/mongo-backup.log 2>&1

# NOTE: restore
# aws s3 cp s3://forwardemail-selfhosted/mongo-backups/mongo-backup-YYYY-MM-DD_HH-MM.tgz /tmp/mongo-backup.tgz --profile cloudflare --endpoint-url $AWS_S3_ENDPOINT
# tar -xzf /tmp/mongo-backup.tgz -C /tmp
# docker exec -i mongodb mongorestore --drop --dir "/tmp/mongo-backup-YYYY-MM-DD_HH-MM"

echo "Starting MongoDB backup..."
docker exec mongodb mongodump --out "$CONTAINER_BACKUP_DIR/$BACKUP_NAME"

echo "Compressing backup..."
tar -czf "$TAR_FILE" -C "$BACKUP_DIR" "$BACKUP_NAME"

echo "Cleaning up uncompressed backup..."
rm -rf "$BACKUP_PATH"

# Delete old backups
echo "Removing backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "mongo-backup-*.tgz" -mtime +$RETENTION_DAYS -exec rm -f {} \;

# Upload to S3 if enabled
if [[ "$USE_S3" == true ]]; then
    echo "Uploading to S3..."
    
    aws s3api create-bucket --bucket "$S3_BUCKET" --endpoint-url "$AWS_S3_ENDPOINT" 2>/dev/null || true
    if aws s3 cp "$TAR_FILE" "$S3_PATH" --profile cloudflare --endpoint-url "$AWS_S3_ENDPOINT"; then
        echo "Backup successfully uploaded to S3: $S3_PATH"
    else
        echo "Error uploading backup to S3." >&2
        exit 1
    fi
fi

echo "MongoDB backup process completed!"

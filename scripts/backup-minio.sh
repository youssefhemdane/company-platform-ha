#!/bin/bash

source /home/ubuntoserver/scripts/vault-helper.sh

MINIO_URL="http://192.168.1.100:9000"
BUCKET="postgres-backups"
LOG="/home/ubuntoserver/scripts/alerts.log"
DATE=$(date '+%Y-%m-%d_%H-%M-%S')
BACKUP_FILE="/tmp/backup_${DATE}.sql"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG; }

# Configurer mc avec credentials depuis Vault
~/mc alias set myminio $MINIO_URL $MINIO_USER $MINIO_PASS &>/dev/null

# Backup PostgreSQL
log "💾 Backup PostgreSQL → MinIO"
docker exec postgres pg_dump -U $DB_USER -d $DB_NAME --clean --if-exists > $BACKUP_FILE 2>/dev/null

if [ ! -s $BACKUP_FILE ]; then
    log "❌ Backup échoué"
    exit 1
fi

# Envoyer vers MinIO
~/mc cp $BACKUP_FILE myminio/$BUCKET/ &>/dev/null

if [ $? -eq 0 ]; then
    log "✅ Backup envoyé vers MinIO: backup_${DATE}.sql"
    # Garder seulement les 10 derniers backups
    ~/mc ls myminio/$BUCKET/ | sort | head -n -10 | awk '{print $NF}' | \
        xargs -I{} ~/mc rm myminio/$BUCKET/{} &>/dev/null
else
    log "❌ Envoi MinIO échoué"
fi

rm -f $BACKUP_FILE

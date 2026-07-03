#!/bin/bash

# Récupérer les secrets depuis Vault
source /home/ubuntoserver/scripts/vault-helper.sh

VM2_IP="192.168.1.101"
VM2_USER="ubuntoserver"
LOG="/home/ubuntoserver/scripts/sync-manager.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG; }
check_vm1() { curl -s --max-time 3 http://192.168.1.100:8000/api/users &>/dev/null; return $?; }
check_vm2() { curl -s --max-time 3 http://$VM2_IP/api/users &>/dev/null; return $?; }

sync_to_vm2() {
    log "📤 Sync VM1 → VM2"
    docker exec postgres pg_dump -U $DB_USER -d $DB_NAME --clean --if-exists > /tmp/sync.sql 2>/dev/null
    scp /tmp/sync.sql $VM2_USER@$VM2_IP:/tmp/sync.sql &>/dev/null
    ssh $VM2_USER@$VM2_IP "docker exec -i postgres psql -U $DB_USER -d $DB_NAME < /tmp/sync.sql" &>/dev/null
    rm -f /tmp/sync.sql
    ssh $VM2_USER@$VM2_IP "rm -f /tmp/sync.sql" &>/dev/null
    log "✅ Sync VM1 → VM2 terminée"
}

restore_from_vm2() {
    log "⏳ VM1 revenu — VM2 reste MASTER 60s"
    touch /tmp/restoring
    sleep 60
    log "🔄 Récupération des données de VM2"
    ssh $VM2_USER@$VM2_IP "docker exec postgres pg_dump -U $DB_USER -d $DB_NAME --clean --if-exists" > /tmp/restore.sql 2>/dev/null
    docker exec -i postgres psql -U $DB_USER -d $DB_NAME < /tmp/restore.sql &>/dev/null
    rm -f /tmp/restore.sql
    ssh $VM2_USER@$VM2_IP "touch /tmp/vm1_is_master" &>/dev/null
    rm -f /tmp/restoring
    log "✅ VM1 restauré — VM1 redevient MASTER"
}

monitor() {
    local down=false
    while true; do
        if check_vm1; then
            if [ "$down" = true ]; then
                restore_from_vm2
                down=false
            fi
        else
            if [ "$down" = false ]; then
                log "⚠️ VM1 API DOWN — VM2 devient MASTER"
                ssh $VM2_USER@$VM2_IP "rm -f /tmp/vm1_is_master" &>/dev/null
                down=true
            fi
        fi
        sleep 10
    done
}

scheduler() {
    while true; do
        sleep 30
        if check_vm1 && [ ! -f /tmp/restoring ]; then
            sync_to_vm2
        fi
    done
}

case "$1" in
    start)
        log "🚀 Démarrage Sync Manager VM1"
        ssh $VM2_USER@$VM2_IP "touch /tmp/vm1_is_master" &>/dev/null
        monitor &
        scheduler &
        wait
        ;;
    stop)
        pkill -f sync-manager
        log "🛑 Arrêté"
        ;;
    status)
        echo "VM1 API: $(check_vm1 && echo MASTER || echo DOWN)"
        echo "VM2 API: $(check_vm2 && echo UP || echo DOWN)"
        ;;
esac

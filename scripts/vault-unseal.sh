#!/bin/bash
VAULT_ADDR="http://127.0.0.1:8200"
UNSEAL_KEY="${VAULT_UNSEAL_KEY}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "Attente demarrage Vault..."
until curl -s $VAULT_ADDR/v1/sys/health &>/dev/null; do
    sleep 2
done

SEALED=$(curl -s $VAULT_ADDR/v1/sys/health | python3 -c "import sys,json; print(json.load(sys.stdin).get('sealed', True))")

if [ "$SEALED" = "True" ]; then
    log "Vault scelle - unseal en cours..."
    docker exec -e VAULT_ADDR=$VAULT_ADDR vault vault operator unseal $UNSEAL_KEY
    log "Vault deverouille"
else
    log "Vault deja deverouille"
fi

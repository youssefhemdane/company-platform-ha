#!/bin/bash
VAULT_ADDR="http://192.168.1.100:8200"
VAULT_TOKEN="${VAULT_TOKEN}"

get_secret() {
    local path="$1"
    local key="$2"
    curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/$path" | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['data']['data']['$key'])"
}

export DB_USER=$(get_secret "secret/data/postgres" "username")
export DB_PASS=$(get_secret "secret/data/postgres" "password")
export DB_NAME=$(get_secret "secret/data/postgres" "database")
export GMAIL_EMAIL=$(get_secret "secret/data/gmail" "email")
export GMAIL_PASS=$(get_secret "secret/data/gmail" "password")
export MINIO_USER=$(get_secret "secret/data/minio" "user")
export MINIO_PASS=$(get_secret "secret/data/minio" "password")
export TELEGRAM_TOKEN=$(get_secret "secret/data/telegram" "token")
export TELEGRAM_CHAT_ID=$(get_secret "secret/data/telegram" "chat_id")

#!/bin/bash

source /home/ubuntoserver/scripts/vault-helper.sh

EMAIL=$GMAIL_EMAIL
NTFY_TOPIC="youssef-vm1-alerts-2026"
LOG="/home/ubuntoserver/scripts/alerts.log"
VM2_IP="192.168.1.101"
VM2_USER="ubuntoserver"
THRESHOLD_CPU=80
THRESHOLD_RAM=80
THRESHOLD_DISK=90
THRESHOLD_LOW=50
CHECK_INTERVAL=10
OVERLOAD_DURATION=30
OVERLOAD_COUNT=$((OVERLOAD_DURATION / CHECK_INTERVAL))

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG; }

send_ntfy() {
    local title="$1"
    local message="$2"
    local priority="$3"
    local tags="$4"
    curl -s -H "Title: $title" -H "Priority: $priority" -H "Tags: $tags" \
         -d "$message" ntfy.sh/$NTFY_TOPIC &>/dev/null
}

send_telegram() {
    local title="$1"
    local message="$2"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" \
      -d text="$title
$message" &>/dev/null
}

send_alert() {
    local subject="$1"
    local message="$2"
    local priority="${3:-default}"
    local tags="${4:-warning}"
    log "📧📱✈️ ALERTE: $subject"
    echo -e "Subject: $subject\n\n$message" | msmtp $EMAIL
    send_ntfy "$subject" "$message" "$priority" "$tags"
    send_telegram "$subject" "$message"
}

get_cpu() { top -bn1 | grep "Cpu(s)" | awk '{print int($2)}'; }
get_ram() { free | grep Mem | awk '{print int($3/$2 * 100)}'; }
get_disk() { df / | tail -1 | awk '{print int($5)}'; }

switch_to_vm2() {
    log "🔄 Basculement trafic vers VM2"
    ssh $VM2_USER@$VM2_IP "sudo sed -i 's/server 192.168.1.100/server 192.168.1.101/' /etc/nginx/nginx.conf && sudo nginx -s reload" &>/dev/null
    send_alert "⚠️ VM1 SURCHARGÉE" \
    "Trafic basculé vers VM2 automatiquement.
CPU: $(get_cpu)% | RAM: $(get_ram)%" \
    "urgent" "rotating_light,computer"
}

switch_to_vm1() {
    log "✅ VM1 récupérée — Trafic revient sur VM1"
    ssh $VM2_USER@$VM2_IP "sudo sed -i 's/server 192.168.1.101/server 192.168.1.100/' /etc/nginx/nginx.conf && sudo nginx -s reload" &>/dev/null
    send_alert "✅ VM1 RÉCUPÉRÉE" \
    "Trafic revenu sur VM1.
CPU: $(get_cpu)% | RAM: $(get_ram)%" \
    "default" "white_check_mark,rocket"
}

log "🚀 Démarrage Monitor VM1"

overload_counter=0
is_overloaded=false
disk_was_critical=false
ram_was_critical=false

while true; do
    CPU=$(get_cpu)
    RAM=$(get_ram)
    DISK=$(get_disk)

    log "📊 CPU: ${CPU}% | RAM: ${RAM}% | DISK: ${DISK}%"

    if [ "$DISK" -gt "$THRESHOLD_DISK" ]; then
        if [ "$disk_was_critical" = false ]; then
            disk_was_critical=true
            send_alert "🔴 VM1 DISK CRITIQUE: ${DISK}%" \
            "Espace disque VM1 critique: ${DISK}%
Action requise immédiatement." \
            "urgent" "rotating_light,computer"
        fi
    else
        if [ "$disk_was_critical" = true ]; then
            disk_was_critical=false
            send_alert "✅ VM1 DISK NORMAL: ${DISK}%" \
            "Espace disque VM1 revenu à la normale: ${DISK}%" \
            "default" "white_check_mark"
        fi
    fi

    if [ "$RAM" -gt "$THRESHOLD_RAM" ]; then
        if [ "$ram_was_critical" = false ]; then
            ram_was_critical=true
            send_alert "🔴 VM1 RAM CRITIQUE: ${RAM}%" \
            "RAM VM1 critique: ${RAM}%
Seuil: ${THRESHOLD_RAM}%" \
            "urgent" "rotating_light,computer"
        fi
    else
        if [ "$ram_was_critical" = true ]; then
            ram_was_critical=false
            send_alert "✅ VM1 RAM NORMALE: ${RAM}%" \
            "RAM VM1 revenue à la normale: ${RAM}%" \
            "default" "white_check_mark"
        fi
    fi

    if [ "$is_overloaded" = false ]; then
        if [ "$CPU" -gt "$THRESHOLD_CPU" ] || [ "$RAM" -gt "$THRESHOLD_RAM" ]; then
            overload_counter=$((overload_counter + 1))
            log "⚠️ Surcharge détectée ($overload_counter/$OVERLOAD_COUNT) CPU:${CPU}% RAM:${RAM}%"
            if [ "$overload_counter" -ge "$OVERLOAD_COUNT" ]; then
                is_overloaded=true
                overload_counter=0
                switch_to_vm2
            fi
        else
            overload_counter=0
        fi
    else
        if [ "$CPU" -lt "$THRESHOLD_LOW" ] && [ "$RAM" -lt "$THRESHOLD_LOW" ]; then
            is_overloaded=false
            switch_to_vm1
        fi
    fi

    sleep $CHECK_INTERVAL
done

#!/bin/bash

CUSTOM_DNS="111.88.96.50 111.88.96.51"
POLL_INTERVAL=2

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local tag="$1" msg="$2" color="$3"
    echo -e "${NC}[$(date '+%H:%M:%S')] ${color}${tag}${NC} ${msg}"
}

run_nmcli() {
    local out ret
    out=$("$@" 2>&1)
    ret=$?
    if [ -n "$out" ]; then
        while IFS= read -r line; do
            log "[ OUTPUT ]" "$line" "$CYAN"
        done <<< "$out"
    fi
    return $ret
}

is_connected() {
    nmcli -t -f DEVICE,STATE device status 2>/dev/null \
        | grep -v -E "^(lo|p2p-dev-)" | grep -qE ":connected$"
}

get_active_connection() {
    local line
    line=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null \
        | grep -v "^lo:" | head -1)
    if [ -n "$line" ]; then
        echo "$line"
        return 0
    fi
    return 1
}

save_dns() {
    local conn="$1"
    OLD_DNS=$(nmcli -t -f ipv4.dns con show "$conn" 2>/dev/null | sed 's/^ipv4\.dns://')
    OLD_AUTO=$(nmcli -t -f ipv4.ignore-auto-dns con show "$conn" 2>/dev/null | sed 's/^ipv4\.ignore-auto-dns://')
}

apply_custom_dns() {
    local conn="$1" dev="$2"
    log "[ INFO ]" "Current DNS: ${OLD_DNS:-via DHCP}" "$CYAN"
    log "[ INFO ]" "Applying $CUSTOM_DNS ..." "$CYAN"
    run_nmcli nmcli con mod "$conn" ipv4.dns "$CUSTOM_DNS" ipv4.ignore-auto-dns yes
    if run_nmcli nmcli device reapply "$dev"; then
        log "[ OK ]" "DNS changed" "$GREEN"
    else
        run_nmcli nmcli con down "$conn"
        run_nmcli nmcli con up "$conn"
        log "[ OK ]" "DNS changed" "$GREEN"
    fi
}

restore_dns() {
    local conn="$1" dev="$2" dns="$3" auto="$4"
    log "[ INFO ]" "Restoring DNS for $conn ..." "$CYAN"
    run_nmcli nmcli con mod "$conn" ipv4.dns "$dns" ipv4.ignore-auto-dns "$auto"
    if [ -n "$dev" ]; then
        run_nmcli nmcli device reapply "$dev" || {
            run_nmcli nmcli con down "$conn"
            run_nmcli nmcli con up "$conn"
        }
    fi
    log "[ OK ]" "DNS restored" "$GREEN"
}

CONNECTED=false
CONN=""
DEV=""
OLD_DNS=""
OLD_AUTO=""

if is_connected; then
    INFO=$(get_active_connection)
    if [ -n "$INFO" ]; then
        CONNECTED=true
        CONN="${INFO%%:*}"
        DEV="${INFO##*:}"
        log "[ INFO ]" "Connection: $CONN  Device: $DEV" "$CYAN"
        save_dns "$CONN"
        apply_custom_dns "$CONN" "$DEV"
    fi
fi

log "[ INFO ]" "Waiting for network changes..." "$CYAN"

trap '
    echo ""
    if [ "$CONNECTED" = true ] && [ -n "$CONN" ]; then
        restore_dns "$CONN" "$DEV" "$OLD_DNS" "$OLD_AUTO"
    fi
    exit 0
' SIGINT

while true; do
    if is_connected; then
        INFO=$(get_active_connection)
        if [ -n "$INFO" ]; then
            NEW_CONN="${INFO%%:*}"
            NEW_DEV="${INFO##*:}"
            if [ "$CONNECTED" = false ]; then
                CONNECTED=true
                CONN="$NEW_CONN"
                DEV="$NEW_DEV"
                log "[ INFO ]" "Connected: $CONN  Device: $DEV" "$CYAN"
                save_dns "$CONN"
                apply_custom_dns "$CONN" "$DEV"
            elif [ "$CONN" != "$NEW_CONN" ]; then
                restore_dns "$CONN" "$DEV" "$OLD_DNS" "$OLD_AUTO"
                CONN="$NEW_CONN"
                DEV="$NEW_DEV"
                log "[ INFO ]" "Switched to: $CONN  Device: $DEV" "$CYAN"
                save_dns "$CONN"
                apply_custom_dns "$CONN" "$DEV"
            fi
        elif [ "$CONNECTED" = true ]; then
            CONNECTED=false
            log "[ INFO ]" "Disconnected: ${CONN:-unknown}" "$CYAN"
            if [ -n "$CONN" ]; then
                restore_dns "$CONN" "" "$OLD_DNS" "$OLD_AUTO"
            fi
        fi
    else
        if [ "$CONNECTED" = true ]; then
            CONNECTED=false
            log "[ INFO ]" "Disconnected: ${CONN:-unknown}" "$CYAN"
            if [ -n "$CONN" ]; then
                restore_dns "$CONN" "" "$OLD_DNS" "$OLD_AUTO"
            fi
        fi
    fi
    sleep "$POLL_INTERVAL"
done

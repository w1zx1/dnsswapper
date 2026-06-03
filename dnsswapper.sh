#!/bin/bash

LINE=$(nmcli -t -f NAME,DEVICE con show --active | head -1)
CONN="${LINE%%:*}"
DEV="${LINE##*:}"

if [ -z "$CONN" ]; then
    echo "No active connection found"
    exit 1
fi

echo "Connection: $CONN  Device: $DEV"

OLD_DNS=$(nmcli -t -f ipv4.dns con show "$CONN" | sed 's/^ipv4\.dns://')
OLD_AUTO=$(nmcli -t -f ipv4.ignore-auto-dns con show "$CONN" | sed 's/^ipv4\.ignore-auto-dns://')

echo "Current DNS: ${OLD_DNS:-DHCP}"
echo "Changing DNS to 111.88.96.50 / 111.88.96.51 ..."

nmcli con mod "$CONN" ipv4.dns "111.88.96.50 111.88.96.51" ipv4.ignore-auto-dns yes
nmcli device reapply "$DEV" 2>/dev/null || { nmcli con down "$CONN" && nmcli con up "$CONN"; }

trap '
    echo ""
    echo "Restoring DNS..."
    nmcli con mod "$CONN" ipv4.dns "$OLD_DNS" ipv4.ignore-auto-dns "$OLD_AUTO"
    nmcli device reapply "$DEV" 2>/dev/null || { nmcli con down "$CONN" && nmcli con up "$CONN"; }
    echo "DNS restored."
    exit 0
' SIGINT

echo "DNS changed. Press Ctrl+C to restore."

while true; do sleep 10; done

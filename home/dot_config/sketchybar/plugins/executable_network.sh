#!/bin/sh

source "$CONFIG_DIR/colors.sh"

# ── PATH explicite pour sketchybar (environnement minimal) ───
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

WIFI_IF="en0"

# ── 1. Ethernet (dock OWC) ───────────────────────────────────
ETH_IP=""
for iface in $(ifconfig -l 2>/dev/null); do
	case "$iface" in
		lo*|en0|utun*|bridge*|ap*|awdl*|llw*|anpi*|gif*|stf*|XHC*) continue ;;
		en*)
			ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
			if [ -n "$ip" ]; then
				ETH_IP="$ip"
				break
			fi
			;;
	esac
done

# ── 2. WiFi (en0) ────────────────────────────────────────────
WIFI_IP=$(ipconfig getifaddr "$WIFI_IF" 2>/dev/null)
WIFI_SSID=""
if [ -n "$WIFI_IP" ]; then
	WIFI_SSID=$(networksetup -listpreferredwirelessnetworks "$WIFI_IF" 2>/dev/null | grep -v '^Preferred networks on' | head -1 | xargs)
fi

# ── Priorité : Ethernet > WiFi ───────────────────────────────
if [ -n "$ETH_IP" ]; then
	ICON="􀤆"
	LABEL="Ethernet"
	CLR=$GREEN
elif [ -n "$WIFI_IP" ]; then
	ICON="􀙇"
	LABEL="${WIFI_SSID:-WiFi}"
	CLR=$GREEN
else
	ICON="􀙈"
	LABEL="Off"
	CLR=$RED
fi

sketchybar --set $NAME icon="$ICON" label="$LABEL" \
	icon.color=$CLR label.color=$CLR

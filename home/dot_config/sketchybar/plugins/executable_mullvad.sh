#!/bin/sh

source "$CONFIG_DIR/colors.sh"

# ── PATH explicite pour sketchybar (environnement minimal) ───
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:$PATH"

MULLVAD=$(command -v mullvad 2>/dev/null)

if [ -z "$MULLVAD" ]; then
	sketchybar --set $NAME icon="􀎥" label="N/A" \
		icon.color=$RED label.color=$RED
	exit 0
fi

STATUS=$($MULLVAD status 2>/dev/null)

if echo "$STATUS" | grep -q "Connected"; then
	# "Visible location:       France, Paris. IPv4: 193.32.126.239"
	# Extraire uniquement le pays (premier champ avant la virgule)
	# On utilise sed non-greedy : supprimer "Visible location:" + espaces
	COUNTRY=$(echo "$STATUS" | grep "Visible location" | sed 's/^.*Visible location:[[:space:]]*//' | cut -d',' -f1)
	if [ -z "$COUNTRY" ]; then
		COUNTRY="VPN"
	fi
	ICON="􀎡"
	CLR=$GREEN
	LABEL="$COUNTRY"

elif echo "$STATUS" | grep -q "Connecting"; then
	ICON="􀎡"
	CLR=$YELLOW
	LABEL="…"

else
	ICON="􀎥"
	CLR=$RED
	LABEL="Off"
fi

sketchybar --set $NAME icon="$ICON" label="$LABEL" \
	icon.color=$CLR label.color=$CLR

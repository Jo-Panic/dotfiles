#!/bin/bash

# ── Mullvad VPN ──────────────────────────────────────────────
# Clic → ouvre l'application Mullvad VPN.
# L'icône / la couleur / le label sont gérés par plugins/mullvad.sh
# en fonction de l'état du tunnel.

sketchybar --add item mullvad right \
	--set mullvad icon=􀎡 \
	icon.color=$GREEN \
	label.color=$GREEN \
	update_freq=10 \
	click_script="open -a 'Mullvad VPN'" \
	script="$PLUGIN_DIR/mullvad.sh"

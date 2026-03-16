#!/bin/bash

sketchybar --add item mullvad right \
	--set mullvad icon=􀎡 \
	icon.color=$GREEN \
	label.color=$GREEN \
	update_freq=10 \
	script="$PLUGIN_DIR/mullvad.sh"

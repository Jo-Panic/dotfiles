#!/bin/bash

sketchybar --add item network right \
	--set network icon=􀙇 \
	icon.color=$GREEN \
	label.color=$GREEN \
	update_freq=10 \
	script="$PLUGIN_DIR/network.sh" \
	--subscribe network wifi_change

#!/bin/bash

sketchybar --add item clock q \
	--set clock update_freq=10 \
	icon=􀉉 \
	icon.color=$TEXT \
	label.color=$TEXT \
	label.font="SF Pro:Semibold:13.0" \
	background.color=$ITEM_BG_COLOR \
	background.border_width=0 \
	script="$PLUGIN_DIR/clock.sh" \
	padding_right=24

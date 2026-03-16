#!/bin/bash

sketchybar --add item front_app e \
	--set front_app icon.font="sketchybar-app-font:Regular:14.0" \
	background.color=$ACCENT_BG \
	background.border_width=1 \
	background.border_color=$BAR_BORDER_COLOR \
	icon.color=$BLUE \
	label.color=$TEXT \
	label.font="SF Pro:Semibold:13.0" \
	script="$PLUGIN_DIR/front_app.sh" \
	padding_left=24 \
	--subscribe front_app front_app_switched

#!/bin/sh

source "$CONFIG_DIR/colors.sh"

if [ "$SELECTED" = "true" ]; then
	sketchybar --set $NAME \
		background.drawing=on \
		background.color=$ACCENT_BG \
		label.color=$BLUE \
		icon.color=$BLUE
else
	sketchybar --set $NAME \
		background.drawing=off \
		label.color=$SUBTEXT0 \
		icon.color=$SUBTEXT0
fi

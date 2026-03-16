#!/bin/bash

SPACE_ICONS=("1" "2" "3" "4" "5" "6" "7")

for i in "${!SPACE_ICONS[@]}"; do
	sid=$(($i + 1))
	sketchybar --add space space.$sid left \
		--set space.$sid space=$sid \
		icon=${SPACE_ICONS[i]} \
		icon.font="SF Pro:Bold:14.0" \
		label.font="sketchybar-app-font:Regular:16.0" \
		label.padding_right=20 \
		label.y_offset=-1 \
		background.color=0x00000000 \
		background.corner_radius=6 \
		background.height=24 \
		script="$PLUGIN_DIR/space.sh"
done

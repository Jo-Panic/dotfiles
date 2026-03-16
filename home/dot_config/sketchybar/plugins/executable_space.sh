#!/bin/sh

# The $SELECTED variable is available for space components and indicates if
# the space invoking this script (with name: $NAME) is currently selected:
# https://felixkratz.github.io/SketchyBar/config/components#space----associate-mission-control-spaces-with-an-item

# sketchybar --set $NAME background.drawing=$SELECTED

source "$CONFIG_DIR/colors.sh" # Load the color variables

if [ "$SELECTED" = "true" ]; then
	sketchybar --set $NAME background.drawing=$SELECTED \
		background.color=$ACCENT_COLOR \
		label.color=$LABEL_IN_ACCENT_COLOR \
		icon.color=$LABEL_IN_ACCENT_COLOR
else
	sketchybar --set $NAME background.drawing=$SELECTED \
		label.color=$LABEL_COLOR \
		icon.color=$ICON_COLOR
fi

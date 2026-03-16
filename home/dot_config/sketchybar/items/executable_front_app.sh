#!/bin/bash

#sketchybar --add item space_separator left \

# Since the front app is centered, we don't need separator item

#sketchybar --add item space_separator e \
#	--set space_separator icon="􀆊" \
#	icon.padding_left=4 \
#	background.drawing=off \
#	icon.color=$ACCENT_COLOR \
#	padding_left=5 \
#	label.drawing=off

# The fornt app is set to the right of the notch (position = e)
sketchybar --add item front_app e \
  --set front_app icon.font="sketchybar-app-font:Regular:16.0" \
  background.color=$ACCENT_COLOR \
  icon.color=$LABEL_IN_ACCENT_COLOR \
  label.color=$LABEL_IN_ACCENT_COLOR \
  script="$PLUGIN_DIR/front_app.sh" \
  padding_left=24 \
  --subscribe front_app front_app_switched

#sketchybar --add item space_separator q \
#	--set space_separator icon="􀆊" \
#	icon.padding_left=4 \
#	background.drawing=off \
#	icon.color=$ACCENT_COLOR \
#	padding_left=5 \
#	label.drawing=off

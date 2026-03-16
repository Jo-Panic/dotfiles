#!/bin/bash

sketchybar --add item space_apps left \
	--set space_apps label.drawing=off \
	background.drawing=off \
	script="$PLUGIN_DIR/space_apps.sh" \
	--subscribe space_apps space_windows_change

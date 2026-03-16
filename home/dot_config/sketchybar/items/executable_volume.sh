#!/bin/bash

sketchybar --add item volume right \
	--set volume icon.color=$PEACH \
	label.color=$PEACH \
	script="$PLUGIN_DIR/volume.sh" \
	--subscribe volume volume_change

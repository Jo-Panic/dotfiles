#!/bin/sh

source "$CONFIG_DIR/colors.sh"

if [ "$SENDER" = "volume_change" ]; then
	VOLUME=$INFO

	case $VOLUME in
	[6-9][0-9] | 100)
		ICON="􀊩"
		ICON_CLR=$PEACH
		;;
	[3-5][0-9])
		ICON="􀊥"
		ICON_CLR=$PEACH
		;;
	[1-9] | [1-2][0-9])
		ICON="􀊡"
		ICON_CLR=$PEACH
		;;
	*)
		ICON="􀊣"
		ICON_CLR=$MUTED_COLOR
		;;
	esac

	sketchybar --set $NAME icon="$ICON" label="$VOLUME%" \
		icon.color=$ICON_CLR \
		label.color=$ICON_CLR
fi

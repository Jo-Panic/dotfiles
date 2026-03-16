#!/bin/sh

source "$CONFIG_DIR/colors.sh"

PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ "$PERCENTAGE" = "" ]; then
	exit 0
fi

case ${PERCENTAGE} in
9[0-9] | 100)
	ICON="􀛨"
	CLR=$GREEN
	;;
[6-8][0-9])
	ICON="􀺸"
	CLR=$GREEN
	;;
[3-5][0-9])
	ICON="􀺶"
	CLR=$GREEN
	;;
[1-2][0-9])
	ICON="􀛩"
	CLR=$YELLOW
	;;
*)
	ICON="􀛪"
	CLR=$RED
	;;
esac

if [ "$CHARGING" != "" ]; then
	ICON="􀋦"
	CLR=$TEAL
fi

sketchybar --set $NAME icon="$ICON" label="${PERCENTAGE}%" \
	icon.color=$CLR \
	label.color=$CLR

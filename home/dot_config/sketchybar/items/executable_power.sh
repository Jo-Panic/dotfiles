#!/bin/bash

# ── Power Button + Popup Menu ────────────────────────────────
# Le bouton parent ouvre un popup natif SketchyBar contenant
# trois entrées : Suspendre / Redémarrer / Éteindre.
#
# Icônes : SF Symbols (PUA) pour rester cohérent avec le reste
# de la barre (mullvad, etc.).
#   􀆨  power.circle      → bouton parent
#   􀓤  moon.fill         → suspendre
#   􀅈  arrow.clockwise   → redémarrer
#   􀋧  power             → éteindre

# ── Parent : le bouton dans la barre ─────────────────────────
sketchybar --add item power right \
  --set power icon="􀆨" \
  icon.font="SF Pro:Bold:15.0" \
  icon.color=$RED \
  icon.padding_left=10 \
  icon.padding_right=10 \
  label.drawing=off \
  popup.background.color=$BAR_COLOR \
  popup.background.border_color=$BAR_BORDER_COLOR \
  popup.background.border_width=1 \
  popup.background.corner_radius=12 \
  popup.background.blur_radius=30 \
  popup.background.shadow.drawing=on \
  popup.background.shadow.color=0x80000000 \
  popup.background.shadow.distance=6 \
  popup.horizontal=off \
  popup.align=right \
  popup.y_offset=6 \
  click_script="sketchybar --set power popup.drawing=toggle"

# ── Entrées du popup ─────────────────────────────────────────
# Defaults communs (override les defaults globaux de sketchybarrc)
POPUP_ITEM_DEFAULTS=(
  background.drawing=off
  background.corner_radius=6
  background.height=28
  background.padding_left=4
  background.padding_right=4
  icon.font="SF Pro:Semibold:14.0"
  icon.padding_left=14
  icon.padding_right=10
  label.font="SF Pro:Semibold:13.0"
  label.color=$TEXT
  label.padding_left=4
  label.padding_right=16
  label.align=left
)

# Suspendre l'activité
sketchybar --add item power.suspend popup.power \
  --set power.suspend "${POPUP_ITEM_DEFAULTS[@]}" \
  icon="􀓤" \
  icon.color=$YELLOW \
  label="Suspendre l'activité" \
  click_script="$PLUGIN_DIR/power-action.sh suspend"

# Redémarrer
sketchybar --add item power.restart popup.power \
  --set power.restart "${POPUP_ITEM_DEFAULTS[@]}" \
  icon="􀅈" \
  icon.color=$BLUE \
  label="Redémarrer…" \
  click_script="$PLUGIN_DIR/power-action.sh restart"

# Éteindre
sketchybar --add item power.shutdown popup.power \
  --set power.shutdown "${POPUP_ITEM_DEFAULTS[@]}" \
  icon="􀋧" \
  icon.color=$RED \
  label="Éteindre…" \
  click_script="$PLUGIN_DIR/power-action.sh shutdown"

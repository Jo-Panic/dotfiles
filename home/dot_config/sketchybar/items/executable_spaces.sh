#!/bin/bash

# ── Workspaces ───────────────────────────────────────────────
# Inspiré de la Waybar Hyprland :
#   - workspace actif      : bleu + background
#   - workspace non-vide   : texte standard
#   - workspace vide       : texte muted
#
# Le rendu effectif (couleurs / background) est géré par
# plugins/space.sh, qui interroge yabai à chaque événement.
#
# Événements d'abonnement :
#   - space_change          : géré nativement (item type "space")
#   - space_windows_change  : intégration sketchybar (peut être partielle)
#   - window_change         : événement custom poussé par yabai (signals
#                             dans yabairc) — couvre les changements de
#                             fenêtres sur les workspaces non focalisés.

SPACE_ICONS=("1" "2" "3" "4" "5" "6" "7" "8")

for i in "${!SPACE_ICONS[@]}"; do
  sid=$(($i + 1))
  sketchybar --add space space.$sid left \
    --set space.$sid space=$sid \
    icon=${SPACE_ICONS[i]} \
    icon.font="SF Pro:Bold:14.0" \
    icon.padding_left=10 \
    icon.padding_right=10 \
    label.drawing=off \
    background.color=0x00000000 \
    background.corner_radius=6 \
    background.height=24 \
    click_script="yabai -m space --focus $sid" \
    script="$PLUGIN_DIR/space.sh" \
    --subscribe space.$sid space_windows_change window_change
done

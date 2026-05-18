#!/bin/sh

# ── Plugin : rendu d'un workspace ────────────────────────────
# Déclenché par :
#   - événement natif "space_change" (sketchybar suit le space=N de l'item)
#   - événement "space_windows_change" (abonnement explicite dans items/spaces.sh)
#
# Une seule query yabai par invocation : on récupère focus + nombre
# de fenêtres dans le même appel.

source "$CONFIG_DIR/colors.sh"

# Extraction du numéro de space depuis $NAME (space.1 → 1)
sid="${NAME#space.}"

# Query unique : info complète sur ce space
info=$(yabai -m query --spaces --space "$sid" 2>/dev/null)
if [ -z "$info" ]; then
  exit 0
fi

is_focused=$(echo "$info" | jq -r '."has-focus"')
window_count=$(echo "$info" | jq '.windows | length')

if [ "$is_focused" = "true" ]; then
  # Workspace actif → bleu + background
  sketchybar --set "$NAME" \
    background.drawing=on \
    background.color=$ACCENT_BG \
    icon.color=$BLUE \
    label.color=$BLUE
elif [ "$window_count" -gt 0 ]; then
  # Workspace non-vide → texte standard
  sketchybar --set "$NAME" \
    background.drawing=off \
    icon.color=$TEXT \
    label.color=$TEXT
else
  # Workspace vide → muted
  sketchybar --set "$NAME" \
    background.drawing=off \
    icon.color=$OVERLAY0 \
    label.color=$OVERLAY0
fi

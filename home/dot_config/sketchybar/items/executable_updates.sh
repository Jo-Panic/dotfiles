#!/bin/bash

# ── Mises à jour Homebrew ────────────────────────────────────
# Pendant du module Waybar custom/updates (Arch). Masqué tant qu'aucune
# mise à jour n'est en attente.
#
# Événementiel, sans update_freq : plugins/updates.sh est réveillé par
# l'événement updates_changed que déclenche ~/.local/bin/updates-check
# (agent launchd local.updates-check, toutes les 3 h) — l'équivalent du
# signal SIGRTMIN+9 envoyé à Waybar.
#
#   survol      → popup listant les paquets (le tooltip Waybar)
#   clic gauche → session de mise à jour dans Ghostty (updates-tui.sh)
#   clic droit  → vérification immédiate
#
# Icône : SF Symbol arrow.down.circle (U+100078), écrit en octets UTF-8
# plutôt que collé : les glyphes de la zone privée se perdent en silence
# au copier-coller.

UPDATES_ICON=$(printf '\364\200\201\270')

sketchybar --add event updates_changed \
  --add item updates right \
  --set updates icon="$UPDATES_ICON" \
  icon.color=$YELLOW \
  label.color=$YELLOW \
  drawing=off \
  popup.background.color=$BAR_COLOR \
  popup.background.border_color=$BAR_BORDER_COLOR \
  popup.background.border_width=1 \
  popup.background.corner_radius=12 \
  popup.background.shadow.drawing=on \
  popup.background.shadow.color=0x80000000 \
  popup.background.shadow.distance=6 \
  popup.horizontal=off \
  popup.align=right \
  popup.y_offset=6 \
  script="$PLUGIN_DIR/updates.sh" \
  --subscribe updates updates_changed mouse.clicked mouse.entered mouse.exited

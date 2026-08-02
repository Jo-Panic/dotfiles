#!/bin/bash

# ── Workspaces ───────────────────────────────────────────────
# Inspiré de la Waybar Hyprland :
#   - workspace actif      : bleu + background
#   - workspace non-vide   : texte standard
#   - workspace vide       : texte muted
#
# ARCHITECTURE (depuis 2026-08-02)
#
# Les items `space.N` sont PASSIFS : ni `script`, ni `--subscribe`.
# Ils ne portent que leur apparence et leur `click_script`.
#
# Un item unique et invisible, `spaces_watcher`, s'abonne aux
# événements et repeint les 8 items en un seul appel sketchybar.
#
# Pourquoi ? Un `--subscribe` par item fait exécuter le script de
# CHAQUE item abonné à CHAQUE occurrence de l'événement, quel que
# soit le space concerné. Avec 8 items abonnés à space_windows_change,
# une simple ouverture de fenêtre déclenchait 8 process shell + 8
# query yabai — pour une information qui tient dans un seul $INFO.

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
    click_script="yabai -m space --focus $sid"
done

# ── Contrôleur unique ────────────────────────────────────────
# drawing=off  → jamais rendu, sert uniquement de porteur de script.
# updates=on   → OBLIGATOIRE : avec le défaut `when_shown`, un item
#                non dessiné ne voit jamais son script exécuté.
sketchybar --add item spaces_watcher left \
  --set spaces_watcher drawing=off \
  updates=on \
  script="$PLUGIN_DIR/space.sh" \
  --subscribe spaces_watcher space_change \
  space_windows_change \
  display_change \
  system_woke

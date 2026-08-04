#!/bin/bash

# ── Media Player ─────────────────────────────────────────────
# Équivalent macOS du `group/media` de la Waybar Hyprland
# (playerctl + zscroll).
#
# POURQUOI PAS L'ÉVÉNEMENT NATIF `media_change` ?
#
# SketchyBar expose un événement `media_change` alimenté par le
# framework privé MediaRemote. Depuis macOS 15.4, `mediaremoted`
# vérifie une entitlement que seuls les binaires signés Apple
# possèdent : l'événement ne se déclenche plus jamais.
# Cf. FelixKratz/SketchyBar#708 — le problème est structurel,
# pas une erreur de configuration.
#
# Contournement retenu : `media-control` (brew), qui charge
# MediaRemote depuis /usr/bin/perl — binaire système dont le
# bundle id (`com.apple.perl`) est autorisé par mediaremoted.
#
# ARCHITECTURE
#
#   items/media.sh          → déclare l'item, PASSIF :
#                             ni `script`, ni `update_freq`,
#                             ni `--subscribe`.
#   plugins/media-daemon.sh → process long-lived qui lit
#                             `media-control stream` et pousse
#                             l'état par `sketchybar --set`.
#   plugins/media.sh        → dispatch des clics.
#
# Même principe que la Waybar : zéro fork tant que la lecture
# ne change pas. Pas de polling.
#
# ICÔNE
# Une seule glyphe (􀑪 music.note), la couleur porte l'état :
#   lecture en cours → GREEN + titre en MAUVE
#   en pause         → tout en MUTED
# (parité visuelle avec #custom-media-* de la style.css Waybar)

sketchybar --add item media left \
  --set media drawing=off \
  icon="􀑪" \
  icon.color=$GREEN \
  icon.padding_left=10 \
  label.color=$MAUVE \
  label.max_chars=28 \
  label.padding_right=10 \
  scroll_texts=on \
  click_script="$PLUGIN_DIR/media.sh"

# NOTE : ne pas ajouter `label.scroll_duration`.
# Cf. FelixKratz/SketchyBar#760 — crash de SketchyBar au
# lock/unlock lorsque cette propriété est définie.

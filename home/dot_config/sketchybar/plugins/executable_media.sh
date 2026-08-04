#!/bin/bash

# ── Media — dispatch des clics ───────────────────────────────
# SketchyBar fournit $BUTTON : left | right | other
#
# Parité Waybar (custom/media-now-playing) :
#   gauche → play/pause
#   milieu → piste précédente
#   droit  → piste suivante
#
# Les commandes doivent viser la source réellement affichée :
# `media-control` ne pilote pas MPD, et `mpc` ne pilote pas
# Firefox. media-render.sh écrit la source retenue dans
# $STATE_DIR/active à chaque rendu.
#
# PATH explicite : les click_script tournent dans un shell
# minimal, sans le PATH utilisateur — même piège que les plugins
# et les wrappers yabai.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

STATE_DIR="${TMPDIR:-/tmp}/sketchybar-media"
ACTIVE="$(cat "$STATE_DIR/active" 2>/dev/null)"

if [ "$ACTIVE" = "mpd" ]; then
  case "$BUTTON" in
  right) mpc -q next ;;
  other) mpc -q prev ;;
  *) mpc -q toggle ;;
  esac
  exit 0
fi

# ATTENTION : vérifier les noms exacts des sous-commandes avec
#   $ media-control
# (sans argument, la commande imprime son aide).
# `toggle-play-pause` est documenté ; `next-track` /
# `previous-track` sont déduits de la table de commandes de
# mediaremote-adapter (kMRNextTrack / kMRPreviousTrack).
case "$BUTTON" in
right) media-control next-track ;;
other) media-control previous-track ;;
*) media-control toggle-play-pause ;;
esac

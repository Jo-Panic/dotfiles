#!/usr/bin/env bash

# ── Media — rendu de l'item ──────────────────────────────────
# Point de rendu unique, appelé par les daemons producteurs.
#
# POURQUOI DEUX SOURCES ?
#
# MediaRemote (via media-control) ne connaît que les apps qui
# enregistrent une session « Now Playing » auprès du système :
# navigateurs (Media Session API), mpv, Music, Spotify…
# MPD est un daemon headless qui pousse du PCM vers CoreAudio
# sans jamais s'annoncer — il est donc structurellement absent
# de MediaRemote, et rien ne permet d'y injecter des infos
# depuis l'extérieur.
#
# MPD est donc traité comme une seconde source, interrogée par
# son propre protocole (`mpc idle`, événementiel lui aussi).
#
# PROTOCOLE ENTRE PRODUCTEURS ET RENDU
#
# Chaque daemon écrit UNE ligne dans $STATE_DIR/<source> :
#     off
#   ou
#     play|pause <TAB> Label affiché
#
# puis appelle ce script. Le fichier $STATE_DIR/active mémorise
# la source retenue, pour que plugins/media.sh sache à qui
# adresser les commandes de lecture.
#
# ARBITRAGE
# Une source en lecture l'emporte sur une source en pause.
# À égalité, MPD passe devant : c'est une session lancée
# explicitement, pas une vidéo de fond dans un onglet.
#
# CONCURRENCE
# Deux daemons peuvent appeler ce script en même temps ; au pire
# deux `sketchybar --set` successifs, le dernier gagne. Pas de
# verrou : le coût dépasserait le bénéfice.

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"

STATE_DIR="${TMPDIR:-/tmp}/sketchybar-media"
mkdir -p "$STATE_DIR"

state=""
label=""
active=""

for want in play pause; do
  for src in mpd mediaremote; do
    [ -f "$STATE_DIR/$src" ] || continue
    IFS=$'\t' read -r s l <"$STATE_DIR/$src" || continue
    if [ "$s" = "$want" ]; then
      state="$s"
      label="$l"
      active="$src"
      break 2
    fi
  done
done

if [ -z "$state" ]; then
  : >"$STATE_DIR/active"
  sketchybar --set media drawing=off
  exit 0
fi

printf '%s\n' "$active" >"$STATE_DIR/active"

if [ "$state" = "play" ]; then
  icon_color=$GREEN
  label_color=$MAUVE
else
  icon_color=$MUTED_COLOR
  label_color=$MUTED_COLOR
fi

sketchybar --set media drawing=on \
  label="$label" \
  icon.color="$icon_color" \
  label.color="$label_color"

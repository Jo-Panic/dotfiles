#!/usr/bin/env bash

# ── Media daemon — source MediaRemote ────────────────────────
# Équivalent macOS de `playerctl status --follow` : lit
# `media-control stream`, qui n'émet une ligne JSON QUE lorsque
# l'état de lecture change. Aucun polling, aucun fork au repos.
#
# Couvre les apps qui enregistrent une session « Now Playing » :
# navigateurs, mpv, Music, Spotify… mais PAS MPD, qui n'a pas
# de session à enregistrer (voir plugins/media-daemon-mpd.sh).
#
# Lancé en arrière-plan depuis sketchybarrc, après `--update`.
#
# CHANGEMENT vs première version : le daemon n'appelle plus
# `sketchybar --set` directement. Il écrit son état dans
# $STATE_DIR/mediaremote puis délègue à media-render.sh, qui
# arbitre entre les deux sources.
#
# OPTIONS DU STREAM
#   --no-diff     payload complet à chaque update. Sans cette
#                 option il faudrait maintenir l'état côté shell
#                 pour recomposer les diffs partiels.
#   --no-artwork  évite plusieurs centaines de Ko de base64 par
#                 update (indispensable avec --no-diff, qui
#                 réémettrait la pochette à chaque changement).
#   --debounce    regroupe les rafales de petits updates.
#
# `stream` émet immédiatement l'état courant au démarrage :
# relancer le daemon suffit à repeindre l'item correctement
# après un `sketchybar --reload`.
#
# PATH explicite : lancé depuis sketchybarrc, donc shell minimal
# sans le PATH utilisateur.

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
PLUGIN_DIR="$CONFIG_DIR/plugins"

STATE_DIR="${TMPDIR:-/tmp}/sketchybar-media"
mkdir -p "$STATE_DIR"

PIDFILE="$STATE_DIR/mediaremote.pid"

# ── Un seul exemplaire ───────────────────────────────────────
# Au rechargement de SketchyBar, l'ancien daemon survit : il
# n'est pas un enfant supervisé, juste un process détaché.
#
# L'ordre compte : on tue d'abord la descendance (media-control,
# jq), ce qui ferme le pipeline et débloque le shell ; ensuite
# seulement le shell lui-même. Un bash bloqué sur une commande
# en avant-plan ne traite pas ses traps avant que celle-ci ne
# rende la main.
if [ -f "$PIDFILE" ]; then
  old="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$old" ] && [ "$old" != "$$" ]; then
    pkill -P "$old" 2>/dev/null
    kill "$old" 2>/dev/null
  fi
fi

echo $$ >"$PIDFILE"
trap 'pkill -P $$ 2>/dev/null; rm -f "$PIDFILE"' EXIT INT TERM

# ── Boucle événementielle ────────────────────────────────────
# jq réduit chaque payload à une ligne TSV : état + label déjà
# composé. `--unbuffered` est requis, sinon jq bufferise et
# l'affichage accumule du retard.
#
# Une clé `title` vide (ou absente) signifie qu'aucun lecteur ne
# publie d'information → la source se déclare éteinte.
media-control stream --no-diff --no-artwork --debounce=150 2>/dev/null |
  jq -rc --unbuffered '
    .payload as $p
    | if ($p.title // "") == "" then
        "off"
      else
        [ (if $p.playing then "play" else "pause" end),
          ($p.title
           + (if ($p.artist // "") == "" then "" else " - " + $p.artist end))
        ] | @tsv
      end
  ' |
  while IFS= read -r line; do
    printf '%s\n' "$line" >"$STATE_DIR/mediaremote"
    "$PLUGIN_DIR/media-render.sh"
  done

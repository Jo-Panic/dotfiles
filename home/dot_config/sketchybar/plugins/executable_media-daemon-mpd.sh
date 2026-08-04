#!/usr/bin/env bash

# ── Media daemon — source MPD ────────────────────────────────
# MPD n'apparaît pas dans MediaRemote : c'est un daemon headless
# qui écrit du PCM vers CoreAudio sans enregistrer de session
# « Now Playing ». ncmpcpp n'est qu'un client TUI, il ne change
# rien à ça.
#
# On interroge donc MPD par son propre protocole. `mpc idle`
# BLOQUE jusqu'au prochain événement du sous-système `player`
# (lecture, pause, changement de piste) : c'est l'équivalent
# exact de `media-control stream` côté MediaRemote, et de
# `playerctl --follow` côté Linux. Aucun polling.
#
# Prérequis : brew install mpc
#   (attention, la formule `mpc` est bien le client MPD ;
#    la bibliothèque mathématique GNU MPC est `libmpc`)
#
# MPD_HOST / MPD_PORT ne sont pas définis → localhost:6600,
# ce qui correspond aux valeurs par défaut de ~/.mpd/mpd.conf.

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
PLUGIN_DIR="$CONFIG_DIR/plugins"

STATE_DIR="${TMPDIR:-/tmp}/sketchybar-media"
mkdir -p "$STATE_DIR"

PIDFILE="$STATE_DIR/mpd.pid"

# ── Un seul exemplaire ───────────────────────────────────────
# Même logique que le daemon MediaRemote : tuer la descendance
# (le `mpc idle` bloquant) avant le shell lui-même.
if [ -f "$PIDFILE" ]; then
  old="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$old" ] && [ "$old" != "$$" ]; then
    pkill -P "$old" 2>/dev/null
    kill "$old" 2>/dev/null
  fi
fi

echo $$ >"$PIDFILE"
trap 'pkill -P $$ 2>/dev/null; rm -f "$PIDFILE"' EXIT INT TERM

# ── Lecture de l'état ────────────────────────────────────────
# Le format mpc : `[...]` n'imprime le groupe que si un tag au
# moins est présent, `|` fournit une alternative. D'où l'imbri-
# cation : l'artiste et son séparateur forment leur propre
# groupe, sinon un morceau sans tag artiste afficherait
# « Titre - ». Repli sur le nom de fichier si aucun tag.
emit() {
  local status state label

  status="$(mpc status 2>/dev/null)" || {
    printf 'off\n' >"$STATE_DIR/mpd"
    return 1
  }

  case "$status" in
  *'[playing]'*) state=play ;;
  *'[paused]'*) state=pause ;;
  *)
    # arrêté, playlist vide, ou MPD injoignable
    printf 'off\n' >"$STATE_DIR/mpd"
    return 0
    ;;
  esac

  label="$(mpc -f '[%title%[ - %artist%]]|[%file%]' current 2>/dev/null)"
  [ -n "$label" ] || label="(sans titre)"

  printf '%s\t%s\n' "$state" "$label" >"$STATE_DIR/mpd"
}

# ── Boucle événementielle ────────────────────────────────────
# `mpc idle player` rend la main au premier changement d'état.
# S'il échoue, MPD n'est pas lancé : on se met en veille plutôt
# que de boucler à vide.
while :; do
  emit
  "$PLUGIN_DIR/media-render.sh"

  if ! mpc idle player >/dev/null 2>&1; then
    printf 'off\n' >"$STATE_DIR/mpd"
    "$PLUGIN_DIR/media-render.sh"
    sleep 5
  fi
done

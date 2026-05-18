#!/bin/bash

# ── Power Action Handler ─────────────────────────────────────
# Appelé par chaque entrée du popup power.
# Args : suspend | restart | shutdown
#
# Ferme d'abord le popup, puis exécute l'action demandée.

# Fermer le popup en premier pour un retour visuel immédiat
sketchybar --set power popup.drawing=off

case "$1" in
  suspend)
    pmset sleepnow
    ;;
  restart)
    osascript -e 'tell application "loginwindow" to «event aevtrrst»'
    ;;
  shutdown)
    osascript -e 'tell application "loginwindow" to «event aevtsdwn»'
    ;;
  *)
    echo "Usage: $0 {suspend|restart|shutdown}" >&2
    exit 1
    ;;
esac

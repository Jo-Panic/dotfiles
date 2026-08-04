#!/bin/bash

# ── Fermeture automatique du popup power ─────────────────────
# Ferme le popup dès que le curseur quitte la barre.
#
# mouse.entered.global n'est volontairement pas traité, mais il
# DOIT être souscrit dans items/power.sh : sans lui, la livraison
# de mouse.exited.global est erratique.

export PATH="/opt/homebrew/bin:$PATH"

[ "$SENDER" = "mouse.exited.global" ] && sketchybar --set power popup.drawing=off

exit 0

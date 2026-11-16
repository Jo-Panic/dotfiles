#!/bin/bash

# ── updates-tui ──────────────────────────────────────────────
# Session de mise à jour Homebrew dans une fenêtre Ghostty flottante.
# Pendant de waybar/scripts/updates-tui.sh (Arch : foot + paru) ; foot
# n'existe que sous Wayland, Ghostty en tient le rôle.
#
# Sans argument (clic sketchybar, clic sur la notification) :
#   focus-or-launch. Si la fenêtre « updates » existe, yabai lui donne le
#   focus ; sinon une instance Ghostty dédiée est lancée (open -na), titrée
#   « updates » pour les règles yabai (flottante, centrée, space courant).
#   --window-save-state=never : n'y restaure pas la session précédente.
#   -e implique quit-after-last-window-closed : l'instance quitte avec
#   la fenêtre, sans icône orpheline dans le Dock.
#
# Avec --run (dans la fenêtre) : brew update, liste, confirmation [O/n]
#   comme paru, brew upgrade, puis updates-check --no-update pour
#   rafraîchir sketchybar. Si brew upgrade réussit alors que des paquets
#   restent en attente (cask en échec silencieux, etc.), un avertissement
#   l'indique — l'équivalent du contrôle checkupdates après paru.
#
# Écrit pour le /bin/bash 3.2 de macOS.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_ENV_HINTS=1

# ── Réglages ─────────────────────────────────────────────────
TITLE=updates
GRID=6:6:1:1:4:4 # filet de sécurité, même valeur que la règle yabai
# Casks auto_updates inclus : même valeur que CASK_FLAGS dans updates-check,
# sinon les paquets annoncés ne seraient pas tous mis à jour.
CASK_FLAGS=--greedy-auto-updates
CHECK="$HOME/.local/bin/updates-check"
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/updates-check/pending"

case $0 in
*/*) SELF="$(cd "${0%/*}" && pwd)/${0##*/}" ;;
*) SELF=$(command -v "$0") ;;
esac

# ── Session (dans la fenêtre Ghostty) ────────────────────────
section() { printf '\n\033[1;34m::\033[0;1m %s\033[0m\n' "$*"; }

run_session() {
  local outdated answer="" upgraded=0 remaining count

  section "Synchronisation du catalogue Homebrew…"
  brew update ||
    printf '\n[Attention] brew update a échoué : la liste peut être incomplète.\n'

  outdated=$(brew outdated --verbose ${CASK_FLAGS:+"$CASK_FLAGS"})
  if [ -z "$outdated" ]; then
    section "Aucune mise à jour disponible."
  else
    section "Paquets à mettre à jour :"
    printf '%s\n\n' "$outdated"
    read -rp ":: Procéder à la mise à jour ? [O/n] " answer
    case $answer in
    [nN]*) printf 'Mise à jour annulée.\n' ;;
    *) brew upgrade ${CASK_FLAGS:+"$CASK_FLAGS"} && upgraded=1 ;;
    esac
  fi

  # Rafraîchit l'état et sketchybar dans tous les cas (annulation, échec,
  # rien à faire) ; le catalogue vient d'être synchronisé.
  "$CHECK" --no-update

  remaining=$(awk 'NF' "$STATE_FILE" 2>/dev/null)
  if ((upgraded)) && [ -n "$remaining" ]; then
    count=$(printf '%s\n' "$remaining" | awk 'END {print NR}')
    printf '\n[Attention] brew upgrade a réussi mais %s paquet(s) restent en attente :\n' "$count"
    printf '%s\n' "$remaining" | sed 's/^/  /'
  fi

  # yabai : si la règle sudoers de `yabai --load-sa` épingle le hash du
  # binaire (procédure du wiki yabai), elle est à refaire à chaque mise à jour.
  if ((upgraded)) && printf '%s\n' "$outdated" | grep -q '^yabai '; then
    printf '\n[Rappel] yabai a été mis à jour : régénérer le hash dans\n'
    printf '/private/etc/sudoers.d/yabai, puis yabai --restart-service.\n'
  fi

  printf '\n[Terminé — une touche pour fermer]'
  read -rsn1
}

if [ "${1:-}" = "--run" ]; then
  run_session
  exit 0
fi

# ── Focus-or-launch ──────────────────────────────────────────
find_window() {
  yabai -m query --windows 2>/dev/null |
    jq -r --arg t "$TITLE" \
      '[.[] | select(.app == "Ghostty" and .title == $t)][0].id // empty' 2>/dev/null
}

# Filet de sécurité si la règle yabai n'a pas pris (titre posé après la
# création de la fenêtre) : flottante, centrée, ramenée sur le space courant.
place_window() {
  local space="$1" id="" info i

  for ((i = 0; i < 50; i++)); do
    id=$(find_window)
    [ -n "$id" ] && break
    sleep 0.1
  done
  [ -n "$id" ] || return 0

  info=$(yabai -m query --windows --window "$id" 2>/dev/null) || return 0
  if [ "$(jq -r '."is-floating"' <<<"$info")" != "true" ]; then
    yabai -m window "$id" --toggle float
    yabai -m window "$id" --grid "$GRID"
  fi
  if [ -n "$space" ] && [ "$(jq -r '.space' <<<"$info")" != "$space" ]; then
    yabai -m window "$id" --space "$space"
    yabai -m space --focus "$space"
  fi
  yabai -m window --focus "$id" 2>/dev/null
  return 0
}

if command -v yabai >/dev/null 2>&1; then
  id=$(find_window)
  if [ -n "$id" ]; then
    yabai -m window --focus "$id"
    exit 0
  fi
  space=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index // empty' 2>/dev/null)
fi

# Sans yabai (ou fenêtre introuvable) : pas de seconde session si une
# première tourne encore — brew refuserait de toute façon le verrou.
pgrep -f -- "updates-tui.sh --run" >/dev/null 2>&1 && exit 0

open -na Ghostty --args \
  --title="$TITLE" \
  --window-save-state=never \
  -e /bin/bash "$SELF" --run

command -v yabai >/dev/null 2>&1 && place_window "${space:-}"
exit 0

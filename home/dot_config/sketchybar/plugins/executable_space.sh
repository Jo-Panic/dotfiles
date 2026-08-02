#!/bin/bash

# ── Contrôleur de rendu des workspaces ───────────────────────
# Un seul process par événement, un seul appel yabai, un seul
# appel sketchybar (batché sur les 8 items).
#
# Sources de vérité, par ordre de fraîcheur :
#
#   1. $INFO (événement space_windows_change)
#      Émis par SketchyBar au moment exact où SkyLight lui signale
#      la création / destruction / migration d'une fenêtre.
#      Format : {"space": 3, "apps": {"Brave Browser": 1}}
#      → toujours à jour, mais ne couvre QUE le space concerné,
#        et n'énumère pas les fenêtres masquées / minimisées
#        (cf. FelixKratz/SketchyBar#492).
#
#   2. yabai -m query --spaces
#      Couvre tous les spaces, y compris les fenêtres masquées,
#      mais son état interne accuse un retard sur SkyLight quand
#      une règle `space=N` vient de déplacer une fenêtre.
#
# On combine les deux : occupation = max(INFO, yabai). Une source
# qui voit une fenêtre l'emporte sur une source qui n'en voit pas.
# C'est ce max() qui corrige le bug historique du space cible
# affiché « vide » après le lancement d'une app assignée par règle.

source "$CONFIG_DIR/colors.sh"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ── 1. Occupation fraîche issue de l'événement (si disponible) ──
evt_space=""
evt_count=0
if [ "$SENDER" = "space_windows_change" ] && [ -n "$INFO" ]; then
  evt_space=$(jq -r '.space // empty' <<<"$INFO" 2>/dev/null)
  evt_count=$(jq -r '[.apps[]] | add // 0' <<<"$INFO" 2>/dev/null)
  [ -z "$evt_count" ] && evt_count=0
fi

# ── 2. Snapshot global yabai : "index focus nb_fenetres" ────────
snapshot=$(yabai -m query --spaces 2>/dev/null |
  jq -r '.[] | "\(.index) \(if ."has-focus" then 1 else 0 end) \(.windows | length)"')

[ -z "$snapshot" ] && exit 0

# ── 3. Construction d'un seul appel sketchybar ──────────────────
args=()
while read -r idx focused count; do
  [ -z "$idx" ] && continue

  # L'événement l'emporte s'il voit plus de fenêtres que yabai
  if [ -n "$evt_space" ] && [ "$idx" = "$evt_space" ] && [ "$evt_count" -gt "$count" ]; then
    count=$evt_count
  fi

  if [ "$focused" = "1" ]; then
    # Workspace actif → bleu + background
    args+=(--set "space.$idx"
      background.drawing=on
      background.color="$ACCENT_BG"
      icon.color="$BLUE"
      icon.highlight_color="$BLUE"
      label.color="$BLUE"
      label.highlight_color="$BLUE")
  elif [ "$count" -gt 0 ]; then
    # Workspace non-vide → texte standard
    args+=(--set "space.$idx"
      background.drawing=off
      icon.color="$TEXT"
      icon.highlight_color="$TEXT"
      label.color="$TEXT"
      label.highlight_color="$TEXT")
  else
    # Workspace vide → muted
    args+=(--set "space.$idx"
      background.drawing=off
      icon.color="$OVERLAY0"
      icon.highlight_color="$OVERLAY0"
      label.color="$OVERLAY0"
      label.highlight_color="$OVERLAY0")
  fi
done <<<"$snapshot"

[ ${#args[@]} -gt 0 ] && sketchybar "${args[@]}"

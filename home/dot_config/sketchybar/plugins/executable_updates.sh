#!/bin/bash

# ── Module updates ───────────────────────────────────────────
# Indicateur des mises à jour Homebrew en attente. L'affichage est purement
# passif : il lit le fichier d'état produit par ~/.local/bin/updates-check,
# sans appel réseau ni appel brew.
#
# Événements (cf. items/updates.sh) :
#   forced / updates_changed → rendu de l'item et du popup
#   mouse.entered / exited   → popup au survol (le tooltip Waybar)
#   mouse.clicked gauche     → session de mise à jour (updates-tui.sh)
#   mouse.clicked droit      → vérification immédiate
#
# Le popup est reconstruit à chaque rendu : ses lignes (updates.line.*)
# sont supprimées puis recréées, dans l'ordre d'affichage.

source "$CONFIG_DIR/colors.sh"

# ── PATH explicite pour sketchybar (environnement minimal) ───
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# ── Réglages ─────────────────────────────────────────────────
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/updates-check/pending"
CHECK="$HOME/.local/bin/updates-check"
TUI="$CONFIG_DIR/plugins/updates-tui.sh"
POPUP_MAX_NAMES=20

# Defaults des lignes du popup (override les defaults globaux de sketchybarrc)
LINE_DEFAULTS=(
  background.drawing=off
  icon.drawing=off
  label.font="SF Pro:Semibold:13.0"
  label.color=$TEXT
  label.padding_left=14
  label.padding_right=14
  label.align=left
)

render() {
  local names=() line count header i args

  if [ -r "$STATE_FILE" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && names+=("$line")
    done <"$STATE_FILE"
  fi
  count=${#names[@]}

  sketchybar --remove '/updates\.line\..*/' >/dev/null 2>&1

  if ((count == 0)); then
    sketchybar --set "$NAME" drawing=off popup.drawing=off
    return
  fi

  if ((count > 1)); then
    header="$count mises à jour en attente"
  else
    header="1 mise à jour en attente"
  fi

  args=(
    --set "$NAME" drawing=on label="$count" icon.color=$YELLOW label.color=$YELLOW
    --add item updates.line.header popup."$NAME"
    --set updates.line.header "${LINE_DEFAULTS[@]}"
    label="$header" label.font="SF Pro:Bold:13.0" label.color=$YELLOW
  )

  for ((i = 0; i < count && i < POPUP_MAX_NAMES; i++)); do
    args+=(
      --add item "updates.line.$i" popup."$NAME"
      --set "updates.line.$i" "${LINE_DEFAULTS[@]}" label="${names[i]}"
    )
  done

  if ((count > POPUP_MAX_NAMES)); then
    args+=(
      --add item updates.line.more popup."$NAME"
      --set updates.line.more "${LINE_DEFAULTS[@]}"
      label="… et $((count - POPUP_MAX_NAMES)) autres" label.color=$SUBTEXT0
    )
  fi

  args+=(
    --add item updates.line.hint popup."$NAME"
    --set updates.line.hint "${LINE_DEFAULTS[@]}"
    label="Clic : mettre à jour · clic droit : vérifier"
    label.font="SF Pro:Regular:11.0" label.color=$MUTED_COLOR
  )

  sketchybar "${args[@]}"
}

case "$SENDER" in
mouse.entered)
  sketchybar --set "$NAME" popup.drawing=on
  ;;
mouse.exited)
  sketchybar --set "$NAME" popup.drawing=off
  ;;
mouse.clicked)
  sketchybar --set "$NAME" popup.drawing=off
  if [ "$BUTTON" = "right" ]; then
    # Retour visuel pendant la vérification ; le rendu final est forcé
    # même si l'ensemble en attente n'a pas changé.
    sketchybar --set "$NAME" icon.color=$MUTED_COLOR label.color=$MUTED_COLOR
    ("$CHECK"; sketchybar --trigger updates_changed) >/dev/null 2>&1 &
  else
    "$TUI" >/dev/null 2>&1 &
  fi
  ;;
*)
  render
  ;;
esac

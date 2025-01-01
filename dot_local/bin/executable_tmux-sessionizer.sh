#!/usr/bin/env bash
# Inspired by ThePrimagen : https://github.com/ThePrimeagen/tmux-sessionizer
switch_to() {
  if [[ -z $TMUX ]]; then
    tmux attach-session -t "$1"
  else
    tmux switch-client -t "$1"
  fi
}

has_session() {
  tmux list-sessions | grep -q "^$1:"
}

# Ce bloc vérifie si un argument a été passé au script.
# Si oui, il l'utilise comme répertoire sélectionné.
# Sinon, il utilise find pour chercher des dossiers dans certains répertoires spécifiques,
# puis utilise fzf pour permettre à l'utilisateur de sélectionner un dossier.
if [[ $# -eq 1 ]]; then
  selected=$1
else
  selected=$(find ~/ ~/Documents ~/Projets ~/.config -mindepth 1 -maxdepth 1 -type d | fzf)
fi

# Si aucun dossier n'a été sélectionné, le script se termine.
if [[ -z $selected ]]; then
  exit 0
fi

# Cette ligne extrait le nom du dossier sélectionné et remplace les points par des underscores.
selected_name=$(basename "$selected" | tr . _)
# Vérifie si tmux est déjà en cours d'exécution.
tmux_running=$(pgrep tmux)

# Si tmux n'est pas en cours d'exécution et qu'on n'est pas dans une session tmux,
# ce bloc crée une nouvelle session tmux avec le nom du dossier sélectionné et change le répertoire de travail.
if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
  tmux new-session -s "$selected_name" -c "$selected"
  exit 0
fi
# Si une session tmux avec le nom du dossier sélectionné n'existe pas déjà, ce bloc en crée une nouvelle en arrière-plan.
if ! has_session "$selected_name"; then
  tmux new-session -ds "$selected_name" -c "$selected"
fi

# Enfin, cette ligne bascule vers la session tmux créée ou existante.
# tmux switch-client -t "$selected_name"
switch_to "$selected_name"

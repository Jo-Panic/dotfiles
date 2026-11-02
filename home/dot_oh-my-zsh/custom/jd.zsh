# Johnny.Decimal — navigation, recherche et création d'ID.
#
#   jd [AC|AC.ID]        se placer dans une catégorie ou un ID
#   jdex [MOTIF]         chercher dans l'index, ou l'ouvrir
#   jdg MOTIF...         plein texte sur tout l'arbre, PDF inclus
#   jdnew AC.ID LIBELLÉ  créer un ID et sa ligne d'index
#   jdp FICHIER...       copier vers Proton Drive, préfixé par l'ID
#
# JD_ROOT, JD_INDEX et JD_PROTON_DEST peuvent être surchargés avant
# chargement.

export JD_ROOT=${JD_ROOT:-$HOME/Documents/jd}
export JD_INDEX=${JD_INDEX:-$JD_ROOT/00-09-Systeme/00-Gestion-du-systeme/00.00-JDex/index.md}
export JD_PROTON_DEST=${JD_PROTON_DEST:-/my-files/Mobile}

# Navigation par numéro.
#   jd 26      → 20-29-Foyer/26-Animaux
#   jd 26.11   → 20-29-Foyer/26-Animaux/26.11-…
#   jd         → sélection fzf, aperçu du contenu
#
# Les catégories vivent à la profondeur 2, les ID à la profondeur 3.
# Le glob zsh les cible directement : ni find ni filtrage, et rien à
# adapter entre BSD et GNU.
jd() {
  emulate -L zsh
  local target
  local -a hits

  if (( $# )); then
    hits=( $JD_ROOT/*/$1-*(N/) $JD_ROOT/*/*/$1-*(N/) )
    (( $#hits )) || { print -u2 "jd: aucun dossier pour $1"; return 1 }
    target=$hits[1]
  else
    hits=( $JD_ROOT/*(N/) $JD_ROOT/*/*(N/) $JD_ROOT/*/*/*(N/) )
    (( $#hits )) || { print -u2 "jd: $JD_ROOT vide ou absent"; return 1 }
    target=$(print -rl -- $hits \
      | fzf --prompt='jd > ' --height=60% --reverse --preview='ls -1 {}') || return
  fi

  cd -- $target
}

# Recherche dans l'index, ouverture à la ligne trouvée.
#   jdex chevaux   → fzf sur les lignes correspondantes
#   jdex           → ouvre l'index
jdex() {
  emulate -L zsh
  [[ -r $JD_INDEX ]] || { print -u2 "jdex: index introuvable — $JD_INDEX"; return 1 }
  (( $# )) || { ${EDITOR:-nvim} $JD_INDEX; return }

  # --smart-case, comme jdg : une requête tout en minuscules ignore la
  # casse, une majuscule quelque part la rend discriminante. « syncthing »
  # trouve « Syncthing », « SCI » ne trouve que le sigle.
  local hit
  hit=$(command rg --smart-case --line-number --color=always -- "$*" $JD_INDEX \
    | fzf --ansi --delimiter=: --prompt='jdex > ' --height=60% --reverse) || return

  [[ -n $hit ]] && ${EDITOR:-nvim} "+${hit%%:*}" $JD_INDEX
}

# Plein texte sur tout l'arbre. ripgrep-all lit les PDF, docx et archives,
# ce que rg ne fait pas — déterminant tant que l'archive n'est pas classée.
jdg() {
  emulate -L zsh
  (( $# )) || { print -u2 'usage: jdg MOTIF...'; return 2 }

  if (( $+commands[rga] )); then
    command rga --smart-case -- "$@" $JD_ROOT
  else
    print -u2 'jdg: rga absent (paquet ripgrep-all) — repli sur rg, PDF ignorés'
    command rg --smart-case -- "$@" $JD_ROOT
  fi
}

# Création d'un ID : le dossier et la ligne d'index, jamais l'un sans l'autre.
# Un ID absent du JDex est un ID qui sera perdu.
#   jdnew 26.11 Cheval Alezan
jdnew() {
  emulate -L zsh
  # Le shift doit être gardé : sans argument il échouerait avant le
  # contrôle d'usage ci-dessous.
  local id=$1; (( $# )) && shift
  local label="$*"

  [[ -n $id && -n $label ]] || {
    print -u2 'usage: jdnew <AC.ID> <libellé>'
    return 2
  }
  [[ $id == [0-9][0-9].[0-9][0-9] ]] || {
    print -u2 "jdnew: identifiant invalide — $id (attendu AC.ID, ex. 26.11)"
    return 2
  }
  [[ -w $JD_INDEX ]] || { print -u2 "jdnew: index non inscriptible — $JD_INDEX"; return 1 }

  local -a catdirs taken
  catdirs=( $JD_ROOT/*/${id%%.*}-*(N/) )
  (( $#catdirs )) || { print -u2 "jdnew: catégorie ${id%%.*} introuvable"; return 1 }

  # Le contrôle porte sur le numéro, pas sur le libellé : deux dossiers
  # partageant un ID ruineraient le système.
  taken=( $catdirs[1]/$id-*(N/) )
  (( $#taken )) && { print -u2 "jdnew: $id déjà attribué — ${taken[1]:t}"; return 1 }

  [[ $label == *[^[:ascii:]]* ]] && print -u2 \
    "jdnew: accents dans le libellé — APFS normalise en NFD, ext4 en NFC"

  local dir=$catdirs[1]/$id-${label// /-}
  command mkdir -p $dir || return
  print -n 'créé : '; print -D -- $dir

  # Le squelette initial a pré-rempli quelques lignes d'index. En écrire
  # une seconde pour le même ID donnerait deux réponses à une recherche.
  if command grep -q "^- \*\*${id}\*\*" $JD_INDEX; then
    print "JDex : ligne $id déjà présente, laissée intacte"
  else
    print -r -- "- **$id** $label" >> $JD_INDEX
    print 'JDex : ligne ajoutée en fin de fichier, à replacer sous sa catégorie'
  fi
}

# Copie vers Proton Drive pour consultation depuis le téléphone.
#   jdp ordonnance.pdf                    → /my-files/Mobile/41.12-ordonnance.pdf
#   jdp *.pdf                             → un seul téléversement pour le lot
#
# Le dossier de destination est plat : c'est le préfixe qui porte l'adresse.
# Le CLI Proton téléverse sous le nom source et ne sait pas renommer à
# l'arrivée, d'où les copies préparées dans un temporaire.
jdp() {
  emulate -L zsh
  (( $# )) || { print -u2 'usage: jdp <fichier>...'; return 2 }
  (( $+commands[proton-drive] )) || {
    print -u2 'jdp: proton-drive introuvable dans le PATH'
    return 1
  }

  local f abs name id tmp rc
  local -a uploads

  tmp=$(command mktemp -d) || return 1

  # Une sortie en cours de boucle laisserait le temporaire derrière elle :
  # le nettoyage est explicite à chaque return.
  for f in "$@"; do
    abs=${f:A}
    if [[ ! -f $abs ]]; then
      print -u2 "jdp: fichier introuvable — $f"
      command rm -rf -- $tmp; return 1
    fi
    if [[ $abs =~ '/([0-9][0-9]\.[0-9][0-9])[^/]*/' ]]; then
      id=$match[1]
    else
      print -u2 "jdp: aucun ID JD dans le chemin — $abs"
      command rm -rf -- $tmp; return 1
    fi
    name=${abs:t}
    [[ $name == ${id}* ]] || name="$id-$name"
    command cp -- $abs $tmp/$name || { command rm -rf -- $tmp; return 1 }
    uploads+=( $tmp/$name )
  done

  command proton-drive filesystem upload $uploads $JD_PROTON_DEST
  rc=$?
  command rm -rf -- $tmp
  return $rc
}

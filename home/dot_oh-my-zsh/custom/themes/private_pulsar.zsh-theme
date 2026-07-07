# ~/.oh-my-zsh/custom/themes/pulsar.zsh-theme
#
# Prompt sur deux lignes dérivé du générateur bash-prompt-generator.org.
# Segments : [heure] - (jobs) - (hostname) - (cwd) - (branche git si dépôt)
# Palette 256 couleurs conservée : 35 = vert (cadre), 38 = cyan, 39 = bleu.

PROMPT='%F{35}╭─[%F{38}%*%F{35}]%f'    # heure HH:MM:SS       (bash \t)
PROMPT+='%F{35}-(%F{38}%j%F{35})%f'     # jobs en arrière-plan (bash \j)
PROMPT+='%F{35}-(%F{39}%M%F{35})%f'     # hostname complet     (bash \H)
PROMPT+='%F{35}-(%F{39}%~%F{35})%f'     # répertoire courant   (bash \w)
PROMPT+='$(git_prompt_info)'            # branche git, vide hors dépôt
PROMPT+=$'\n'
PROMPT+='%F{35}╰──%f%2{🚀%} '           # 2e ligne + fusée (largeur 2 cellules)

# Segment git aux couleurs du cadre. Glyphe  (U+E0A0, police Nerd/Powerline) ;
# remplacer par "git:" si la police ne le rend pas.
ZSH_THEME_GIT_PROMPT_PREFIX=$'%F{35}-(%F{39}\uf126 '
ZSH_THEME_GIT_PROMPT_SUFFIX='%F{35})%f'
ZSH_THEME_GIT_PROMPT_DIRTY=' %F{yellow}✗'
ZSH_THEME_GIT_PROMPT_CLEAN=''

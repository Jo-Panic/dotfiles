#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# configure-network-security.sh
# Sécurité réseau macOS : DNS de repli Unbound + NTP authentifié (NTS)
#
# Équivalent macOS de :
#   - arch-dotfiles : Unbound sur 127.0.0.1 + nmcli ipv4.dns 127.0.0.1,
#                     ipv4/ipv6.ignore-auto-dns yes (01-configure-system.sh, guide §14.7)
#   - arch-dotfiles : chrony avec NTS (si configuré)
#
# DNS :
#   - Mullvad connecté : Mullvad impose à tous les services son relais local
#     (127.x.y.z, alias sur lo0), qui transmet au DNS du tunnel.
#   - Mullvad déconnecté, verrouillage levé : Mullvad remet le DNS manuel,
#     127.0.0.1 = Unbound, récursif (racine → TLD → serveurs faisant autorité),
#     DNSSEC validé, sans résolveur tiers. Les requêtes partent en clair.
#     Verrouillage actif : déconnecté = tout est bloqué, Unbound compris.
#   - Remplace Quad9, qui a cessé de servir la France le 24/11/2026.
#   - Little Snitch : chiffrement DNS désactivé (plus de relais NextDNS système).
#     NextDNS ne sert plus qu'à Firefox, en DoH.
#   - Le DNS manuel d'un service remplace aussi ceux du DHCP et de l'IPv6 (RA).
#   Prérequis réseau : aucune politique de filtrage de contenu de l'UDM Pro sur
#   le VLAN 0, sinon SERVFAIL général hors tunnel (guide Arch §20.48).
#
# Test hors tunnel (pas VPN connecté : le pare-feu Mullvad bloque alors le
# port 53 vers tout serveur autre que le DNS du tunnel, Unbound répond SERVFAIL) :
#   mullvad lockdown-mode set off && mullvad disconnect
#   dig example.org | grep flags                    → drapeau ad
#   dig dnssec-failed.org | grep status             → SERVFAIL
#   dig +time=2 +tries=1 @192.0.2.1 example.org     → timeout (pas d'interception)
#   mullvad connect --wait && mullvad lockdown-mode set on
#
# Prérequis : brew install chrony unbound
# Emplacement : ~/.local/bin/configure-network-security.sh
# ═══════════════════════════════════════════════════════════════════

# ── Couleurs ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── DNS de repli hors tunnel ──────────────────────────────────────
DNS_FALLBACK="127.0.0.1"
# Anciennes adresses Quad9, détectées par --status si elles traînent encore
QUAD9_REGEX='^(9\.9\.9\.(9|10|11)|149\.112\.112\.(112|10|11)|2620:fe::)'
# Clé racine en service depuis le 11/10/2026 ; doit figurer dans root.key
ROOT_KSK_2024="38696"

# ── Homebrew prefix (ARM vs Intel) ────────────────────────────────
if [[ -d "/opt/homebrew" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

BREW="${BREW_PREFIX}/bin/brew"
UNBOUND="${BREW_PREFIX}/sbin/unbound"
UNBOUND_ANCHOR="${BREW_PREFIX}/sbin/unbound-anchor"
UNBOUND_CHECKCONF="${BREW_PREFIX}/sbin/unbound-checkconf"
UNBOUND_DIR="${BREW_PREFIX}/etc/unbound"
UNBOUND_CONF="${UNBOUND_DIR}/unbound.conf"
UNBOUND_ROOTKEY="${UNBOUND_DIR}/root.key"
UNBOUND_CONF_CHANGED=false
# Compte vers lequel Unbound abandonne root : le propriétaire de Homebrew,
# comme le prévoit la formule. L'utilisateur « unbound » n'existe pas sur macOS.
BREW_USER=$(stat -f '%Su' "$BREW_PREFIX" 2>/dev/null || echo "")

CHRONYD="${BREW_PREFIX}/sbin/chronyd"
CHRONYC="${BREW_PREFIX}/bin/chronyc"
CHRONY_CONF="/opt/homebrew/etc/chrony.conf"
CHRONY_VAR="/var/db/chrony"
CHRONY_PLIST="/Library/LaunchDaemons/org.tuxfamily.chrony.plist"
TIMED_LABEL="com.apple.timed"

# ── Fonctions utilitaires ─────────────────────────────────────────
log_ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_err()   { echo -e "  ${RED}✗${NC} $1"; }
log_info()  { echo -e "  ${CYAN}→${NC} $1"; }
log_section() { echo -e "\n${CYAN}── $1 ──${NC}"; }

# ── Détection des services réseau ─────────────────────────────────
# Retourne un nom de service par ligne (gère les espaces dans les noms) :
# tout service porté par une interface enN — Wi-Fi, port Ethernet du dock OWC
# (« USB 10/100/1000 LAN »), iPhone USB… Les ponts (Pont Thunderbolt = bridge0,
# réseau Mac à Mac) sont exclus : ils ne portent pas l'accès à Internet.
detect_interfaces() {
    networksetup -listnetworkserviceorder 2>/dev/null | awk '
        /^\([0-9*]+\) / { svc = $0; sub(/^\([0-9*]+\) /, "", svc); next }
        /^\(Hardware Port:/ && svc != "" {
            dev = $0; sub(/.*Device: */, "", dev); sub(/\)$/, "", dev)
            if (dev ~ /^en[0-9]+$/) print svc
            svc = ""
        }'
}

# ══════════════════════════════════════════════════════════════════
# 1. DNS DE REPLI HORS TUNNEL — UNBOUND
# ══════════════════════════════════════════════════════════════════
check_unbound_installed() {
    if [[ ! -x "$UNBOUND" ]]; then
        log_err "unbound n'est pas installé."
        log_info "Installation : brew install unbound"
        return 1
    fi
    log_ok "unbound trouvé : $("$UNBOUND" -V 2>&1 | awk 'NR==1')"
}

# Configuration attendue. Seuls les réglages qui diffèrent du paquet Arch
# sont posés : le compte (absent sur macOS) et l'ancre DNSSEC (l'exemple
# Homebrew n'en déclare aucune, donc ne valide pas).
unbound_conf_content() {
    cat << EOF
# ═══════════════════════════════════════════════════════════════
# unbound.conf — résolveur récursif local, repli DNS hors tunnel
# Généré par configure-network-security.sh (dotfiles chezmoi)
# ═══════════════════════════════════════════════════════════════
server:
    # Boucle locale seulement ; le relais de Mullvad prend une autre
    # adresse 127.x.y.z, sans conflit de port
    interface: 127.0.0.1
    # Unbound démarre en root (port 53) puis passe sur ce compte
    username: "${BREW_USER}"
    directory: "${UNBOUND_DIR}"
    # Ancre DNSSEC tenue à jour par Unbound lui-même (RFC 5011),
    # équivalent du hook pacman de dnssec-anchors
    auto-trust-anchor-file: "${UNBOUND_ROOTKEY}"

remote-control:
    control-enable: no
EOF
}

# Contenu utile d'une configuration (sans commentaires ni lignes vides)
strip_conf() {
    grep -vE '^[[:space:]]*(#|$)' | sed -E 's/[[:space:]]+$//' || true
}

write_unbound_conf() {
    if [[ -z "$BREW_USER" || "$BREW_USER" == "root" ]]; then
        log_err "Propriétaire de ${BREW_PREFIX} introuvable ou root : username impossible à fixer"
        return 1
    fi

    if [[ -f "$UNBOUND_CONF" ]] &&
        diff -q <(strip_conf < "$UNBOUND_CONF") <(unbound_conf_content | strip_conf) > /dev/null; then
        log_ok "unbound.conf déjà à jour"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[dry-run] Écriture de $UNBOUND_CONF :"
        unbound_conf_content | sed 's/^/      /'
        return 0
    fi

    [[ -d "$UNBOUND_DIR" ]] || install -d -o "$BREW_USER" -g admin "$UNBOUND_DIR"
    if [[ -f "$UNBOUND_CONF" ]]; then
        local backup
        backup="${UNBOUND_CONF}.bak-$(date +%Y%m%d-%H%M%S)"
        cp -p "$UNBOUND_CONF" "$backup"
        log_info "Ancienne configuration sauvegardée : $backup"
    fi
    unbound_conf_content > "$UNBOUND_CONF"
    chown "${BREW_USER}:admin" "$UNBOUND_CONF"
    chmod 644 "$UNBOUND_CONF"
    UNBOUND_CONF_CHANGED=true
    log_ok "Configuration écrite dans $UNBOUND_CONF"
}

init_root_key() {
    if [[ -s "$UNBOUND_ROOTKEY" ]]; then
        log_ok "Ancre DNSSEC présente : $UNBOUND_ROOTKEY"
    elif [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[dry-run] unbound-anchor -f /etc/resolv.conf -R -a $UNBOUND_ROOTKEY (compte $BREW_USER)"
        return 0
    else
        # Fichier créé au nom de $BREW_USER : Unbound doit pouvoir le réécrire.
        # Codes : 0 = ancre à jour, 1 = ancre créée ou mise à jour, au-delà = erreur
        local rc=0
        sudo -u "$BREW_USER" "$UNBOUND_ANCHOR" -f /etc/resolv.conf -R -a "$UNBOUND_ROOTKEY" || rc=$?
        if (( rc > 1 )); then
            log_err "unbound-anchor a échoué (code $rc)"
            return 1
        fi
        log_ok "Ancre DNSSEC créée : $UNBOUND_ROOTKEY"
    fi

    if grep -q "$ROOT_KSK_2024" "$UNBOUND_ROOTKEY"; then
        log_ok "Clé racine KSK-2024 ($ROOT_KSK_2024) présente"
    else
        log_warn "KSK-2024 ($ROOT_KSK_2024) absente de root.key : la validation DNSSEC échouera"
        log_info "Arrêter unbound, supprimer $UNBOUND_ROOTKEY puis relancer ce script"
    fi
}

# localhost est une zone locale d'Unbound : la réponse ne dépend pas d'Internet,
# le test vaut donc aussi VPN connecté (Mullvad laisse passer la boucle locale)
unbound_answers() {
    [[ "$(dig +short +time=1 +tries=1 @"$DNS_FALLBACK" localhost A 2> /dev/null)" == "127.0.0.1" ]]
}

start_unbound() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[dry-run] unbound-checkconf, puis brew services start|restart unbound (LaunchDaemon)"
        return 0
    fi

    if ! "$UNBOUND_CHECKCONF" "$UNBOUND_CONF" > /dev/null; then
        log_err "Configuration invalide — détail : $UNBOUND_CHECKCONF $UNBOUND_CONF"
        return 1
    fi

    # brew services accepte root : il gère alors /Library/LaunchDaemons (démarrage au boot)
    if pgrep -x unbound > /dev/null; then
        if [[ "$UNBOUND_CONF_CHANGED" == "true" ]]; then
            "$BREW" services restart unbound > /dev/null
            log_ok "unbound redémarré (configuration modifiée)"
        else
            log_ok "unbound actif (PID $(pgrep -x unbound | awk 'NR==1'))"
        fi
    else
        "$BREW" services start unbound > /dev/null
        log_ok "unbound démarré (LaunchDaemon, lancé au démarrage)"
    fi

    local _
    for _ in {1..10}; do
        if unbound_answers; then
            log_ok "unbound répond sur $DNS_FALLBACK"
            return 0
        fi
        sleep 0.5
    done
    log_err "unbound ne répond pas sur $DNS_FALLBACK:53"
    log_info "Vérifier : sudo lsof -nP -i UDP:53"
    log_info "Journal  : log show --last 5m --predicate 'process == \"unbound\"'"
    return 1
}

set_fallback_dns() {
    local services=() line
    while IFS= read -r line; do
        [[ -n "$line" ]] && services+=("$line")
    done < <(detect_interfaces)

    if [[ ${#services[@]} -eq 0 ]]; then
        log_err "Aucun service réseau Wi-Fi/Ethernet détecté"
        return 1
    fi

    local svc current
    for svc in "${services[@]}"; do
        current=$(networksetup -getdnsservers "$svc" 2> /dev/null || echo "")
        if [[ "$current" == "$DNS_FALLBACK" ]]; then
            log_ok "$svc : DNS déjà sur $DNS_FALLBACK"
        elif [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[dry-run] networksetup -setdnsservers \"$svc\" $DNS_FALLBACK"
        else
            networksetup -setdnsservers "$svc" "$DNS_FALLBACK"
            log_ok "$svc : DNS défini sur $DNS_FALLBACK"
        fi
    done
}

configure_dns() {
    log_section "DNS de repli hors tunnel — Unbound"
    echo -e "  Mullvad connecté   → relais local de Mullvad (127.x.y.z) → DNS du tunnel"
    echo -e "  Mullvad déconnecté → ${GREEN}Unbound${NC} ($DNS_FALLBACK), récursif, DNSSEC validé"
    echo -e "  (verrouillage actif : déconnecté = tout est bloqué, Unbound compris)"

    check_unbound_installed || return 1
    write_unbound_conf || return 1
    init_root_key || return 1
    # Unbound doit répondre avant que les services pointent sur 127.0.0.1
    start_unbound || return 1
    set_fallback_dns || return 1

    echo ""
    log_info "Little Snitch : autoriser unbound vers tout serveur, port 53 (UDP et TCP)."
    log_info "Son chiffrement DNS doit rester désactivé : il court-circuiterait Mullvad et Unbound."
}

# ══════════════════════════════════════════════════════════════════
# 2. NTP AVEC NTS (CHRONY)
# ══════════════════════════════════════════════════════════════════
check_chrony_installed() {
    if [[ ! -x "$CHRONYD" ]]; then
        log_err "chrony n'est pas installé."
        log_info "Installation : brew install chrony"
        return 1
    fi
    local version
    version=$("$CHRONYD" --version 2>&1 | head -1)
    log_ok "chrony trouvé : $version"
    return 0
}

write_chrony_conf() {
    log_section "Configuration chrony (NTS)"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[dry-run] Écriture de $CHRONY_CONF"
        cat << 'CONF'
# ── Serveurs NTS (authentifiés) ───────────────────────────────
server time.cloudflare.com iburst nts
server ntppool1.time.nl    iburst nts
server nts.netnod.se        iburst nts
server ptbtime1.ptb.de      iburst nts

# Exiger au minimum 2 sources concordantes pour ajuster l'horloge
minsources 2

# Préférer les sources NTS ; ignorer les non-authentifiées si NTS dispo
authselectmode prefer

# Fichier de dérive (compensation de la fréquence d'horloge)
driftfile /var/db/chrony/drift

# Stockage des cookies NTS entre redémarrages
ntsdumpdir /var/db/chrony

# Correction rapide si décalage > 1s (max 3 fois au démarrage)
makestep 1.0 3

# Pas de port de commande ouvert sur le réseau
cmdport 0

# Pas de log client
noclientlog

# Fichier PID
pidfile /var/run/chrony/chronyd.pid

# Gestion du leap second
leapsectz right/UTC
CONF
        return
    fi

    # Créer les répertoires de données
    sudo mkdir -p "$CHRONY_VAR"
    sudo mkdir -p /var/run/chrony

    # Écrire la configuration
    sudo tee "$CHRONY_CONF" > /dev/null << 'CONF'
# ═══════════════════════════════════════════════════════════════
# chrony.conf — NTP avec NTS (Network Time Security)
# Généré par configure-network-security.sh
# ═══════════════════════════════════════════════════════════════

# ── Serveurs NTS (authentifiés) ───────────────────────────────
# Cloudflare (anycast mondial)
server time.cloudflare.com iburst nts

# SIDN Labs / Pays-Bas
server ntppool1.time.nl    iburst nts

# Netnod / Suède (opérateur IXP)
server nts.netnod.se        iburst nts

# PTB / Allemagne (institut national de métrologie)
server ptbtime1.ptb.de      iburst nts

# ── Politique de sécurité ─────────────────────────────────────
# Exiger au minimum 2 sources concordantes
minsources 2

# Préférer les sources NTS ; ignorer les non-authentifiées si NTS OK
authselectmode prefer

# ── Fichiers de données ──────────────────────────────────────
driftfile /var/db/chrony/drift
ntsdumpdir /var/db/chrony

# ── Comportement ─────────────────────────────────────────────
# Correction rapide si décalage > 1s (max 3 fois au démarrage)
makestep 1.0 3

# Pas de port de commande ouvert sur le réseau
cmdport 0

# Pas de log client
noclientlog

# Fichier PID
pidfile /var/run/chrony/chronyd.pid

# Leap second via tzdata
leapsectz right/UTC
CONF

    log_ok "Configuration NTS écrite dans $CHRONY_CONF"
}

install_chrony_launchdaemon() {
    log_section "LaunchDaemon chrony"

    if [[ -f "$CHRONY_PLIST" ]]; then
        log_ok "LaunchDaemon déjà présent"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[dry-run] Création de $CHRONY_PLIST"
        return 0
    fi

    sudo tee "$CHRONY_PLIST" > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.tuxfamily.chrony</string>
    <key>Nice</key>
    <integer>-10</integer>
    <key>ProgramArguments</key>
    <array>
        <string>${CHRONYD}</string>
        <string>-n</string>
        <string>-f</string>
        <string>${CHRONY_CONF}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

    log_ok "LaunchDaemon créé"
}

disable_timed() {
    log_section "Désactivation de timed (NTP natif Apple)"

    # Vérifier si timed est actif
    if sudo launchctl print system/"$TIMED_LABEL" &>/dev/null 2>&1; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[dry-run] sudo launchctl disable system/$TIMED_LABEL"
        else
            sudo launchctl disable system/"$TIMED_LABEL"
            # Arrêter timed s'il tourne
            sudo launchctl bootout system/"$TIMED_LABEL" 2>/dev/null || true
            log_ok "timed désactivé"
        fi
    else
        log_ok "timed déjà désactivé"
    fi
}

start_chrony() {
    log_section "Démarrage de chrony"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[dry-run] sudo launchctl load $CHRONY_PLIST"
        return 0
    fi

    # Recharger si déjà chargé
    sudo launchctl bootout system/org.tuxfamily.chrony 2>/dev/null || true
    sudo launchctl load "$CHRONY_PLIST"

    # Attendre un peu que chrony démarre
    sleep 2

    if pgrep -x chronyd > /dev/null; then
        log_ok "chronyd actif (PID $(pgrep -x chronyd))"
    else
        log_err "chronyd n'a pas démarré — vérifier : sudo ${CHRONYD} -n -f ${CHRONY_CONF}"
        return 1
    fi
}

configure_nts() {
    if ! check_chrony_installed; then
        return 1
    fi

    write_chrony_conf
    install_chrony_launchdaemon
    disable_timed
    start_chrony
}

# ══════════════════════════════════════════════════════════════════
# 3. STATUS
# ══════════════════════════════════════════════════════════════════
show_status() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           Sécurité réseau — État actuel                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"

    # ── DNS ───────────────────────────────────────────────────────
    log_section "DNS"

    # Réglage manuel de chaque service (ce que Mullvad remet à la déconnexion)
    local services=() line svc dns
    while IFS= read -r line; do
        [[ -n "$line" ]] && services+=("$line")
    done < <(detect_interfaces)

    for svc in ${services[@]+"${services[@]}"}; do
        dns=$(networksetup -getdnsservers "$svc" 2> /dev/null || echo "aucun")
        if [[ "$dns" == "$DNS_FALLBACK" ]]; then
            log_ok "$svc : repli Unbound ($DNS_FALLBACK)"
        elif grep -qE "$QUAD9_REGEX" <<< "$dns"; then
            log_err "$svc : Quad9 encore configuré — il ne répond plus en France depuis le 24/11/2026"
        elif grep -qi "any DNS" <<< "$dns"; then
            log_warn "$svc : DNS automatique (DHCP, UDM Pro) — pas de repli Unbound"
        else
            log_warn "$svc : DNS = $(tr '\n' ' ' <<< "$dns")"
        fi
    done

    # Résolveur réellement utilisé : Mullvad remplace le réglage tant qu'il est actif
    local active
    active=$(scutil --dns | awk '/nameserver\[[0-9]+\]/ {print $3}' | sort -u | tr '\n' ' ')
    active=${active% }
    if [[ "$active" == "$DNS_FALLBACK" ]]; then
        log_ok "Résolveur actif : Unbound ($DNS_FALLBACK)"
    elif [[ "$active" =~ ^127\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_ok "Résolveur actif : relais local de Mullvad ($active) → DNS du tunnel"
    else
        log_warn "Résolveur actif : ${active:-aucun} — ni Mullvad ni Unbound"
    fi

    # Unbound
    if pgrep -x unbound > /dev/null 2>&1; then
        if unbound_answers; then
            log_ok "unbound actif, répond sur $DNS_FALLBACK"
        else
            log_err "unbound actif mais ne répond pas sur $DNS_FALLBACK"
        fi
    elif [[ -x "$UNBOUND" ]]; then
        log_err "unbound arrêté — sudo brew services start unbound"
    else
        log_err "unbound non installé — brew install unbound"
    fi
    if [[ -f "$UNBOUND_ROOTKEY" ]] && grep -q "$ROOT_KSK_2024" "$UNBOUND_ROOTKEY"; then
        log_ok "Ancre DNSSEC à jour (KSK-2024 présente)"
    else
        log_warn "Ancre DNSSEC absente ou sans KSK-2024 : $UNBOUND_ROOTKEY"
    fi

    # Little Snitch
    if pgrep -x "Little Snitch" > /dev/null 2>&1 || pgrep -f "at.obdev.littlesnitch" > /dev/null 2>&1; then
        log_ok "Little Snitch actif"
        log_info "Son chiffrement DNS doit rester désactivé (il court-circuiterait Mullvad et Unbound)"
    else
        log_warn "Little Snitch non détecté"
    fi

    # ── NTP / NTS ─────────────────────────────────────────────────
    log_section "NTP / NTS"

    if pgrep -x chronyd > /dev/null 2>&1; then
        log_ok "chronyd actif (PID $(pgrep -x chronyd))"

        # Sources NTS
        if [[ -x "$CHRONYC" ]]; then
            echo ""
            echo "  Sources :"
            sudo "$CHRONYC" sources 2>/dev/null | while IFS= read -r line; do
                echo "    $line"
            done

            echo ""
            echo "  Authentification NTS :"
            sudo "$CHRONYC" authdata 2>/dev/null | while IFS= read -r line; do
                echo "    $line"
            done
        fi
    elif pgrep -x timed > /dev/null 2>&1; then
        log_warn "timed actif (NTP classique, non authentifié)"
        local ntp_server
        ntp_server=$(sudo systemsetup -getnetworktimeserver 2>/dev/null | awk -F': ' '{print $2}')
        log_info "Serveur NTP : ${ntp_server:-inconnu}"
    else
        log_err "Aucun service NTP actif"
    fi

    # ── Mullvad ───────────────────────────────────────────────────
    log_section "Mullvad VPN"

    if command -v mullvad &>/dev/null; then
        # Comparaisons exactes : « Disconnected » contient « connected »,
        # et « disconnected: off » contient « on »
        local status state lockdown relay
        status=$(mullvad status 2> /dev/null || echo "inconnu")
        state=$(awk 'NR==1' <<< "$status")
        relay=$(awk '/Relay:/ {print $2; exit}' <<< "$status")
        lockdown=$(mullvad lockdown-mode get 2> /dev/null | awk '{print $NF}')

        case "$state" in
            Connected*)
                log_ok "Connecté — relais ${relay:-inconnu}"
                log_info "DNS : relais local de Mullvad → DNS du tunnel (bloqueurs : mullvad dns get)"
                ;;
            Disconnected*)
                if [[ "$lockdown" == "on" ]]; then
                    log_warn "Déconnecté, verrouillage actif — tout est bloqué, Unbound compris"
                else
                    log_warn "Déconnecté — DNS = Unbound ($DNS_FALLBACK), requêtes en clair hors tunnel"
                fi
                ;;
            *)
                log_warn "État : $state"
                ;;
        esac

        if [[ "$lockdown" == "on" ]]; then
            log_ok "Kill switch + mode verrouillage actifs"
        else
            log_warn "Mode verrouillage désactivé"
        fi
    else
        log_warn "Mullvad CLI non trouvé"
    fi

    # ── Coupe-feu macOS (ALF) ─────────────────────────────────────
    log_section "Coupe-feu macOS (ALF)"
    local fw_status
    fw_status=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo "")
    if echo "$fw_status" | grep -qi "disabled"; then
        log_ok "ALF désactivé (Little Snitch gère le filtrage)"
    else
        log_info "ALF activé — potentielle redondance avec Little Snitch"
    fi

    echo ""
}

# ══════════════════════════════════════════════════════════════════
# 4. ROLLBACK DNS → DHCP
# ══════════════════════════════════════════════════════════════════
rollback_dns() {
    log_section "Rollback : DNS automatique (DHCP)"

    local services=() line svc
    while IFS= read -r line; do
        [[ -n "$line" ]] && services+=("$line")
    done < <(detect_interfaces)

    for svc in ${services[@]+"${services[@]}"}; do
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[dry-run] networksetup -setdnsservers \"$svc\" Empty"
        else
            networksetup -setdnsservers "$svc" Empty
            log_ok "$svc : DNS automatique (DHCP)"
        fi
    done
    log_info "Hors tunnel, le DNS sera celui de l'UDM Pro."
    log_info "unbound tourne toujours — arrêt : sudo brew services stop unbound"
}

# ══════════════════════════════════════════════════════════════════
# 5. ROLLBACK NTS → TIMED
# ══════════════════════════════════════════════════════════════════
rollback_nts() {
    log_section "Rollback : réactivation de timed"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[dry-run] Arrêt chrony, réactivation timed"
        return 0
    fi

    # Arrêter chrony
    sudo launchctl bootout system/org.tuxfamily.chrony 2>/dev/null || true
    sudo launchctl disable system/org.tuxfamily.chrony 2>/dev/null || true

    # Réactiver timed
    sudo launchctl enable system/"$TIMED_LABEL"
    sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.timed.plist 2>/dev/null || true

    # Remettre le serveur NTP par défaut
    sudo systemsetup -setnetworktimeserver "time.apple.com" 2>/dev/null || true

    log_ok "timed réactivé avec time.apple.com"
    log_info "chrony est toujours installé — supprimer avec : brew uninstall chrony"
    log_info "Plist conservé : $CHRONY_PLIST (supprimer manuellement si souhaité)"
}

# ══════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════
usage() {
    echo "Usage: $0 [--status|--dry-run|--dns-only|--nts-only|--rollback-dns|--rollback-nts]"
    echo ""
    echo "  (sans option)    Appliquer le repli DNS Unbound + NTS (nécessite sudo)"
    echo "  --status         Afficher l'état actuel"
    echo "  --dry-run        Simuler les changements"
    echo "  --dns-only       Configurer uniquement le repli DNS (Unbound)"
    echo "  --nts-only       Configurer uniquement chrony NTS"
    echo "  --rollback-dns   Remettre le DNS automatique (DHCP) sur les services"
    echo "  --rollback-nts   Désactiver chrony et réactiver timed"
    echo ""
}

main() {
    local action="${1:-apply}"

    case "$action" in
        --status)
            show_status
            ;;
        --dry-run)
            DRY_RUN=true
            echo ""
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║           Mode simulation (dry-run)                        ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            configure_dns
            configure_nts
            ;;
        --dns-only)
            if [[ $EUID -ne 0 ]]; then
                log_err "Ce script nécessite sudo pour configurer le DNS."
                exit 1
            fi
            configure_dns
            ;;
        --nts-only)
            if [[ $EUID -ne 0 ]]; then
                log_err "Ce script nécessite sudo pour configurer chrony."
                exit 1
            fi
            configure_nts
            ;;
        --rollback-dns)
            if [[ $EUID -ne 0 ]]; then
                log_err "Ce script nécessite sudo."
                exit 1
            fi
            rollback_dns
            ;;
        --rollback-nts)
            if [[ $EUID -ne 0 ]]; then
                log_err "Ce script nécessite sudo."
                exit 1
            fi
            rollback_nts
            ;;
        --help|-h)
            usage
            ;;
        apply)
            if [[ $EUID -ne 0 ]]; then
                log_err "Ce script nécessite sudo."
                echo "  Usage : sudo $0"
                echo "  Voir l'état : $0 --status"
                exit 1
            fi
            echo ""
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║       Sécurité réseau — Configuration                      ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            configure_dns
            configure_nts

            echo ""
            log_section "Résumé"
            echo ""
            echo "  DNS :  Unbound ($DNS_FALLBACK) en repli hors tunnel sur les services Wi-Fi/Ethernet"
            echo "  NTS :  chrony avec 4 serveurs NTS authentifiés"
            echo "  NTP :  timed (Apple) désactivé, remplacé par chrony"
            echo ""
            echo "  Prochaines étapes :"
            echo "  1. Vérifier l'état : $0 --status"
            echo "  2. Dans Réglages Système → Date et heure :"
            echo "     le serveur NTP affiché n'est plus utilisé (chrony le remplace)"
            echo "  3. Vérifier que Little Snitch autorise chronyd (${CHRONYD})"
            echo "     vers les ports 123/UDP et 4460/TCP (NTS-KE),"
            echo "     et unbound (${UNBOUND}) vers le port 53 (UDP et TCP)"
            echo "  4. Tester Unbound hors tunnel (procédure en tête du script)"
            echo ""
            echo "  Rollback si problème : sudo $0 --rollback-dns | --rollback-nts"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"

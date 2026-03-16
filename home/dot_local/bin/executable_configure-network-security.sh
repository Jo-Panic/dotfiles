#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# configure-network-security.sh
# Sécurité réseau macOS : DNS fallback Quad9 + NTP authentifié (NTS)
#
# Équivalent macOS de :
#   - arch-dotfiles : nmcli ipv4.dns "9.9.9.9 149.112.112.112"
#   - arch-dotfiles : chrony avec NTS (si configuré)
#
# Prérequis : brew install chrony
# Emplacement : ~/.local/bin/configure-network-security.sh
# ═══════════════════════════════════════════════════════════════════

# ── Couleurs ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── DNS Quad9 ─────────────────────────────────────────────────────
DNS_PRIMARY="9.9.9.9"
DNS_SECONDARY="149.112.112.112"
DNS_PRIMARY_V6="2620:fe::fe"
DNS_SECONDARY_V6="2620:fe::9"

# ── Homebrew prefix (ARM vs Intel) ────────────────────────────────
if [[ -d "/opt/homebrew" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

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

# ── Détection des interfaces réseau ───────────────────────────────
# Retourne les noms de service un par ligne (gère les espaces dans les noms)
detect_interfaces() {
    # Wi-Fi
    local wifi_dev
    wifi_dev=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
    if [[ -n "$wifi_dev" ]]; then
        echo "Wi-Fi"
    fi

    # Ethernet / Dock OWC
    networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r svc; do
        case "$svc" in
            *USB*|*Ethernet*|*Thunderbolt*|*LAN*)
                if [[ "$svc" != "Wi-Fi" ]]; then
                    echo "$svc"
                fi
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════
# 1. DNS FALLBACK QUAD9
# ══════════════════════════════════════════════════════════════════
configure_dns() {
    log_section "DNS Fallback — Quad9"
    echo -e "  Chaîne de résolution : Mullvad DNS (VPN actif)"
    echo -e "                       → NextDNS DoH (Little Snitch)"
    echo -e "                       → ${GREEN}Quad9${NC} (fallback système)"

    local interfaces=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && interfaces+=("$line")
    done < <(detect_interfaces)

    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log_err "Aucune interface réseau détectée"
        return 1
    fi

    for iface in "${interfaces[@]}"; do
        local current_dns
        current_dns=$(networksetup -getdnsservers "$iface" 2>/dev/null || echo "")

        if echo "$current_dns" | grep -q "$DNS_PRIMARY" && echo "$current_dns" | grep -q "$DNS_SECONDARY"; then
            log_ok "$iface : Quad9 déjà configuré"
        else
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                log_info "[dry-run] networksetup -setdnsservers \"$iface\" $DNS_PRIMARY $DNS_SECONDARY"
            else
                networksetup -setdnsservers "$iface" "$DNS_PRIMARY" "$DNS_SECONDARY"
                log_ok "$iface : DNS défini sur $DNS_PRIMARY / $DNS_SECONDARY"
            fi
        fi
    done

    echo ""
    log_info "Note : Little Snitch intercepte le DNS avant le résolveur système."
    log_info "Quad9 n'est sollicité que si Little Snitch est indisponible."
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

    local interfaces=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && interfaces+=("$line")
    done < <(detect_interfaces)

    for iface in "${interfaces[@]}"; do
        local dns
        dns=$(networksetup -getdnsservers "$iface" 2>/dev/null || echo "aucun")
        if echo "$dns" | grep -q "$DNS_PRIMARY"; then
            log_ok "$iface : Quad9 configuré"
        elif echo "$dns" | grep -qi "any DNS"; then
            log_warn "$iface : DNS automatique (DHCP) — pas de fallback"
        else
            log_warn "$iface : DNS = $(echo "$dns" | tr '\n' ', ')"
        fi
    done

    # Little Snitch DNS
    if pgrep -x "Little Snitch" > /dev/null 2>&1 || pgrep -f "at.obdev.littlesnitch" > /dev/null 2>&1; then
        log_ok "Little Snitch actif (DNS NextDNS DoH en priorité)"
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
        local status
        status=$(mullvad status 2>/dev/null || echo "inconnu")
        if echo "$status" | grep -qi "connected"; then
            log_ok "Connecté — $(echo "$status" | head -1)"
            log_info "DNS dans le tunnel = résolveurs Mullvad"
        else
            log_warn "Déconnecté — DNS = NextDNS (Little Snitch) → Quad9 (fallback)"
        fi

        local ks
        ks=$(mullvad lockdown-mode get 2>/dev/null || echo "")
        if echo "$ks" | grep -qi "on"; then
            log_ok "Kill switch + mode verrouillage actifs"
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
# 4. ROLLBACK NTS → TIMED
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
    echo "Usage: $0 [--status|--dry-run|--rollback-nts|--dns-only|--nts-only]"
    echo ""
    echo "  (sans option)    Appliquer DNS fallback + NTS (nécessite sudo)"
    echo "  --status         Afficher l'état actuel"
    echo "  --dry-run        Simuler les changements"
    echo "  --dns-only       Configurer uniquement le DNS fallback Quad9"
    echo "  --nts-only       Configurer uniquement chrony NTS"
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
            echo "  DNS :  Quad9 (9.9.9.9) en fallback sur toutes les interfaces"
            echo "  NTS :  chrony avec 4 serveurs NTS authentifiés"
            echo "  NTP :  timed (Apple) désactivé, remplacé par chrony"
            echo ""
            echo "  Prochaines étapes :"
            echo "  1. Vérifier l'état : $0 --status"
            echo "  2. Dans Réglages Système → Date et heure :"
            echo "     le serveur NTP affiché n'est plus utilisé (chrony le remplace)"
            echo "  3. Vérifier que Little Snitch autorise chronyd (${CHRONYD})"
            echo "     vers les ports 123/UDP et 4460/TCP (NTS-KE)"
            echo ""
            echo "  Rollback si problème : sudo $0 --rollback-nts"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"

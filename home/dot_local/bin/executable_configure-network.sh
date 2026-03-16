#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# configure-network.sh — Configuration réseau macOS
# Équivalent macOS de arch-dotfiles/scripts/01-configure-system.sh
# ══════════════════════════════════════════════════════════════
#
# Usage : sudo ./configure-network.sh [--dry-run] [--status]
#
# Ce script configure :
#   1. Routes statiques par VLAN (Wi-Fi + Ethernet)
#   2. mDNS / Bonjour pour la découverte réseau inter-VLAN
#   3. Vérification de la connectivité scanner/imprimante
#   4. Rappels pour Mullvad et LittleSnitch
#
# Nécessite : droits root (sudo) sauf pour --status
# ══════════════════════════════════════════════════════════════

# ── Couleurs ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Configuration réseau ──────────────────────────────────────
GATEWAY="192.168.0.1"

# VLANs : nom / VLAN ID / subnet
# Note : le Mac est sur le VLAN 1 (LAN-MGMT / native network)
declare -a VLAN_NAMES=("LAN-MGMT" "IOT" "FAMILLE" "GUEST" "NAS")
declare -a VLAN_IDS=(1 10 20 30 40)
declare -a VLAN_SUBNETS=("192.168.0.0" "192.168.10.0" "192.168.20.0" "192.168.30.0" "192.168.40.0")
VLAN_MASK="255.255.255.0"

# Interfaces réseau macOS
WIFI_SERVICE="Wi-Fi"
ETH_SERVICE="Ethernet"

# Imprimante / Scanner HP (VLAN 10 — IOT)
PRINTER_IP="192.168.10.5"
PRINTER_NAME="HP Printer/Scanner"

# Ports
PRINT_PORTS_DESC="515 (LPD), 631 (IPP/CUPS), 9100 (RAW)"
SCAN_PORTS_DESC="80, 443, 8080, 9095 (eSCL/AirScan)"

# ── Fonctions utilitaires ─────────────────────────────────────
DRY_RUN=false
STATUS_ONLY=false
ACTIVE_SERVICES=()

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${CYAN}═══ $* ═══${NC}"; }

run_cmd() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        eval "$@"
    fi
}

# ── Parsing des arguments ─────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN=true ;;
        --status)     STATUS_ONLY=true ;;
        --help|-h)
            echo "Usage: sudo $0 [--dry-run] [--status]"
            echo ""
            echo "  --dry-run   Affiche les commandes sans les exécuter"
            echo "  --status    Affiche l'état actuel sans modifier"
            exit 0
            ;;
        *)
            echo "Option inconnue: $arg"
            exit 1
            ;;
    esac
done

# ── Vérification root ─────────────────────────────────────────
if [[ $EUID -ne 0 ]] && ! $STATUS_ONLY; then
    log_error "Ce script doit être lancé avec sudo"
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# Détection des interfaces réseau actives
# ══════════════════════════════════════════════════════════════
detect_interfaces() {
    log_section "Détection des interfaces réseau"

    # Vérifier Wi-Fi
    if networksetup -getinfo "$WIFI_SERVICE" 2>/dev/null | grep -q "^IP address:"; then
        local wifi_ip
        wifi_ip=$(networksetup -getinfo "$WIFI_SERVICE" | grep "^IP address:" | awk '{print $3}')
        log_ok "Wi-Fi actif — IP : $wifi_ip"
        ACTIVE_SERVICES+=("$WIFI_SERVICE")
    else
        log_warn "Wi-Fi non connecté ou inexistant"
    fi

    # Vérifier Ethernet — tester les noms courants (dock OWC / Thunderbolt)
    local eth_found=false
    for eth_name in "Ethernet" "Thunderbolt Ethernet" "USB 10/100/1000 LAN" "Thunderbolt Bridge"; do
        if networksetup -getinfo "$eth_name" 2>/dev/null | grep -q "^IP address:"; then
            local eth_ip
            eth_ip=$(networksetup -getinfo "$eth_name" | grep "^IP address:" | awk '{print $3}')
            log_ok "$eth_name actif — IP : $eth_ip"
            ETH_SERVICE="$eth_name"
            ACTIVE_SERVICES+=("$eth_name")
            eth_found=true
            break
        fi
    done

    if ! $eth_found; then
        log_warn "Aucune interface Ethernet détectée (dock OWC non connecté ?)"
    fi
}

# ══════════════════════════════════════════════════════════════
# Afficher l'état actuel
# ══════════════════════════════════════════════════════════════
show_status() {

    # ── Routes ────────────────────────────────────────────────
    log_section "État actuel des routes"

    local services_to_check=()
    for svc in "${ACTIVE_SERVICES[@]}"; do
        services_to_check+=("$svc")
    done

    for service in "${services_to_check[@]}"; do
        echo -e "\n${CYAN}── $service ──${NC}"
        local routes
        routes=$(networksetup -getadditionalroutes "$service" 2>/dev/null || true)
        if [[ -z "$routes" ]] || echo "$routes" | grep -q "There are no additional"; then
            log_warn "Aucune route additionnelle"
        else
            echo "$routes"
        fi
    done

    log_section "Table de routage système (VLANs)"
    netstat -rn -f inet | head -3
    netstat -rn -f inet | grep -E "192\.168\.(0|10|20|30|40)\." || log_warn "Aucune route VLAN trouvée"

    # ── mDNS / Bonjour ───────────────────────────────────────
    log_section "État mDNS / Bonjour"
    # launchctl list nécessite root pour voir les services système
    # pgrep fonctionne sans sudo
    if pgrep -x mDNSResponder &>/dev/null; then
        log_ok "mDNSResponder actif (PID : $(pgrep -x mDNSResponder))"
    else
        log_error "mDNSResponder inactif — Bonjour ne fonctionnera pas"
    fi

    # dns-sd tourne indéfiniment sur macOS
    # On utilise une subshell pour isoler le processus et éviter les problèmes avec set -e
    local bonjour_tmp
    bonjour_tmp=$(mktemp)

    # Fonction helper pour lancer dns-sd avec timeout
    _bonjour_search() {
        local service_type="$1"
        local label="$2"
        local secs="${3:-3}"

        : > "$bonjour_tmp"
        log_info "Recherche $label via Bonjour (${secs}s)..."

        # Subshell : dns-sd en background, sleep, kill — isolé du set -e principal
        (
            dns-sd -B "$service_type" > "$bonjour_tmp" 2>/dev/null &
            local pid=$!
            sleep "$secs"
            kill "$pid" 2>/dev/null
        ) 2>/dev/null || true

        if [[ -s "$bonjour_tmp" ]] && grep -q "Add" "$bonjour_tmp"; then
            log_ok "$label trouvé(s) :"
            grep "Add" "$bonjour_tmp" | head -10 | while read -r line; do
                echo "    $line"
            done
        else
            log_warn "Aucun $label trouvé via mDNS ($service_type)"
        fi
    }

    _bonjour_search "_ipp._tcp" "services d'impression"
    _bonjour_search "_uscan._tcp" "scanners eSCL"
    _bonjour_search "_scanner._tcp" "scanners (_scanner._tcp)"

    rm -f "$bonjour_tmp"

    # ── Connectivité imprimante ───────────────────────────────
    log_section "Connectivité imprimante/scanner ($PRINTER_IP)"
    if ping -c 1 -W 2 "$PRINTER_IP" &>/dev/null; then
        log_ok "Imprimante accessible (ping OK)"
    else
        log_error "Imprimante non accessible (ping échoué)"
        log_info "Vérifier : route vers 192.168.10.0/24, firewall UDM Pro, Mullvad LAN"
    fi

    # Test des ports (nc sur macOS : -G pour connect timeout)
    log_info "Test des ports sur $PRINTER_IP..."
    for port in 80 443 515 631 8080 9095 9100; do
        if nc -z -G 2 "$PRINTER_IP" "$port" 2>/dev/null; then
            log_ok "Port $port ouvert"
        else
            log_warn "Port $port fermé ou filtré"
        fi
    done

    # Test eSCL
    log_info "Test du protocole eSCL/AirScan..."
    local escl_found=false
    for port in 80 443 8080 9095; do
        local escl_url="http://${PRINTER_IP}:${port}/eSCL/ScannerCapabilities"
        if curl -s --connect-timeout 3 --max-time 5 "$escl_url" 2>/dev/null | grep -qi "scanner"; then
            log_ok "eSCL actif sur port $port — $escl_url"
            escl_found=true
        fi
    done
    if ! $escl_found; then
        log_warn "eSCL non détecté — vérifier l'EWS de l'imprimante (http://$PRINTER_IP)"
    fi

    # ── Mullvad ───────────────────────────────────────────────
    log_section "Mullvad VPN"
    if command -v mullvad &>/dev/null; then
        local mullvad_status
        mullvad_status=$(mullvad status 2>/dev/null || echo "inconnu")
        log_info "Statut : $mullvad_status"

        local lan_status
        lan_status=$(mullvad lan get 2>/dev/null || echo "inconnu")
        if echo "$lan_status" | grep -qi "allow"; then
            log_ok "LAN sharing : autorisé"
        else
            log_warn "LAN sharing : $lan_status — corriger avec : mullvad lan set allow"
        fi
    else
        log_warn "Mullvad CLI non trouvé"
    fi
}

# ══════════════════════════════════════════════════════════════
# Configurer les routes VLAN
# ══════════════════════════════════════════════════════════════
configure_routes() {
    log_section "Configuration des routes VLAN"

    for service in "${ACTIVE_SERVICES[@]}"; do
        log_info "Configuration des routes pour : $service"

        # networksetup -setadditionalroutes attend : dest1 mask1 gw1 dest2 mask2 gw2 ...
        local route_args=""
        for i in "${!VLAN_SUBNETS[@]}"; do
            route_args+="${VLAN_SUBNETS[$i]} $VLAN_MASK $GATEWAY "
            log_info "  → ${VLAN_NAMES[$i]} (VLAN ${VLAN_IDS[$i]}) : ${VLAN_SUBNETS[$i]}/24 via $GATEWAY"
        done

        run_cmd "networksetup -setadditionalroutes '$service' $route_args"

        if ! $DRY_RUN; then
            log_ok "Routes configurées pour $service"
        fi
    done
}

# ══════════════════════════════════════════════════════════════
# Configurer mDNS / Bonjour
# ══════════════════════════════════════════════════════════════
configure_mdns() {
    log_section "Configuration mDNS / Bonjour"

    if pgrep -x mDNSResponder &>/dev/null; then
        log_ok "mDNSResponder est actif"
    else
        log_warn "mDNSResponder semble inactif — tentative de redémarrage"
        run_cmd "launchctl kickstart -k system/com.apple.mDNSResponder"
    fi

    log_info "Flush du cache DNS..."
    run_cmd "dscacheutil -flushcache"
    run_cmd "killall -HUP mDNSResponder 2>/dev/null || true"
    log_ok "Cache DNS vidé et mDNSResponder relancé"
}

# ══════════════════════════════════════════════════════════════
# Vérifications et conseils pour le scanner
# ══════════════════════════════════════════════════════════════
scanner_checks() {
    log_section "Vérifications scanner HP ($PRINTER_IP)"

    echo -e "\n${CYAN}── Checklist scanner ──${NC}"
    echo ""

    # 1. Route vers le VLAN IoT
    if netstat -rn -f inet | grep -q "192.168.10"; then
        log_ok "Route vers VLAN 10 (IoT) présente"
    else
        log_error "Route vers VLAN 10 (IoT) manquante — lancer sans --status pour configurer"
    fi

    # 2. Ping imprimante
    if ping -c 1 -W 2 "$PRINTER_IP" &>/dev/null; then
        log_ok "Imprimante joignable ($PRINTER_IP)"
    else
        log_error "Imprimante injoignable — vérifier les routes et le firewall UDM Pro"
    fi

    # 3. Test eSCL
    local escl_found=false
    for port in 80 443 8080 9095; do
        if curl -s --connect-timeout 3 --max-time 5 "http://${PRINTER_IP}:${port}/eSCL/ScannerCapabilities" 2>/dev/null | grep -qi "scanner"; then
            log_ok "eSCL/AirScan détecté sur le port $port"
            escl_found=true
            break
        fi
    done

    if ! $escl_found; then
        log_warn "eSCL non détecté — le protocole est peut-être désactivé sur l'imprimante"
        echo ""
        log_info "Actions à vérifier sur l'EWS :"
        echo "  1. Ouvrir http://$PRINTER_IP dans un navigateur"
        echo "  2. Onglet Réseau → Paramètres avancés"
        echo "  3. Activer 'eSCL' ou 'WebScan'"
        echo "  4. Onglet Sécurité → Activer 'Remote User Auto Capture'"
        echo "  5. Appliquer et redémarrer l'imprimante"
    fi

    # 4. Rappels Mullvad
    echo ""
    log_section "Rappels Mullvad VPN"
    if command -v mullvad &>/dev/null; then
        local lan_status
        lan_status=$(mullvad lan get 2>/dev/null || echo "inconnu")
        if echo "$lan_status" | grep -qi "allow"; then
            log_ok "Mullvad LAN sharing : autorisé"
        else
            log_warn "Mullvad LAN sharing : $lan_status"
            echo "  → Corriger avec : mullvad lan set allow"
        fi
    fi

    # 5. Rappels LittleSnitch
    echo ""
    log_section "Rappels LittleSnitch"
    echo -e "  Processus à autoriser vers ${GREEN}$PRINTER_IP${NC} et ${GREEN}224.0.0.251${NC} :"
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────────────┐"
    echo "  │ Processus                              │ Destination / Ports     │"
    echo "  ├──────────────────────────────────────────────────────────────────┤"
    echo "  │ /usr/sbin/mDNSResponder                │ 224.0.0.251 · UDP 5353 │"
    echo "  │ /usr/sbin/mDNSResponder                │ $PRINTER_IP  · UDP 5353│"
    echo "  │ imagecaptureagent / icdd               │ $PRINTER_IP  · TCP 80  │"
    echo "  │ Image Capture.app                      │ $PRINTER_IP  · TCP 443 │"
    echo "  │                                        │ TCP 8080, 9095         │"
    echo "  └──────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "  ${CYAN}Astuce :${NC} Dans LittleSnitch, créer un groupe de règles 'Réseau local'"
    echo "  autorisant les connexions vers 192.168.0.0/16 pour les processus système."

    # 6. UDM Pro
    echo ""
    log_section "Rappels UDM Pro"
    echo -e "  ${GREEN}✓${NC} mDNS Reflector activé sur VLAN 1 et VLAN 10"
    echo -e "  ${YELLOW}•${NC} Règles firewall : autoriser VLAN 1 (LAN-MGMT) → VLAN 10 (IOT)"
    echo "    Ports minimum : TCP 80, 443, 515, 631, 8080, 9095, 9100 + UDP 5353"
}

# ══════════════════════════════════════════════════════════════
# LaunchDaemon pour persistance au boot
# ══════════════════════════════════════════════════════════════
generate_launchd() {
    log_section "Persistance (LaunchDaemon)"

    local plist_path="/Library/LaunchDaemons/com.local.network-routes.plist"
    local script_path
    script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    if [[ -f "$plist_path" ]]; then
        log_ok "LaunchDaemon déjà installé : $plist_path"
        return
    fi

    log_info "Pour appliquer les routes automatiquement au démarrage :"
    echo ""
    cat << PLIST_EOF
  sudo tee $plist_path << 'EOF'
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.local.network-routes</string>
      <key>ProgramArguments</key>
      <array>
          <string>/bin/bash</string>
          <string>$script_path</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>WatchPaths</key>
      <array>
          <string>/Library/Preferences/SystemConfiguration</string>
      </array>
      <key>StandardOutPath</key>
      <string>/var/log/network-routes.log</string>
      <key>StandardErrorPath</key>
      <string>/var/log/network-routes.log</string>
  </dict>
  </plist>
  EOF

  sudo launchctl load $plist_path
PLIST_EOF
}

# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════
main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     Configuration réseau macOS — VLANs & Scanner       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if $DRY_RUN; then
        log_warn "Mode DRY-RUN — aucune modification ne sera effectuée"
    fi

    detect_interfaces

    if $STATUS_ONLY; then
        show_status
        exit 0
    fi

    configure_routes
    configure_mdns
    scanner_checks
    generate_launchd

    echo ""
    log_section "Résumé"
    echo -e "  ${GREEN}✓${NC} Routes VLAN configurées pour ${#ACTIVE_SERVICES[@]} interface(s)"
    echo -e "  ${GREEN}✓${NC} Cache DNS vidé"
    echo ""
    echo -e "  ${CYAN}Prochaines étapes :${NC}"
    echo "  1. Vérifier l'état : $0 --status"
    echo "  2. Tester le scanner dans Transfert d'images"
    echo "  3. Si le scanner ne fonctionne pas, vérifier LittleSnitch et l'EWS"
}

main "$@"

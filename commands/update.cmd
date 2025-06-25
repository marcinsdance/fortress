#!/bin/bash
#
# Fortress Update Command
# Dodaje komendę 'fortress update' do systemu
#

# Funkcja główna dla komendy update
updateFortress() {
    local UPDATE_BRANCH="main"
    local DRY_RUN=false
    local FORCE=false
    local NO_BACKUP=false
    
    # Parsowanie argumentów
    while [[ $# -gt 0 ]]; do
        case $1 in
            --branch)
                UPDATE_BRANCH="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --no-backup)
                NO_BACKUP=true
                shift
                ;;
            -h|--help)
                showUpdateHelp
                return 0
                ;;
            *)
                echo "Nieznany argument: $1"
                showUpdateHelp
                return 1
                ;;
        esac
    done
    
    # Sprawdź czy skrypt aktualizacji istnieje
    local UPDATE_SCRIPT="/opt/fortress/scripts/fortress-update.sh"
    if [[ ! -f "$UPDATE_SCRIPT" ]]; then
        echo "❌ Skrypt aktualizacji nie został znaleziony: $UPDATE_SCRIPT"
        echo "Pobierz najnowsze skrypty z: https://github.com/marcinsdance/fortress"
        return 1
    fi
    
    # Budowanie argumentów dla skryptu
    local SCRIPT_ARGS=""
    [[ "$UPDATE_BRANCH" != "main" ]] && SCRIPT_ARGS="$SCRIPT_ARGS --branch $UPDATE_BRANCH"
    [[ "$DRY_RUN" == "true" ]] && SCRIPT_ARGS="$SCRIPT_ARGS --dry-run"
    [[ "$FORCE" == "true" ]] && SCRIPT_ARGS="$SCRIPT_ARGS --force"
    [[ "$NO_BACKUP" == "true" ]] && SCRIPT_ARGS="$SCRIPT_ARGS --no-backup"
    
    echo "🚀 Rozpoczynam aktualizację Fortress..."
    echo "Gałąź: $UPDATE_BRANCH"
    [[ "$DRY_RUN" == "true" ]] && echo "Tryb: Symulacja (dry-run)"
    
    # Wykonaj aktualizację
    $UPDATE_SCRIPT $SCRIPT_ARGS
}

# Funkcja weryfikacji po aktualizacji
verifyFortress() {
    local VERIFY_SCRIPT="/opt/fortress/scripts/fortress-verify.sh"
    
    if [[ ! -f "$VERIFY_SCRIPT" ]]; then
        echo "❌ Skrypt weryfikacji nie został znaleziony: $VERIFY_SCRIPT"
        return 1
    fi
    
    echo "🔍 Weryfikacja systemu Fortress..."
    $VERIFY_SCRIPT
}

# Funkcja backup
backupFortress() {
    local BACKUP_SCRIPT="/opt/fortress/scripts/fortress-backup.sh"
    
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        echo "❌ Skrypt backup nie został znaleziony: $BACKUP_SCRIPT"
        return 1
    fi
    
    echo "💾 Tworzenie backup systemu Fortress..."
    $BACKUP_SCRIPT
}

# Funkcja sprawdzenia wersji
checkVersion() {
    echo "📋 Informacje o systemie Fortress:"
    echo "=================================="
    
    # Wersja Fortress
    if [[ -f "/opt/fortress/.version" ]]; then
        echo "Wersja Fortress: $(cat /opt/fortress/.version)"
    else
        echo "Wersja Fortress: Nieznana"
    fi
    
    # Wersja z bin/fortress
    if [[ -f "/opt/fortress/bin/fortress" ]]; then
        local bin_version=$(grep -o 'VERSION="[^"]*"' /opt/fortress/bin/fortress | cut -d'"' -f2 2>/dev/null || echo "Nieznana")
        echo "Wersja binarna: $bin_version"
    fi
    
    # Data ostatniej modyfikacji
    if [[ -f "/opt/fortress/bin/fortress" ]]; then
        echo "Ostatnia modyfikacja: $(stat -c %y /opt/fortress/bin/fortress | cut -d'.' -f1)"
    fi
    
    # Status kontenerów
    echo ""
    echo "Status kontenerów:"
    docker ps --filter name=fortress --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    # Aplikacje
    echo ""
    echo "Zainstalowane aplikacje:"
    if [[ -d "/opt/fortress/apps" ]]; then
        local app_count=$(ls -1 /opt/fortress/apps | wc -l)
        echo "Liczba aplikacji: $app_count"
        ls -1 /opt/fortress/apps 2>/dev/null || echo "Brak aplikacji"
    else
        echo "Katalog aplikacji nie istnieje"
    fi
}

# Pomoc dla komendy update
showUpdateHelp() {
    cat << EOF
fortress update - Aktualizacja systemu Fortress

UŻYCIE:
    fortress update [OPTIONS]
    fortress update verify
    fortress update backup
    fortress update version

OPCJE:
    --branch <nazwa>    Aktualizuj z określonej gałęzi (domyślnie: main)
    --dry-run          Symulacja aktualizacji bez wykonywania zmian
    --force            Wymuś aktualizację nawet przy tej samej wersji
    --no-backup        Pomiń tworzenie backup (niezalecane)
    -h, --help         Wyświetl tę pomoc

PODKOMENDY:
    verify             Weryfikuj system po aktualizacji
    backup             Utwórz backup systemu
    version            Wyświetl informacje o wersji

PRZYKŁADY:
    fortress update                    # Standardowa aktualizacja
    fortress update --dry-run          # Symulacja aktualizacji
    fortress update --branch develop   # Aktualizacja z gałęzi develop
    fortress update verify             # Weryfikacja systemu
    fortress update backup             # Backup systemu

UWAGI:
    - Aktualizacja zachowuje wszystkie aplikacje i dane
    - Przed aktualizacją tworzony jest automatyczny backup
    - Aplikacje działają bez przerwy podczas aktualizacji
    - W razie problemów możliwy jest rollback do poprzedniej wersji
EOF
}

# Router dla subkomend
case "${1:-}" in
    "")
        updateFortress "${@:2}"
        ;;
    verify)
        verifyFortress "${@:2}"
        ;;
    backup)
        backupFortress "${@:2}"
        ;;
    version)
        checkVersion "${@:2}"
        ;;
    -h|--help)
        showUpdateHelp
        ;;
    *)
        updateFortress "$@"
        ;;
esac
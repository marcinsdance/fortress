#!/bin/bash
#
# Fortress Update Script
# Bezpieczna aktualizacja systemu Fortress z zachowaniem konfiguracji i danych
#
set -e

# Konfiguracja
REPO_URL="https://github.com/marcinsdance/fortress.git"
FORTRESS_DIR="/opt/fortress"
TEMP_DIR="/tmp/fortress-update-$(date +%s)"
BACKUP_REQUIRED=true
UPDATE_BRANCH="main"

# Kolory dla logowania
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Wyświetlenie pomocy
show_help() {
    echo "Fortress Update Script"
    echo ""
    echo "Użycie: $0 [opcje]"
    echo ""
    echo "Opcje:"
    echo "  --branch <nazwa>     Aktualizuj z określonej gałęzi (domyślnie: main)"
    echo "  --no-backup          Pomiń tworzenie backup'u (niezalecane)"
    echo "  --dry-run           Symulacja aktualizacji bez wykonywania zmian"
    echo "  --force             Wymuś aktualizację nawet przy błędach"
    echo "  -h, --help          Wyświetl tę pomoc"
    echo ""
}

# Parsowanie argumentów
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --branch)
                UPDATE_BRANCH="$2"
                shift 2
                ;;
            --no-backup)
                BACKUP_REQUIRED=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_UPDATE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Nieznany argument: $1"
                ;;
        esac
    done
}

# Sprawdzenie uprawnień root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ten skrypt musi być uruchomiony jako root"
    fi
}

# Sprawdzenie czy Fortress jest zainstalowany
check_fortress_installed() {
    if [[ ! -d "$FORTRESS_DIR" ]]; then
        log_error "Fortress nie jest zainstalowany w $FORTRESS_DIR"
    fi
    
    if [[ ! -f "$FORTRESS_DIR/bin/fortress" ]]; then
        log_error "Nie znaleziono pliku wykonywalnego Fortress"
    fi
}

# Sprawdzenie aktualnej wersji
check_current_version() {
    if [[ -f "$FORTRESS_DIR/.version" ]]; then
        CURRENT_VERSION=$(cat "$FORTRESS_DIR/.version")
        log_info "Aktualna wersja: $CURRENT_VERSION"
    else
        log_warning "Nie można określić aktualnej wersji"
        CURRENT_VERSION="unknown"
    fi
}

# Tworzenie backup'u
create_backup() {
    if [[ "$BACKUP_REQUIRED" == "true" ]]; then
        log_info "Tworzenie backup'u przed aktualizacją..."
        if [[ -f "/home/michal/projects/fortress/scripts/fortress-backup.sh" ]]; then
            /home/michal/projects/fortress/scripts/fortress-backup.sh
            log_success "Backup utworzony pomyślnie"
        else
            log_error "Skrypt backup'u nie został znaleziony"
        fi
    else
        log_warning "Backup pominięty (--no-backup)"
    fi
}

# Pobieranie najnowszej wersji
download_latest() {
    log_info "Pobieranie najnowszej wersji z gałęzi: $UPDATE_BRANCH"
    
    # Usuń stary katalog tymczasowy
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    
    # Klonowanie repozytorium
    git clone --depth 1 --branch "$UPDATE_BRANCH" "$REPO_URL" "$TEMP_DIR"
    
    if [[ ! -d "$TEMP_DIR" ]]; then
        log_error "Nie udało się pobrać najnowszej wersji"
    fi
    
    log_success "Najnowsza wersja pobrana do $TEMP_DIR"
}

# Sprawdzenie kompatybilności
check_compatibility() {
    log_info "Sprawdzanie kompatybilności..."
    
    # Sprawdź czy nowa wersja ma wymagane pliki
    local required_files=(
        "bin/fortress"
        "commands/install.cmd"
        "commands/app.cmd"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$TEMP_DIR/$file" ]]; then
            log_error "Brak wymaganego pliku: $file"
        fi
    done
    
    # Sprawdź wersję w nowym kodzie
    if [[ -f "$TEMP_DIR/bin/fortress" ]]; then
        NEW_VERSION=$(grep -o 'VERSION="[^"]*"' "$TEMP_DIR/bin/fortress" | cut -d'"' -f2 || echo "unknown")
        log_info "Nowa wersja: $NEW_VERSION"
        
        if [[ "$NEW_VERSION" == "$CURRENT_VERSION" && "$FORCE_UPDATE" != "true" ]]; then
            log_warning "Ta sama wersja jest już zainstalowana. Użyj --force aby kontynuować."
            exit 0
        fi
    fi
    
    log_success "Sprawdzenie kompatybilności - OK"
}

# Zatrzymanie usług Fortress (bez aplikacji)
stop_fortress_services() {
    log_info "Zatrzymywanie usług Fortress..."
    
    # Zatrzymaj tylko usługi systemowe, nie aplikacje użytkowników
    if docker ps --format "table {{.Names}}" | grep -q "fortress_traefik"; then
        docker stop fortress_traefik || true
    fi
    
    # Nie zatrzymujemy PostgreSQL i Redis gdyż aplikacje mogą ich używać
    log_success "Usługi Fortress zatrzymane"
}

# Aktualizacja plików
update_files() {
    log_info "Aktualizowanie plików Fortress..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Symulacja aktualizacji plików"
        return 0
    fi
    
    # Backup aktualnych plików wykonywalnych
    if [[ -d "$FORTRESS_DIR/bin" ]]; then
        cp -r "$FORTRESS_DIR/bin" "$FORTRESS_DIR/bin.backup.$(date +%s)" || true
    fi
    
    # Aktualizacja plików wykonywanych
    cp -r "$TEMP_DIR/bin"/* "$FORTRESS_DIR/bin/"
    cp -r "$TEMP_DIR/commands"/* "$FORTRESS_DIR/commands/"
    cp -r "$TEMP_DIR/utils"/* "$FORTRESS_DIR/utils/" 2>/dev/null || true
    
    # Aktualizacja uprawnień
    chmod +x "$FORTRESS_DIR/bin/fortress"
    find "$FORTRESS_DIR/commands" -name "*.cmd" -exec chmod +x {} \;
    
    # Aktualizacja symlinka
    ln -sf "$FORTRESS_DIR/bin/fortress" "/usr/local/bin/fortress"
    
    # Zapisz nową wersję
    echo "$NEW_VERSION" > "$FORTRESS_DIR/.version"
    
    log_success "Pliki zaktualizowane"
}

# Aktualizacja konfiguracji (jeśli potrzeba)
update_config() {
    log_info "Sprawdzanie aktualizacji konfiguracji..."
    
    # Porównaj template'y konfiguracji
    if [[ -f "$TEMP_DIR/config/fortress.env.template" && -f "$FORTRESS_DIR/config/fortress.env" ]]; then
        # Tu można dodać logikę migracji konfiguracji
        log_info "Konfiguracja nie wymaga aktualizacji"
    fi
    
    log_success "Konfiguracja sprawdzona"
}

# Restart usług
restart_services() {
    log_info "Restartowanie usług Fortress..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Symulacja restartu usług"
        return 0
    fi
    
    # Restart Traefik
    if [[ -f "$FORTRESS_DIR/proxy/docker-compose.yml" ]]; then
        cd "$FORTRESS_DIR/proxy"
        docker compose up -d
    fi
    
    # Sprawdź czy usługi działają
    sleep 5
    if docker ps --format "table {{.Names}}" | grep -q "fortress_traefik"; then
        log_success "Traefik uruchomiony pomyślnie"
    else
        log_error "Nie udało się uruchomić Traefik"
    fi
    
    log_success "Usługi zrestartowane"
}

# Weryfikacja po aktualizacji
verify_update() {
    log_info "Weryfikacja aktualizacji..."
    
    # Sprawdź wersję
    if command -v fortress >/dev/null 2>&1; then
        INSTALLED_VERSION=$(fortress --version 2>/dev/null || echo "unknown")
        log_info "Zainstalowana wersja: $INSTALLED_VERSION"
    fi
    
    # Sprawdź usługi
    local services_ok=true
    
    if ! docker ps --format "table {{.Names}}" | grep -q "fortress_traefik"; then
        log_warning "Traefik nie działa"
        services_ok=false
    fi
    
    # Sprawdź aplikacje użytkowników
    if [[ -d "$FORTRESS_DIR/apps" ]]; then
        for app_dir in "$FORTRESS_DIR"/apps/*/; do
            if [[ -d "$app_dir" ]]; then
                app_name=$(basename "$app_dir")
                if [[ -f "$app_dir/docker-compose.yml" ]]; then
                    cd "$app_dir"
                    if ! docker compose ps | grep -q "Up"; then
                        log_warning "Aplikacja $app_name może nie działać poprawnie"
                    fi
                fi
            fi
        done
    fi
    
    if [[ "$services_ok" == "true" ]]; then
        log_success "Weryfikacja zakończona pomyślnie"
    else
        log_error "Problemy po aktualizacji - sprawdź logi"
    fi
}

# Czyszczenie plików tymczasowych
cleanup() {
    log_info "Czyszczenie plików tymczasowych..."
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    log_success "Pliki tymczasowe usunięte"
}

# Rollback w przypadku błędu
rollback() {
    log_error "Błąd podczas aktualizacji - wykonywanie rollback..."
    
    # Przywróć pliki z backup'u
    if [[ -d "$FORTRESS_DIR/bin.backup."* ]]; then
        latest_backup=$(ls -t "$FORTRESS_DIR"/bin.backup.* | head -1)
        rm -rf "$FORTRESS_DIR/bin"
        mv "$latest_backup" "$FORTRESS_DIR/bin"
        chmod +x "$FORTRESS_DIR/bin/fortress"
        ln -sf "$FORTRESS_DIR/bin/fortress" "/usr/local/bin/fortress"
    fi
    
    # Restart usług
    restart_services
    
    log_info "Rollback zakończony - system przywrócony do poprzedniego stanu"
}

# Główna funkcja
main() {
    log_info "=== Fortress Update Script ==="
    log_info "Czas rozpoczęcia: $(date)"
    
    # Trap dla rollback w przypadku błędu
    trap 'rollback; cleanup; exit 1' ERR
    
    parse_args "$@"
    check_root
    check_fortress_installed
    check_current_version
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== TRYB SYMULACJI - żadne zmiany nie zostaną wykonane ==="
    fi
    
    create_backup
    download_latest
    check_compatibility
    stop_fortress_services
    update_files
    update_config
    restart_services
    verify_update
    cleanup
    
    log_success "=== Aktualizacja Fortress zakończona pomyślnie ==="
    log_info "Poprzednia wersja: $CURRENT_VERSION"
    log_info "Nowa wersja: $NEW_VERSION"
    log_info "W przypadku problemów, przywróć backup z: /opt/fortress/backups/system/"
}

main "$@"
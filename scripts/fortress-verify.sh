#!/bin/bash
#
# Fortress Verification Script
# Weryfikuje poprawność działania systemu Fortress po aktualizacji
#
set -e

# Konfiguracja
FORTRESS_DIR="/opt/fortress"
REPORT_FILE="/tmp/fortress-verification-$(date +%Y%m%d_%H%M%S).txt"

# Kolory dla logowania
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$REPORT_FILE"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$REPORT_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$REPORT_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$REPORT_FILE"; }

# Inicjalizacja raportu
init_report() {
    echo "=== Fortress Verification Report ===" > "$REPORT_FILE"
    echo "Czas wykonania: $(date)" >> "$REPORT_FILE"
    echo "Hostname: $(hostname)" >> "$REPORT_FILE"
    echo "=====================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Sprawdzenie wersji Fortress
check_fortress_version() {
    log_info "Sprawdzanie wersji Fortress..."
    
    if command -v fortress >/dev/null 2>&1; then
        local version=$(fortress --version 2>/dev/null || echo "Nieznana")
        log_success "Fortress jest dostępny, wersja: $version"
        return 0
    else
        log_error "Komenda 'fortress' nie jest dostępna"
        return 1
    fi
}

# Sprawdzenie struktury katalogów
check_directory_structure() {
    log_info "Sprawdzanie struktury katalogów..."
    
    local required_dirs=(
        "$FORTRESS_DIR"
        "$FORTRESS_DIR/bin"
        "$FORTRESS_DIR/commands"
        "$FORTRESS_DIR/config"
        "$FORTRESS_DIR/apps"
        "$FORTRESS_DIR/proxy"
        "$FORTRESS_DIR/backups"
    )
    
    local missing_dirs=()
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        log_success "Struktura katalogów - OK"
        return 0
    else
        log_error "Brakujące katalogi: ${missing_dirs[*]}"
        return 1
    fi
}

# Sprawdzenie plików wykonywalnych
check_executables() {
    log_info "Sprawdzanie plików wykonywalnych..."
    
    local required_files=(
        "$FORTRESS_DIR/bin/fortress"
        "/usr/local/bin/fortress"
    )
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]] || [[ ! -x "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        log_success "Pliki wykonywalne - OK"
        return 0
    else
        log_error "Brakujące lub niepoprawne pliki: ${missing_files[*]}"
        return 1
    fi
}

# Sprawdzenie kontenerów Docker
check_docker_containers() {
    log_info "Sprawdzanie kontenerów Docker..."
    
    local containers_status=0
    
    # Sprawdź Traefik
    if docker ps --format "table {{.Names}}" | grep -q "fortress_traefik"; then
        local traefik_status=$(docker ps --filter "name=fortress_traefik" --format "{{.Status}}")
        log_success "Traefik: $traefik_status"
    else
        log_error "Traefik nie działa"
        containers_status=1
    fi
    
    # Sprawdź PostgreSQL
    if docker ps --format "table {{.Names}}" | grep -q "fortress_postgres"; then
        local postgres_status=$(docker ps --filter "name=fortress_postgres" --format "{{.Status}}")
        log_success "PostgreSQL: $postgres_status"
    else
        log_warning "PostgreSQL nie działa (może być wyłączony)"
    fi
    
    # Sprawdź Redis
    if docker ps --format "table {{.Names}}" | grep -q "fortress_redis"; then
        local redis_status=$(docker ps --filter "name=fortress_redis" --format "{{.Status}}")
        log_success "Redis: $redis_status"
    else
        log_warning "Redis nie działa (może być wyłączony)"
    fi
    
    return $containers_status
}

# Sprawdzenie aplikacji użytkowników
check_user_apps() {
    log_info "Sprawdzanie aplikacji użytkowników..."
    
    local apps_count=0
    local running_apps=0
    local failed_apps=()
    
    if [[ -d "$FORTRESS_DIR/apps" ]]; then
        for app_dir in "$FORTRESS_DIR"/apps/*/; do
            if [[ -d "$app_dir" ]]; then
                local app_name=$(basename "$app_dir")
                apps_count=$((apps_count + 1))
                
                if [[ -f "$app_dir/docker-compose.yml" ]]; then
                    cd "$app_dir"
                    local app_status=$(docker compose ps --format "table {{.Service}}\t{{.State}}" 2>/dev/null || echo "ERROR")
                    
                    if echo "$app_status" | grep -q "running"; then
                        running_apps=$((running_apps + 1))
                        log_success "Aplikacja $app_name: działa"
                    else
                        failed_apps+=("$app_name")
                        log_warning "Aplikacja $app_name: nie działa lub problem"
                    fi
                else
                    log_warning "Aplikacja $app_name: brak docker-compose.yml"
                fi
            fi
        done
    fi
    
    log_info "Znalezione aplikacje: $apps_count"
    log_info "Działające aplikacje: $running_apps"
    
    if [[ ${#failed_apps[@]} -gt 0 ]]; then
        log_warning "Problematyczne aplikacje: ${failed_apps[*]}"
        return 1
    else
        log_success "Wszystkie aplikacje działają poprawnie"
        return 0
    fi
}

# Sprawdzenie konfiguracji Traefik
check_traefik_config() {
    log_info "Sprawdzanie konfiguracji Traefik..."
    
    if [[ -f "$FORTRESS_DIR/proxy/traefik.yml" ]]; then
        log_success "Plik konfiguracyjny Traefik istnieje"
        
        # Sprawdź czy Traefik odpowiada
        if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
            log_success "Traefik API odpowiada"
        else
            log_warning "Traefik API nie odpowiada"
        fi
        
        return 0
    else
        log_error "Brak pliku konfiguracyjnego Traefik"
        return 1
    fi
}

# Sprawdzenie certyfikatów SSL
check_ssl_certificates() {
    log_info "Sprawdzanie certyfikatów SSL..."
    
    local certs_found=0
    
    if [[ -f "$FORTRESS_DIR/proxy/acme.json" ]]; then
        local cert_count=$(jq -r '.letsencrypt.Certificates | length' "$FORTRESS_DIR/proxy/acme.json" 2>/dev/null || echo "0")
        if [[ "$cert_count" -gt 0 ]]; then
            log_success "Znaleziono $cert_count certyfikatów SSL"
            certs_found=1
        fi
    fi
    
    if [[ -d "$FORTRESS_DIR/proxy/certs" ]] && [[ -n "$(ls -A "$FORTRESS_DIR/proxy/certs" 2>/dev/null)" ]]; then
        local manual_certs=$(ls -1 "$FORTRESS_DIR/proxy/certs" | wc -l)
        log_success "Znaleziono $manual_certs ręcznych certyfikatów"
        certs_found=1
    fi
    
    if [[ $certs_found -eq 0 ]]; then
        log_warning "Nie znaleziono certyfikatów SSL"
        return 1
    else
        return 0
    fi
}

# Sprawdzenie połączenia z bazą danych
check_database_connection() {
    log_info "Sprawdzanie połączenia z bazą danych..."
    
    if docker ps --format "table {{.Names}}" | grep -q "fortress_postgres"; then
        if docker exec fortress_postgres pg_isready -U postgres >/dev/null 2>&1; then
            log_success "PostgreSQL: połączenie OK"
            return 0
        else
            log_error "PostgreSQL: nie można nawiązać połączenia"
            return 1
        fi
    else
        log_warning "PostgreSQL nie działa - pomijanie testu"
        return 0
    fi
}

# Sprawdzenie zasobów systemowych
check_system_resources() {
    log_info "Sprawdzanie zasobów systemowych..."
    
    # Sprawdź miejsce na dysku
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -lt 90 ]]; then
        log_success "Użycie dysku: ${disk_usage}%"
    else
        log_warning "Wysokie użycie dysku: ${disk_usage}%"
    fi
    
    # Sprawdź pamięć
    local memory_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2 }')
    if [[ $memory_usage -lt 90 ]]; then
        log_success "Użycie pamięci: ${memory_usage}%"
    else
        log_warning "Wysokie użycie pamięci: ${memory_usage}%"
    fi
    
    # Sprawdź ładowanie systemu
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    log_info "Średnie obciążenie: $load_avg"
    
    return 0
}

# Sprawdzenie sieci
check_network() {
    log_info "Sprawdzanie sieci Docker..."
    
    local networks=("fortress_default" "fortress_proxy")
    local network_status=0
    
    for network in "${networks[@]}"; do
        if docker network ls --format "{{.Name}}" | grep -q "^${network}$"; then
            log_success "Sieć Docker: $network - OK"
        else
            log_warning "Sieć Docker: $network - brak"
            network_status=1
        fi
    done
    
    return $network_status
}

# Test podstawowej funkcjonalności
test_basic_functionality() {
    log_info "Test podstawowej funkcjonalności..."
    
    # Test komendy fortress
    if fortress app list >/dev/null 2>&1; then
        log_success "Komenda 'fortress app list' działa"
    else
        log_error "Komenda 'fortress app list' nie działa"
        return 1
    fi
    
    # Test dostępu do API Traefik
    if curl -s http://localhost:8080/api/rawdata >/dev/null 2>&1; then
        log_success "API Traefik dostępne"
    else
        log_warning "API Traefik niedostępne"
    fi
    
    return 0
}

# Generowanie podsumowania
generate_summary() {
    log_info "Generowanie podsumowania..."
    
    echo "" >> "$REPORT_FILE"
    echo "=== PODSUMOWANIE WERYFIKACJI ===" >> "$REPORT_FILE"
    
    local total_checks=0
    local passed_checks=0
    local failed_checks=0
    local warning_checks=0
    
    # Policz wyniki z pliku raportu
    total_checks=$(grep -c "\[.*\]" "$REPORT_FILE" || echo "0")
    passed_checks=$(grep -c "\[SUCCESS\]" "$REPORT_FILE" || echo "0")
    failed_checks=$(grep -c "\[ERROR\]" "$REPORT_FILE" || echo "0")
    warning_checks=$(grep -c "\[WARNING\]" "$REPORT_FILE" || echo "0")
    
    echo "Całkowita liczba sprawdzeń: $total_checks" >> "$REPORT_FILE"
    echo "Zakończone sukcesem: $passed_checks" >> "$REPORT_FILE"
    echo "Ostrzeżenia: $warning_checks" >> "$REPORT_FILE"
    echo "Błędy: $failed_checks" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [[ $failed_checks -eq 0 ]]; then
        echo "WYNIK: ✅ SYSTEM DZIAŁA POPRAWNIE" >> "$REPORT_FILE"
        log_success "Weryfikacja zakończona pomyślnie!"
    else
        echo "WYNIK: ❌ WYKRYTO PROBLEMY" >> "$REPORT_FILE"
        log_error "Weryfikacja wykryła problemy - sprawdź raport"
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "Pełny raport: $REPORT_FILE" >> "$REPORT_FILE"
    
    return $failed_checks
}

# Główna funkcja
main() {
    log_info "=== Fortress Verification Script ==="
    log_info "Rozpoczęcie weryfikacji: $(date)"
    
    init_report
    
    local exit_code=0
    
    # Wykonaj wszystkie sprawdzenia
    check_fortress_version || exit_code=$((exit_code + 1))
    check_directory_structure || exit_code=$((exit_code + 1))
    check_executables || exit_code=$((exit_code + 1))
    check_docker_containers || exit_code=$((exit_code + 1))
    check_user_apps || exit_code=$((exit_code + 1))
    check_traefik_config || exit_code=$((exit_code + 1))
    check_ssl_certificates || exit_code=$((exit_code + 1))
    check_database_connection || exit_code=$((exit_code + 1))
    check_system_resources || exit_code=$((exit_code + 1))
    check_network || exit_code=$((exit_code + 1))
    test_basic_functionality || exit_code=$((exit_code + 1))
    
    generate_summary
    
    log_info "Weryfikacja zakończona. Raport: $REPORT_FILE"
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "=== WSZYSTKIE SPRAWDZENIA ZAKOŃCZONE POMYŚLNIE ==="
    else
        log_error "=== WYKRYTO $exit_code PROBLEMÓW ==="
    fi
    
    return $exit_code
}

main "$@"
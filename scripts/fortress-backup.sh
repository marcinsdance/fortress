#!/bin/bash
#
# Fortress Backup Script
# Tworzy kompletny backup systemu Fortress zachowując wszystkie konfiguracje i dane
#
set -e

# Konfiguracja
BACKUP_DIR="/opt/fortress/backups/system"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="fortress_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Kolory dla logowania
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Sprawdzenie uprawnień root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ten skrypt musi być uruchomiony jako root"
        exit 1
    fi
}

# Utworzenie katalogów backup
create_backup_dirs() {
    log_info "Tworzenie katalogów backup..."
    mkdir -p "${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}/config"
    mkdir -p "${BACKUP_PATH}/apps"
    mkdir -p "${BACKUP_PATH}/proxy"
    mkdir -p "${BACKUP_PATH}/services"
    mkdir -p "${BACKUP_PATH}/databases"
    mkdir -p "${BACKUP_PATH}/ssl"
}

# Backup konfiguracji głównej
backup_main_config() {
    log_info "Backup konfiguracji głównej Fortress..."
    if [[ -d "/opt/fortress/config" ]]; then
        cp -r /opt/fortress/config/* "${BACKUP_PATH}/config/"
        log_success "Konfiguracja główna - OK"
    else
        log_warning "Katalog /opt/fortress/config nie istnieje"
    fi
}

# Backup aplikacji
backup_apps() {
    log_info "Backup konfiguracji aplikacji..."
    if [[ -d "/opt/fortress/apps" ]]; then
        cp -r /opt/fortress/apps/* "${BACKUP_PATH}/apps/" 2>/dev/null || true
        # Zatrzymanie kontenerów aplikacji przed backup'em wolumenów
        for app_dir in /opt/fortress/apps/*/; do
            if [[ -d "$app_dir" ]]; then
                app_name=$(basename "$app_dir")
                log_info "Backup aplikacji: $app_name"
                
                # Backup docker-compose.yml i .env
                [[ -f "$app_dir/docker-compose.yml" ]] && cp "$app_dir/docker-compose.yml" "${BACKUP_PATH}/apps/$app_name/"
                [[ -f "$app_dir/.env" ]] && cp "$app_dir/.env" "${BACKUP_PATH}/apps/$app_name/"
                
                # Backup wolumenów danych
                if [[ -d "$app_dir/data" ]]; then
                    cp -r "$app_dir/data" "${BACKUP_PATH}/apps/$app_name/"
                fi
            fi
        done
        log_success "Aplikacje - OK"
    else
        log_warning "Katalog /opt/fortress/apps nie istnieje"
    fi
}

# Backup konfiguracji proxy (Traefik)
backup_proxy() {
    log_info "Backup konfiguracji Traefik..."
    if [[ -d "/opt/fortress/proxy" ]]; then
        cp -r /opt/fortress/proxy/* "${BACKUP_PATH}/proxy/"
        log_success "Konfiguracja Traefik - OK"
    else
        log_warning "Katalog /opt/fortress/proxy nie istnieje"
    fi
}

# Backup certyfikatów SSL
backup_ssl() {
    log_info "Backup certyfikatów SSL..."
    
    # Let's Encrypt certyfikaty
    if [[ -d "/opt/fortress/proxy/certs" ]]; then
        cp -r /opt/fortress/proxy/certs/* "${BACKUP_PATH}/ssl/" 2>/dev/null || true
    fi
    
    # Traefik ACME storage
    if [[ -f "/opt/fortress/proxy/acme.json" ]]; then
        cp /opt/fortress/proxy/acme.json "${BACKUP_PATH}/ssl/"
    fi
    
    log_success "Certyfikaty SSL - OK"
}

# Backup baz danych
backup_databases() {
    log_info "Backup baz danych..."
    
    # PostgreSQL
    if docker ps --format "table {{.Names}}" | grep -q "fortress_postgres"; then
        log_info "Export bazy PostgreSQL..."
        docker exec fortress_postgres pg_dumpall -U postgres > "${BACKUP_PATH}/databases/postgres_all.sql"
        log_success "PostgreSQL backup - OK"
    else
        log_warning "Kontener PostgreSQL nie działa"
    fi
    
    # Redis
    if docker ps --format "table {{.Names}}" | grep -q "fortress_redis"; then
        log_info "Export bazy Redis..."
        docker exec fortress_redis redis-cli BGSAVE
        sleep 2
        docker cp fortress_redis:/data/dump.rdb "${BACKUP_PATH}/databases/redis_dump.rdb"
        log_success "Redis backup - OK"
    else
        log_warning "Kontener Redis nie działa"
    fi
}

# Backup skryptów i binariów
backup_scripts() {
    log_info "Backup skryptów Fortress..."
    if [[ -d "/opt/fortress/bin" ]]; then
        mkdir -p "${BACKUP_PATH}/bin"
        cp -r /opt/fortress/bin/* "${BACKUP_PATH}/bin/"
    fi
    
    if [[ -d "/opt/fortress/commands" ]]; then
        mkdir -p "${BACKUP_PATH}/commands"
        cp -r /opt/fortress/commands/* "${BACKUP_PATH}/commands/"
    fi
    
    if [[ -d "/opt/fortress/utils" ]]; then
        mkdir -p "${BACKUP_PATH}/utils"
        cp -r /opt/fortress/utils/* "${BACKUP_PATH}/utils/"
    fi
    
    log_success "Skrypty - OK"
}

# Utworzenie archiwum
create_archive() {
    log_info "Tworzenie archiwum backup..."
    cd "${BACKUP_DIR}"
    tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"
    rm -rf "${BACKUP_NAME}"
    log_success "Archiwum utworzone: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
}

# Czyszczenie starych backup'ów (zachowaj tylko 5 najnowszych)
cleanup_old_backups() {
    log_info "Czyszczenie starych backup'ów..."
    cd "${BACKUP_DIR}"
    ls -t fortress_backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f
    log_success "Stare backup'y usunięte"
}

# Główna funkcja
main() {
    log_info "=== Fortress Backup Script ==="
    log_info "Czas rozpoczęcia: $(date)"
    
    check_root
    create_backup_dirs
    backup_main_config
    backup_apps
    backup_proxy
    backup_ssl
    backup_databases
    backup_scripts
    create_archive
    cleanup_old_backups
    
    log_success "=== Backup zakończony pomyślnie ==="
    log_info "Lokalizacja: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    log_info "Rozmiar: $(du -h ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz | cut -f1)"
}

main "$@"
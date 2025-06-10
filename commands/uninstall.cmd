#!/usr/bin/env bash
[[ ! ${FORTRESS_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

function uninstallFortress() {
    local CONFIRMATION_STRING="$1"

    if [[ "$EUID" -ne 0 ]]; then
        fatal "This command must be run as root or with sudo."
    fi

    if [[ "${CONFIRMATION_STRING}" != "UNINSTALL" ]]; then
        fatal "To uninstall Fortress, you must confirm by typing 'UNINSTALL'. Usage: fortress uninstall UNINSTALL"
    fi

    warning "==================================================================="
    warning "                  FORTRESS UNINSTALLATION IN PROGRESS             "
    warning "==================================================================="
    warning "This will PERMANENTLY remove ALL Fortress applications, services,"
    warning "configurations, and data. This action CANNOT be undone."
    warning "Ensure you have backed up any critical data before proceeding."
    echo ""
    read -p "Are you absolutely sure you want to proceed? Type 'UNINSTALL' to confirm: " -r USER_CONFIRMATION
    echo ""

    if [[ "${USER_CONFIRMATION}" != "UNINSTALL" ]]; then
        info "Fortress uninstallation cancelled."
        exit 0
    fi

    info "Starting Fortress uninstallation process..."

    # 1. Stop and remove all applications managed by Fortress
    info "Stopping and removing all Fortress applications..."
    if [[ -d "${FORTRESS_APPS_DIR}" ]]; then
        for app_dir in "${FORTRESS_APPS_DIR}"/*; do
            if [[ -d "$app_dir" ]]; then
                local app_name=$(basename "$app_dir")
                info "  - Removing application: ${app_name}"
                (cd "$app_dir" && ${DOCKER_COMPOSE_COMMAND} -p "${app_name}" down -v) || warning "Failed to stop/remove app '${app_name}', continuing..."
                rm -rf "$app_dir" || warning "Failed to remove app directory '${app_dir}', continuing..."
            fi
        done
        rm -rf "${FORTRESS_APPS_DIR}" || warning "Failed to remove main apps directory."
    else
        info "Fortress applications directory '${FORTRESS_APPS_DIR}' not found, skipping app removal."
    fi

    # Ensure all containers are stopped and removed, even if not explicitly from apps dir
    info "Ensuring all Fortress-related Docker containers are stopped and removed..."
    sudo docker ps -a --format "{{.Names}}" | grep -E "fortress_|fortress_traefik|fortress_postgres|fortress_redis" | xargs -r sudo docker stop || true
    sudo docker ps -a --format "{{.Names}}" | grep -E "fortress_|fortress_traefik|fortress_postgres|fortress_redis" | xargs -r sudo docker rm -v || true

    # 2. Stop and remove core Fortress services
    info "Stopping and removing core Fortress services (proxy, postgres, redis)..."
    local services_dirs=("/opt/fortress/proxy" "/opt/fortress/services/postgres" "/opt/fortress/services/redis")
    for svc_dir in "${services_dirs[@]}"; do
        if [[ -d "$svc_dir" ]]; then
            info "  - Stopping service in: ${svc_dir}"
            (cd "$svc_dir" && ${DOCKER_COMPOSE_COMMAND} down -v) || warning "Failed to stop service in '${svc_dir}', continuing..."
        fi
    done

    # 3. Remove Fortress Docker network
    info "Removing Docker network 'fortress'..."
    ${DOCKER_COMPOSE_COMMAND} network rm fortress || warning "Docker network 'fortress' not found or could not be removed."

    # 4. Remove Fortress systemd service
    info "Disabling and removing 'fortress-core.service'..."
    systemctl disable fortress-core.service || true
    systemctl stop fortress-core.service || true
    rm -f /etc/systemd/system/fortress-core.service || true
    systemctl daemon-reload || true

    # 5. Remove symlink to fortress command
    info "Removing 'fortress' command symlink from /usr/local/bin/fortress..."
    rm -f /usr/local/bin/fortress || true

    # 6. Remove Fortress directory
    info "Removing main Fortress installation directory: ${FORTRESS_ROOT}..."
    rm -rf "${FORTRESS_ROOT}" || fatal "Failed to remove main Fortress directory: ${FORTRESS_ROOT}. Please check permissions."

    # 7. Remove system configurations
    info "Removing system-wide Fortress configurations (Fail2ban, Logrotate)..."
    rm -f /etc/fail2ban/jail.d/fortress-defaults.conf || true
    rm -f /etc/fail2ban/filter.d/docker-traefik.conf || true
    systemctl restart fail2ban || warning "Failed to restart Fail2ban after removing config."
    rm -f /etc/logrotate.d/fortress || true
    # Usunięto rm -f /etc/sudoers.d/90-github-deployer, ponieważ nie jest to standardowa część Fortress

    # 8. Remove fortress system user (optional)
    info "Removing 'fortress' system user (if exists)..."
    userdel -r fortress || true # -r usunie również katalog domowy

    # 9. Clean up temporary installer files
    info "Cleaning up temporary installer files..."
    rm -rf /tmp/fortress-install-* || true
    rm -f /tmp/fortress_install.sh || true

    success "Fortress has been completely uninstalled from your server."
    echo ""
    warning "It is highly recommended to REBOOT your server now to ensure all changes are applied."
    echo ""
}

# Main execution for the uninstall command
if [[ ${#FORTRESS_PARAMS[@]} -eq 0 ]]; then
    fatal "To uninstall Fortress, you must confirm by typing 'UNINSTALL'. Usage: fortress uninstall UNINSTALL"
else
    uninstallFortress "${FORTRESS_PARAMS[0]}"
fi


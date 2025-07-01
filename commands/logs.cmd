#!/usr/bin/env bash

[[ ! ${FORTRESS_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if [[ ${#FORTRESS_PARAMS[@]} -eq 0 ]]; then
    fatal "logs: No target specified. Use 'fortress logs --help' for options."
fi

TARGET="${FORTRESS_PARAMS[0]}"
LOG_OPTIONS=("${FORTRESS_PARAMS[@]:1}")

# Default log options if none provided
if [[ ${#LOG_OPTIONS[@]} -eq 0 ]]; then
    LOG_OPTIONS=("--tail" "100")
fi

function showAppLogs() {
    local APP_NAME="$1"
    shift
    local options=("$@")
    
    local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
    [[ ! -d "${APP_DIR}" || ! -f "${APP_DIR}/fortress.yml" ]] && fatal "logs: App '${APP_NAME}' not found or not managed by Fortress."
    
    info "Showing logs for app: ${APP_NAME}"
    (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" logs "${options[@]}")
}

function showServiceLogs() {
    local SERVICE_NAME="$1"
    shift
    local options=("$@")
    
    local service_dir=""
    if [[ "$SERVICE_NAME" == "proxy" ]]; then
        service_dir="${FORTRESS_PROXY_DIR}"
    elif [[ -d "${FORTRESS_SERVICES_DIR}/${SERVICE_NAME}" ]]; then
        service_dir="${FORTRESS_SERVICES_DIR}/${SERVICE_NAME}"
    else
        fatal "logs: Unknown service '${SERVICE_NAME}'. Available services: proxy, postgres, redis"
    fi
    
    info "Showing logs for service: ${SERVICE_NAME}"
    (cd "${service_dir}" && ${DOCKER_COMPOSE_COMMAND} -p "fortress_${SERVICE_NAME}" logs "${options[@]}")
}

function showAllLogs() {
    local options=("$@")
    
    info "Showing logs for all Fortress components..."
    echo ""
    
    # Show service logs first
    echo "=== SERVICES ==="
    for service in proxy postgres redis; do
        local service_dir=""
        if [[ "$service" == "proxy" ]]; then
            service_dir="${FORTRESS_PROXY_DIR}"
        elif [[ -d "${FORTRESS_SERVICES_DIR}/${service}" ]]; then
            service_dir="${FORTRESS_SERVICES_DIR}/${service}"
        else
            continue
        fi
        
        if [[ -f "${service_dir}/docker-compose.yml" ]]; then
            echo ""
            echo "--- ${service} ---"
            (cd "${service_dir}" && ${DOCKER_COMPOSE_COMMAND} -p "fortress_${service}" logs "${options[@]}" 2>/dev/null || echo "No logs or service not running")
        fi
    done
    
    # Show app logs
    echo ""
    echo "=== APPLICATIONS ==="
    if [[ -d "${FORTRESS_APPS_DIR}" ]] && [[ -n "$(ls -A ${FORTRESS_APPS_DIR} 2>/dev/null)" ]]; then
        for app_dir in "${FORTRESS_APPS_DIR}"/*; do
            if [[ -d "${app_dir}" ]] && [[ -f "${app_dir}/fortress.yml" ]]; then
                local app_name=$(basename "${app_dir}")
                echo ""
                echo "--- ${app_name} ---"
                (cd "${app_dir}" && ${DOCKER_COMPOSE_COMMAND} -p "${app_name}" logs "${options[@]}" 2>/dev/null || echo "No logs or app not running")
            fi
        done
    else
        echo "No applications deployed."
    fi
}

case "${TARGET}" in
    --help|-h)
        cat << 'EOF'
Usage: fortress logs [TARGET] [OPTIONS]

Show logs for Fortress components.

TARGETS:
  <app-name>        Show logs for a specific application
  proxy             Show logs for Traefik proxy service
  postgres          Show logs for PostgreSQL service  
  redis             Show logs for Redis service
  all               Show logs for all services and applications

OPTIONS:
  --follow, -f      Follow log output (live tail)
  --tail N          Show last N lines (default: 100)
  --since TIME      Show logs since timestamp (e.g. 2h, 1m30s)
  --timestamps, -t  Show timestamps
  --no-color        Disable colored output

EXAMPLES:
  fortress logs myapp                    # Show last 100 lines for myapp
  fortress logs myapp --follow           # Follow myapp logs in real-time  
  fortress logs proxy --tail 50          # Show last 50 lines for proxy
  fortress logs postgres --since 1h      # Show postgres logs from last hour
  fortress logs all --tail 20            # Show last 20 lines for all components

EOF
        ;;
    all)
        showAllLogs "${LOG_OPTIONS[@]}"
        ;;
    proxy|postgres|redis)
        showServiceLogs "${TARGET}" "${LOG_OPTIONS[@]}"
        ;;
    *)
        # Check if it's an app name
        if [[ -d "${FORTRESS_APPS_DIR}/${TARGET}" ]] && [[ -f "${FORTRESS_APPS_DIR}/${TARGET}/fortress.yml" ]]; then
            showAppLogs "${TARGET}" "${LOG_OPTIONS[@]}"
        else
            # Try to be helpful - list available targets
            echo "Unknown target '${TARGET}'. Available targets:"
            echo ""
            echo "Services: proxy, postgres, redis, all"
            if [[ -d "${FORTRESS_APPS_DIR}" ]] && [[ -n "$(ls -A ${FORTRESS_APPS_DIR} 2>/dev/null)" ]]; then
                echo "Applications:"
                for app_dir in "${FORTRESS_APPS_DIR}"/*; do
                    if [[ -d "${app_dir}" ]] && [[ -f "${app_dir}/fortress.yml" ]]; then
                        echo "  $(basename "${app_dir}")"
                    fi
                done
            else
                echo "Applications: (none deployed)"
            fi
            echo ""
            echo "Use 'fortress logs --help' for more information."
            exit 1
        fi
        ;;
esac
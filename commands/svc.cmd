#!/usr/bin/env bash

[[ ! ${FORTRESS_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if [[ ${#FORTRESS_PARAMS[@]} -eq 0 ]]; then
    fatal "svc: No subcommand specified. Use 'fortress svc --help' for options."
fi

SVC_SUBCOMMAND="${FORTRESS_PARAMS[0]}"
SUBCOMMAND_ARGS=("${FORTRESS_PARAMS[@]:1}")

if [[ -f "${FORTRESS_CONFIG_DIR}/fortress.env" ]]; then
    set -a
    source "${FORTRESS_CONFIG_DIR}/fortress.env"
    set +a
else
    warning "Fortress global environment file not found: ${FORTRESS_CONFIG_DIR}/fortress.env"
    warning "Core services like Traefik and PostgreSQL might not start/function correctly."
fi

execute_compose_for_services() {
    local compose_main_action="$1"
    shift

    local compose_flags_and_services_list=("$@")
    local compose_flags_for_dc=()
    local services_to_manage_list=()

    for param_item in "${compose_flags_and_services_list[@]}"; do
        if [[ "$param_item" == -* ]]; then
            compose_flags_for_dc+=("$param_item")
        else
            services_to_manage_list+=("$param_item")
        fi
    done
    
    if [[ ${#services_to_manage_list[@]} -eq 0 ]]; then
        fatal "svc ${compose_main_action}: No services specified to manage. Please specify 'proxy', 'postgres', 'redis', etc."
    fi

    for service_name_item in "${services_to_manage_list[@]}"; do
        local service_item_dir=""
        local compose_file_path=""

        if [[ "$service_name_item" == "proxy" ]]; then
            service_item_dir="${FORTRESS_PROXY_DIR}"
        elif [[ -d "${FORTRESS_SERVICES_DIR}/${service_name_item}" ]]; then
            service_item_dir="${FORTRESS_SERVICES_DIR}/${service_name_item}"
        else
            error "svc ${compose_main_action}: Unknown service '${service_name_item}'. Skipping."
            continue
        fi

        compose_file_path="${service_item_dir}/docker-compose.yml"
        if [[ ! -f "${compose_file_path}" ]]; then
            error "svc ${compose_main_action}: Docker Compose file not found for service '${service_name_item}' at ${compose_file_path}. Skipping."
            continue
        fi
        
        info "Service '${service_name_item}': Running ${DOCKER_COMPOSE_COMMAND} -p fortress_${service_name_item} ${compose_main_action} ${compose_flags_for_dc[*]}"
        (
            cd "${service_item_dir}" && \
            ${DOCKER_COMPOSE_COMMAND} -p "fortress_${service_name_item}" "${compose_main_action}" "${compose_flags_for_dc[@]}"
        )
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            error "Failed to execute '${compose_main_action}' for service '${service_name_item}'. Exit code: $exit_code"
        fi
    done
}

case "${SVC_SUBCOMMAND}" in
    up)
        execute_compose_for_services "up" "${SUBCOMMAND_ARGS[@]}"
        ;;
    down)
        execute_compose_for_services "down" "${SUBCOMMAND_ARGS[@]}"
        ;;
    start|stop|restart)
        execute_compose_for_services "${SVC_SUBCOMMAND}" "${SUBCOMMAND_ARGS[@]}"
        ;;
    logs)
        if [[ ${#SUBCOMMAND_ARGS[@]} -eq 0 ]]; then
            fatal "svc logs: Service name required."
        fi
        service_name_logs="${SUBCOMMAND_ARGS[0]}"
        log_options=("${SUBCOMMAND_ARGS[@]:1}")

        service_dir_logs=""
        if [[ "$service_name_logs" == "proxy" ]]; then
            service_dir_logs="${FORTRESS_PROXY_DIR}"
        elif [[ -d "${FORTRESS_SERVICES_DIR}/${service_name_logs}" ]]; then
            service_dir_logs="${FORTRESS_SERVICES_DIR}/${service_name_logs}"
        else
            fatal "svc logs: Unknown service '${service_name_logs}'."
        fi
        info "Fetching logs for service '${service_name_logs}'..."
        (cd "${service_dir_logs}" && ${DOCKER_COMPOSE_COMMAND} -p "fortress_${service_name_logs}" logs "${log_options[@]}")
        ;;
    status|ps)
        services_for_status=("${SUBCOMMAND_ARGS[@]}")
        if [[ ${#services_for_status[@]} -eq 0 ]]; then
            services_for_status=("proxy" "postgres" "redis")
        fi
        
        for service_name_status in "${services_for_status[@]}"; do
            service_dir_status=""
            if [[ "$service_name_status" == "proxy" ]]; then
                service_dir_status="${FORTRESS_PROXY_DIR}"
            elif [[ -d "${FORTRESS_SERVICES_DIR}/${service_name_status}" ]]; then
                service_dir_status="${FORTRESS_SERVICES_DIR}/${service_name_status}"
            else
                warning "svc status: Unknown service '${service_name_status}'. Skipping."
                continue
            fi
            info "Status for service '${service_name_status}':"
            (cd "${service_dir_status}" && ${DOCKER_COMPOSE_COMMAND} -p "fortress_${service_name_status}" ps)
            echo ""
        done
        ;;
    *)
        fatal "svc: Unknown subcommand '${SVC_SUBCOMMAND}'. Use 'fortress svc --help' for options."
        ;;
esac


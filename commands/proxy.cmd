#!/usr/bin/env bash
[[ ! ${FORTRESS_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if [[ ${#FORTRESS_PARAMS[@]} -eq 0 ]]; then
    fatal "proxy: No subcommand specified. Use 'fortress proxy --help' for options."
fi

PROXY_SUBCOMMAND="${FORTRESS_PARAMS[0]}"
PROXY_SUBCOMMAND_ARGS=("${FORTRESS_PARAMS[@]:1}")

if [[ -f "${FORTRESS_CONFIG_DIR}/fortress.env" ]]; then
    set -a
    source "${FORTRESS_CONFIG_DIR}/fortress.env"
    set +a
else
    warning "Fortress global environment file not found: ${FORTRESS_CONFIG_DIR}/fortress.env"
    warning "Proxy service (Traefik) might not function correctly if it depends on these variables."
fi

if [[ ! -d "${FORTRESS_PROXY_DIR}" || ! -f "${FORTRESS_PROXY_DIR}/docker-compose.yml" ]]; then
    fatal "Proxy service directory or docker-compose.yml not found at ${FORTRESS_PROXY_DIR}"
fi

case "${PROXY_SUBCOMMAND}" in
    start|stop|restart|up|down|ps|logs)
        info "Proxy service: Executing '${DOCKER_COMPOSE_COMMAND} ${PROXY_SUBCOMMAND} ${PROXY_SUBCOMMAND_ARGS[*]}' in ${FORTRESS_PROXY_DIR}"
        (
            cd "${FORTRESS_PROXY_DIR}" && \
            ${DOCKER_COMPOSE_COMMAND} "${PROXY_SUBCOMMAND}" "${PROXY_SUBCOMMAND_ARGS[@]}"
        )
        exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            error "Failed to execute '${PROXY_SUBCOMMAND}' for the proxy service. Exit code: $exit_code"
        else
            if [[ "${PROXY_SUBCOMMAND}" == "restart" || "${PROXY_SUBCOMMAND}" == "up" || "${PROXY_SUBCOMMAND}" == "start" ]]; then
                success "Proxy service ${PROXY_SUBCOMMAND}ed successfully."
            elif [[ "${PROXY_SUBCOMMAND}" == "stop" || "${PROXY_SUBCOMMAND}" == "down" ]]; then
                success "Proxy service ${PROXY_SUBCOMMAND} successfully."
            fi
        fi
        ;;
    status)
        info "Proxy service status (${FORTRESS_PROXY_DIR}):"
        (
            cd "${FORTRESS_PROXY_DIR}" && \
            ${DOCKER_COMPOSE_COMMAND} ps "${PROXY_SUBCOMMAND_ARGS[@]}"
        )
        ;;
    configtest|configdump)
        info "Proxy service: Running Traefik command '${PROXY_SUBCOMMAND}'"
        (
            cd "${FORTRESS_PROXY_DIR}" && \
            ${DOCKER_COMPOSE_COMMAND} exec traefik traefik "${PROXY_SUBCOMMAND}" --configfile=/etc/traefik/traefik.yml "${PROXY_SUBCOMMAND_ARGS[@]}"
        )
        ;;
    *)
        fatal "proxy: Unknown subcommand '${PROXY_SUBCOMMAND}'. Use 'start, stop, restart, up, down, ps, logs, status, configtest, configdump'."
        ;;
esac


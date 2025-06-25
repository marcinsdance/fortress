#!/usr/bin/env bash
[[ ! ${FORTRESS_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

function importCompose() {
  local COMPOSE_FILE="$1"
  local APP_NAME="$2"
  local DOMAIN="$3"
  local ENV_FILE="$4"
  
  [[ -z "${COMPOSE_FILE}" ]] && fatal "import: Docker Compose file path is required."
  [[ -z "${APP_NAME}" ]] && fatal "import: App name is required."
  
  # Convert relative path to absolute
  if [[ ! "${COMPOSE_FILE}" = /* ]]; then
    COMPOSE_FILE="$(pwd)/${COMPOSE_FILE}"
  fi
  
  [[ ! -f "${COMPOSE_FILE}" ]] && fatal "import: Docker Compose file '${COMPOSE_FILE}' not found."
  
  if [[ ! "${APP_NAME}" =~ ^[a-z0-9-]+$ ]]; then
    fatal "import: App name must contain only lowercase letters, numbers, and hyphens."
  fi
  
  info "Importing docker-compose project '${APP_NAME}' from: ${COMPOSE_FILE}"
  
  # Create app directory
  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  if [[ -d "${APP_DIR}" ]]; then
    warning "App directory '${APP_DIR}' already exists. Updating configuration..."
  else
    mkdir -p "${APP_DIR}/data"
    info "Created app directory: ${APP_DIR}"
  fi
  
  # Copy compose file and process it
  local TARGET_COMPOSE="${APP_DIR}/docker-compose.yml"
  cp "${COMPOSE_FILE}" "${TARGET_COMPOSE}"
  
  # Process the compose file to add Fortress integration
  processComposeFile "${TARGET_COMPOSE}" "${APP_NAME}" "${DOMAIN}"
  
  # Handle environment file
  local env_file_path="${APP_DIR}/.env"
  if [[ -n "${ENV_FILE}" ]] && [[ -f "${ENV_FILE}" ]]; then
    cp "${ENV_FILE}" "${env_file_path}"
    info "Copied environment file from ${ENV_FILE}"
  else
    # Create basic .env file
    info "Creating basic .env file"
    cat > "${env_file_path}" <<EOF
APP_NAME=${APP_NAME}
APP_DOMAIN=${DOMAIN}
DATABASE_URL=postgresql://\${DB_USER}:\${DB_PASS}@postgres:5432/\${DB_NAME}
REDIS_URL=redis://redis:6379
NODE_ENV=production
EOF
  fi
  
  # Create fortress metadata
  local fortress_metadata_file="${APP_DIR}/fortress.yml"
  info "Generating metadata file at ${fortress_metadata_file}"
  cat > "${fortress_metadata_file}" <<EOF
name: ${APP_NAME}
type: imported
domain: ${DOMAIN}
source: docker-compose
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
status: deploying
original_compose: $(basename "${COMPOSE_FILE}")
EOF
  
  chown -R fortress:fortress "${APP_DIR}" 2>/dev/null || true
  chmod 600 "${env_file_path}"
  
  # Deploy the application
  info "Starting application '${APP_NAME}' from imported compose file..."
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" up -d --remove-orphans)
  
  # Update status
  sed -i 's/status: deploying/status: running/' "${fortress_metadata_file}"
  
  success "Application '${APP_NAME}' imported and deployed from docker-compose.yml"
  echo ""
  if [[ -n "${DOMAIN}" ]]; then
    echo "  URL: https://${DOMAIN}"
  fi
  echo "  App Directory: ${APP_DIR}"
  echo "  Manage with: fortress app <status|logs|stop|remove|...> ${APP_NAME}"
}

function processComposeFile() {
  local COMPOSE_FILE="$1"
  local APP_NAME="$2"
  local DOMAIN="$3"
  
  info "Processing compose file to add Fortress integration..."
  
  # Add fortress network and labels
  addFortressIntegration "${COMPOSE_FILE}" "${APP_NAME}" "${DOMAIN}"
}

function addFortressIntegration() {
  local COMPOSE_FILE="$1"
  local APP_NAME="$2"
  local DOMAIN="$3"
  
  # Use Python to modify the YAML file
  python3 - "${COMPOSE_FILE}" "${APP_NAME}" "${DOMAIN}" <<'EOF'
import sys
import yaml

def add_fortress_integration(compose_file, app_name, domain):
    with open(compose_file, 'r') as f:
        compose = yaml.safe_load(f)
    
    if not compose or 'services' not in compose:
        print("Warning: No services found in compose file")
        return
    
    # Add fortress network to networks section
    if 'networks' not in compose:
        compose['networks'] = {}
    compose['networks']['fortress'] = {'external': True}
    
    # Find main service (first with ports)
    main_service = None
    main_port = "3000"
    
    for service_name, service_config in compose['services'].items():
        # Add fortress network to all services
        if 'networks' not in service_config:
            service_config['networks'] = ['fortress']
        elif isinstance(service_config['networks'], list):
            if 'fortress' not in service_config['networks']:
                service_config['networks'].append('fortress')
        elif isinstance(service_config['networks'], dict):
            service_config['networks']['fortress'] = None
        
        # Add fortress labels to all services
        if 'labels' not in service_config:
            service_config['labels'] = []
        
        fortress_labels = [
            f"fortress.app={app_name}",
            "fortress.managed=true",
            "fortress.type=imported"
        ]
        
        for label in fortress_labels:
            if label not in service_config['labels']:
                service_config['labels'].append(label)
        
        # Detect main service for Traefik
        if 'ports' in service_config and main_service is None:
            main_service = service_name
            ports = service_config['ports']
            if ports:
                port_mapping = ports[0]
                if isinstance(port_mapping, str) and ':' in port_mapping:
                    main_port = port_mapping.split(':')[-1]
                elif isinstance(port_mapping, int):
                    main_port = str(port_mapping)
    
    # Add Traefik labels to main service
    if main_service and domain:
        service = compose['services'][main_service]
        
        traefik_labels = [
            "traefik.enable=true",
            "traefik.docker.network=fortress",
            f"traefik.http.routers.{app_name}.rule=Host(`{domain}`)",
            f"traefik.http.routers.{app_name}.entrypoints=web",
            f"traefik.http.routers.{app_name}.middlewares={app_name}-redirect@file",
            f"traefik.http.routers.{app_name}-secure.rule=Host(`{domain}`)",
            f"traefik.http.routers.{app_name}-secure.entrypoints=websecure",
            f"traefik.http.routers.{app_name}-secure.tls=true",
            f"traefik.http.routers.{app_name}-secure.tls.certresolver=letsencrypt",
            f"traefik.http.routers.{app_name}-secure.middlewares=fortress-security-headers@file,fortress-rate-limit@file",
            f"traefik.http.services.{app_name}.loadbalancer.server.port={main_port}",
            f"traefik.http.middlewares.{app_name}-redirect.redirectscheme.scheme=https",
            f"traefik.http.middlewares.{app_name}-redirect.redirectscheme.permanent=true"
        ]
        
        for label in traefik_labels:
            if label not in service['labels']:
                service['labels'].append(label)
    
    # Write back to file
    with open(compose_file, 'w') as f:
        yaml.dump(compose, f, default_flow_style=False)

if __name__ == "__main__":
    compose_file = sys.argv[1]
    app_name = sys.argv[2]
    domain = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
    
    add_fortress_integration(compose_file, app_name, domain)
EOF
}

function deployApp() {
  local APP_NAME=""
  local DOMAIN=""
  local PORT=""
  local IMAGE=""
  local ENV_FILE=""
  local APP_TYPE="web"
  local REPLICAS=1
  local COMPOSE_FILE=""
  
  local args_to_parse=("$@") 
  local remaining_args=()
  
  idx=0
  while [[ $idx -lt ${#args_to_parse[@]} ]]; do
    local arg="${args_to_parse[$idx]}"
    case $arg in
      --domain=*)
        DOMAIN="${arg#*=}"
        ;;
      --port=*)
        PORT="${arg#*=}"
        ;;
      --image=*)
        IMAGE="${arg#*=}"
        ;;
      --env-file=*)
        ENV_FILE="${arg#*=}"
        ;;
      --type=*)
        APP_TYPE="${arg#*=}"
        ;;
      --replicas=*)
        REPLICAS="${arg#*=}"
        ;;
      --compose-file=*)
        COMPOSE_FILE="${arg#*=}"
        ;;
      -*)
        fatal "deployApp: Unknown option: $arg"
        ;;
      *)
        if [[ -z "${APP_NAME}" ]]; then
          APP_NAME="$arg"
        else
          remaining_args+=("$arg") # Collect any unexpected positional args
        fi
        ;;
    esac
    idx=$((idx + 1))
  done

  if [[ ${#remaining_args[@]} -gt 0 ]]; then
    warning "deployApp: Unexpected arguments: ${remaining_args[*]}"
  fi
  
  [[ -z "${APP_NAME}" ]] && fatal "deployApp: App name is required as the first argument."
  
  # Check if we're deploying from existing docker-compose file
  if [[ -n "${COMPOSE_FILE}" ]]; then
    importCompose "${COMPOSE_FILE}" "${APP_NAME}" "${DOMAIN}" "${ENV_FILE}"
    return
  fi
  
  [[ -z "${DOMAIN}" ]] && fatal "deployApp: --domain=<domain.com> is required."
  [[ -z "${PORT}" ]] && fatal "deployApp: --port=<internal_app_port> is required."
  [[ -z "${IMAGE}" ]] && IMAGE="${APP_NAME}:latest" 
  
  if [[ ! "${APP_NAME}" =~ ^[a-z0-9-]+$ ]]; then
    fatal "deployApp: App name must contain only lowercase letters, numbers, and hyphens."
  fi
  
  info "Deploying app: ${APP_NAME}"
  info "  Domain: ${DOMAIN}"
  info "  Port (internal container): ${PORT}"
  info "  Image: ${IMAGE}"
  info "  Replicas: ${REPLICAS}"
  
  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  if [[ -d "${APP_DIR}" ]]; then
    warning "App directory '${APP_DIR}' already exists. Updating configuration..."
  else
    mkdir -p "${APP_DIR}/data"
    info "Created app directory: ${APP_DIR}"
  fi
  
  local env_file_path="${APP_DIR}/.env"
  if [[ -n "${ENV_FILE}" ]]; then
    if [[ -f "${ENV_FILE}" ]]; then
      cp "${ENV_FILE}" "${env_file_path}"
      info "Copied specified environment file from ${ENV_FILE} to ${env_file_path}"
    else
      warning "Specified environment file ${ENV_FILE} not found. Generating default .env."
      ENV_FILE="" 
    fi
  fi

  if [[ -z "${ENV_FILE}" || ! -f "${env_file_path}" ]]; then
    info "Generating default .env file at ${env_file_path}"
    cat > "${env_file_path}" <<EOF
APP_NAME=${APP_NAME}
APP_DOMAIN=${DOMAIN}
APP_SERVICE_INTERNAL_PORT=${PORT}
APP_IMAGE=${IMAGE}
APP_REPLICAS=${REPLICAS}

DATABASE_URL=postgresql://\${DB_USER}:\${DB_PASS}@postgres:5432/\${DB_NAME}
REDIS_URL=redis://redis:6379

NODE_ENV=production
EOF
  fi
  
  local compose_file_path="${APP_DIR}/docker-compose.yml"
  info "Generating ${compose_file_path}..."
  cat > "${compose_file_path}" <<EOF
services:
  app:
    image: \${APP_IMAGE:-${IMAGE}}
    container_name: fortress_${APP_NAME}
    restart: unless-stopped
    networks:
      - fortress
    env_file:
      - .env
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=fortress"
      - "traefik.http.routers.${APP_NAME}.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.${APP_NAME}.entrypoints=web"
      - "traefik.http.routers.${APP_NAME}.middlewares=${APP_NAME}-redirect@file"
      - "traefik.http.routers.${APP_NAME}-secure.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.${APP_NAME}-secure.entrypoints=websecure"
      - "traefik.http.routers.${APP_NAME}-secure.tls=true"
      - "traefik.http.routers.${APP_NAME}-secure.tls.certresolver=letsencrypt"
      - "traefik.http.routers.${APP_NAME}-secure.middlewares=fortress-security-headers@file,fortress-rate-limit@file"
      - "traefik.http.services.${APP_NAME}.loadbalancer.server.port=${PORT}"
      - "traefik.http.middlewares.${APP_NAME}-redirect.redirectscheme.scheme=https"
      - "traefik.http.middlewares.${APP_NAME}-redirect.redirectscheme.permanent=true"
      - "fortress.app=${APP_NAME}"
      - "fortress.type=${APP_TYPE}"
      - "fortress.managed=true"
      - "fortress.domain=${DOMAIN}"
      - "fortress.port=${PORT}"
    deploy:
      replicas: \${APP_REPLICAS:-${REPLICAS}}
      resources:
        limits:
          cpus: '${DEFAULT_APP_CPU_LIMIT:-0.5}'
          memory: ${DEFAULT_APP_MEMORY_LIMIT:-512M}
        reservations:
          cpus: '0.1'
          memory: 128M
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${PORT}/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    volumes:
      - ./data:/app/data
      - /etc/localtime:/etc/localtime:ro
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        labels: "fortress.app=${APP_NAME}"

networks:
  fortress:
    external: true
EOF
  
  local fortress_metadata_file="${APP_DIR}/fortress.yml"
  info "Generating metadata file at ${fortress_metadata_file}"
  cat > "${fortress_metadata_file}" <<EOF
name: ${APP_NAME}
type: ${APP_TYPE}
domain: ${DOMAIN}
port: ${PORT}
image: ${IMAGE}
replicas: ${REPLICAS}
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
status: deploying
EOF
  chown -R fortress:fortress "${APP_DIR}"
  chmod 600 "${env_file_path}"
  
  info "Pulling image and starting application '${APP_NAME}'..."
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" pull)
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" up -d --remove-orphans --scale app="${REPLICAS}")
  
  info "Waiting for application '${APP_NAME}' to be healthy (up to 60s)..."
  local RETRIES=30 
  local HEALTHY=false
  while [[ ${RETRIES} -gt 0 ]]; do
    if docker ps --filter "name=fortress_${APP_NAME}" --filter "health=healthy" --format "{{.Names}}" | grep -q "fortress_${APP_NAME}"; then
      HEALTHY=true
      break
    elif ! docker ps --filter "name=fortress_${APP_NAME}" --format "{{.Names}}" | grep -q "fortress_${APP_NAME}"; then
      error "Container fortress_${APP_NAME} is not running. Deployment might have failed."
      break 
    fi
    RETRIES=$((RETRIES - 1))
    sleep 2
  done
  
  if [[ "${HEALTHY}" == "true" ]]; then
    success "Application '${APP_NAME}' is healthy!"
    sed -i 's/status: deploying/status: running/' "${fortress_metadata_file}"
  else
    warning "Health check for '${APP_NAME}' did not pass or container not found. Please check logs: fortress logs ${APP_NAME}"
    sed -i 's/status: deploying/status: failed_healthcheck/' "${fortress_metadata_file}"
  fi
  
  success "Application '${APP_NAME}' deployment process finished."
  echo ""
  echo "  URL: https://${DOMAIN}"
  echo "  Container Name: fortress_${APP_NAME} (or similar if scaled)"
  echo "  App Directory: ${APP_DIR}"
  echo "  Manage with: fortress app <status|logs|stop|remove|...> ${APP_NAME}"
}

function listApps() {
  info "Listing all Fortress applications..."
  echo ""
  
  printf "%-20s %-35s %-10s %-20s %-10s\n" "NAME" "DOMAIN" "PORT" "STATUS" "REPLICAS"
  printf "%-20s %-35s %-10s %-20s %-10s\n" "----" "------" "----" "------" "--------"
  
  if [ -z "$(ls -A ${FORTRESS_APPS_DIR})" ]; then
    echo "No applications deployed yet."
    return
  fi

  for APP_NAME_DIR in "${FORTRESS_APPS_DIR}"/*; do
    if [[ -d "${APP_NAME_DIR}" ]] && [[ -f "${APP_NAME_DIR}/fortress.yml" ]]; then
      local APP_NAME=$(basename "${APP_NAME_DIR}")
      # Source the app's .env to get declared replicas if needed, or read from fortress.yml
      # For simplicity, reading from fortress.yml first
      local META_DOMAIN=$(grep "^domain:" "${APP_NAME_DIR}/fortress.yml" | cut -d' ' -f2)
      local META_PORT=$(grep "^port:" "${APP_NAME_DIR}/fortress.yml" | cut -d' ' -f2)
      local META_STATUS=$(grep "^status:" "${APP_NAME_DIR}/fortress.yml" | cut -d' ' -f2)
      local META_REPLICAS=$(grep "^replicas:" "${APP_NAME_DIR}/fortress.yml" | cut -d' ' -f2 || echo "1")

      # Get live container status
      local LIVE_STATUS="stopped"
      local LIVE_REPLICAS=0
      if docker ps --format "{{.Names}}" --filter "label=com.docker.compose.project=${APP_NAME}" --filter "label=com.docker.compose.service=app" | grep -q "."; then
        LIVE_STATUS="running" # More accurately, 'up'
        # Count actual running replicas for the 'app' service of the project
        LIVE_REPLICAS=$(docker ps --format "{{.Names}}" --filter "label=com.docker.compose.project=${APP_NAME}" --filter "label=com.docker.compose.service=app" | wc -l)
      fi
      
      # Prefer live status if possible, fallback to metadata status
      local DISPLAY_STATUS="${LIVE_STATUS}"
      if [[ "${LIVE_STATUS}" == "stopped" && "${META_STATUS}" != "deploying" && "${META_STATUS}" != "" ]]; then
        DISPLAY_STATUS="${META_STATUS}" 
      fi
      if [[ "${LIVE_STATUS}" == "running" && "${META_STATUS}" == "failed_healthcheck" ]]; then
        DISPLAY_STATUS="running (unhealthy)"
      fi


      printf "%-20s %-35s %-10s %-20s %-10s\n" "${APP_NAME}" "${META_DOMAIN}" "${META_PORT}" "${DISPLAY_STATUS}" "${LIVE_REPLICAS}/${META_REPLICAS}"
    fi
  done
}

function appStatus() {
  local APP_NAME="$1"
  [[ -z "${APP_NAME}" ]] && fatal "app status: App name is required."
  
  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  [[ ! -d "${APP_DIR}" || ! -f "${APP_DIR}/fortress.yml" ]] && fatal "app status: App '${APP_NAME}' not found or not managed by Fortress."
  
  info "Status for app: ${APP_NAME}"
  echo ""
  
  echo "Metadata from ${APP_DIR}/fortress.yml:"
  cat "${APP_DIR}/fortress.yml"
  echo ""
  
  info "Docker Compose Status (project: ${APP_NAME}):"
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" ps)
  echo ""

  info "Live Container Resource Usage (service: app):"
  # Docker stats for all containers of the app service
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker ps --filter "label=com.docker.compose.project=${APP_NAME}" --filter "label=com.docker.compose.service=app" --format "{{.Names}}") || echo "No running 'app' service containers found for stats."
}

function updateApp() {
  local APP_NAME="$1"
  [[ -z "${APP_NAME}" ]] && fatal "app update: App name is required."
  shift 

  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  [[ ! -d "${APP_DIR}" ]] && fatal "app update: App '${APP_NAME}' not found."

  local NEW_IMAGE=""
  local PULL_IMAGE=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --image=*)
        NEW_IMAGE="${1#*=}"
        shift
        ;;
      --pull)
        PULL_IMAGE=true
        shift
        ;;
      *)
        fatal "app update: Unknown option '$1'"
        ;;
    esac
  done

  if [[ -z "${NEW_IMAGE}" ]]; then
    fatal "app update: New image is required via --image=<new_image_tag>"
  fi

  info "Updating app '${APP_NAME}' to image '${NEW_IMAGE}'..."
  
  (cd "${APP_DIR}" && \
   echo "APP_IMAGE=${NEW_IMAGE}" >> .env && \
   ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" config > /dev/null && \
   ( [[ "$PULL_IMAGE" == true ]] && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" pull app ) && \
   ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" up -d --remove-orphans --force-recreate app ) # Target only 'app' service

  if [[ $? -eq 0 ]]; then
    sed -i "s|^image: .*|image: ${NEW_IMAGE}|" "${APP_DIR}/fortress.yml"
    echo "updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "${APP_DIR}/fortress.yml"
    success "App '${APP_NAME}' updated successfully to image '${NEW_IMAGE}'."
  else
    error "Failed to update app '${APP_NAME}'."
  fi
}

function removeApp() {
  local APP_NAME="$1"
  [[ -z "${APP_NAME}" ]] && fatal "app remove: App name is required."

  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  [[ ! -d "${APP_DIR}" ]] && fatal "app remove: App '${APP_NAME}' not found."

  warning "This will stop and remove the app '${APP_NAME}', its containers, networks, and potentially named volumes defined in its compose file."
  read -p "Are you sure you want to remove app '${APP_NAME}'? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Removal of app '${APP_NAME}' cancelled."
    return
  fi

  info "Removing app: ${APP_NAME}..."
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" down -v)
  
  local BACKUP_FILE="${FORTRESS_BACKUPS_DIR}/removed/${APP_NAME}-$(date +%Y%m%d-%H%M%S).tar.gz"
  info "Attempting to backup app directory ${APP_DIR} to ${BACKUP_FILE} before removal..."
  if tar -czf "${BACKUP_FILE}" -C "$(dirname "${APP_DIR}")" "$(basename "${APP_DIR}")"; then
    info "Backup of app directory saved to: ${BACKUP_FILE}"
  else
    warning "Failed to create backup of app directory. Proceeding with removal."
  fi
  
  rm -rf "${APP_DIR}"
  success "App '${APP_NAME}' and its directory removed successfully."
}

function restartApp() {
  local APP_NAME="$1"
  [[ -z "${APP_NAME}" ]] && fatal "app restart: App name is required."
  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  [[ ! -d "${APP_DIR}" ]] && fatal "app restart: App '${APP_NAME}' not found."
  
  info "Restarting app: ${APP_NAME}..."
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" restart app) # Restart only the 'app' service typically
  success "App '${APP_NAME}' restart initiated."
}

function stopApp() {
  local APP_NAME="$1"
  [[ -z "${APP_NAME}" ]] && fatal "app stop: App name is required."
  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  [[ ! -d "${APP_DIR}" ]] && fatal "app stop: App '${APP_NAME}' not found."

  info "Stopping app: ${APP_NAME}..."
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" stop app)
  sed -i "s/status: .*/status: stopped/" "${APP_DIR}/fortress.yml"
  success "App '${APP_NAME}' stop initiated."
}

function startApp() {
  local APP_NAME="$1"
  [[ -z "${APP_NAME}" ]] && fatal "app start: App name is required."
  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  [[ ! -d "${APP_DIR}" ]] && fatal "app start: App '${APP_NAME}' not found."

  info "Starting app: ${APP_NAME}..."
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" start app)
  sed -i "s/status: .*/status: starting/" "${APP_DIR}/fortress.yml" # Update status, healthcheck will confirm running
  success "App '${APP_NAME}' start initiated."
}

function scaleApp() {
  local APP_NAME="$1"
  [[ -z "${APP_NAME}" ]] && fatal "app scale: App name is required."
  shift

  local REPLICAS="$1"
  if ! [[ "${REPLICAS}" =~ ^[0-9]+$ ]]; then
    fatal "app scale: Number of replicas must be a positive integer. Provided: '${REPLICAS}'"
  fi
  shift

  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  [[ ! -d "${APP_DIR}" ]] && fatal "app scale: App '${APP_NAME}' not found."

  info "Scaling app '${APP_NAME}' to ${REPLICAS} replicas..."
  
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" up -d --scale app="${REPLICAS}" --no-recreate)
  
  if grep -q "^APP_REPLICAS=" "${APP_DIR}/.env"; then
    sed -i "s/^APP_REPLICAS=.*/APP_REPLICAS=${REPLICAS}/" "${APP_DIR}/.env"
  else
    echo "APP_REPLICAS=${REPLICAS}" >> "${APP_DIR}/.env"
  fi
  sed -i "s/^replicas: .*/replicas: ${REPLICAS}/" "${APP_DIR}/fortress.yml"
  
  success "App '${APP_NAME}' scaled to ${REPLICAS} replicas."
}

function setAppLimits() {
  local APP_NAME="$1"
  [[ -z "${APP_NAME}" ]] && fatal "app limits: App name is required."
  shift

  local CPU_LIMIT=""
  local MEMORY_LIMIT=""
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --cpu=*)
        CPU_LIMIT="${1#*=}"
        shift
        ;;
      --memory=*)
        MEMORY_LIMIT="${1#*=}"
        shift
        ;;
      *)
        fatal "app limits: Unknown option '$1'"
        ;;
    esac
  done

  local APP_DIR="${FORTRESS_APPS_DIR}/${APP_NAME}"
  [[ ! -d "${APP_DIR}" ]] && fatal "app limits: App '${APP_NAME}' not found."
  local COMPOSE_FILE="${APP_DIR}/docker-compose.yml"

  if [[ -z "${CPU_LIMIT}" && -z "${MEMORY_LIMIT}" ]]; then
    fatal "app limits: At least one of --cpu or --memory must be specified."
  fi

  info "Setting resource limits for app: ${APP_NAME}"
  [[ -n "${CPU_LIMIT}" ]] && info "  New CPU Limit: ${CPU_LIMIT}"
  [[ -n "${MEMORY_LIMIT}" ]] && info "  New Memory Limit: ${MEMORY_LIMIT}"

  if [[ -n "${CPU_LIMIT}" ]]; then
    # This sed command is a bit basic; yq would be better for robust YAML editing
    sed -i "/services:/,/app:/ s|cpus: '.*'|cpus: '${CPU_LIMIT}'|" "${COMPOSE_FILE}"
    # If the line doesn't exist, this sed won't add it. Needs more robust YAML parsing or template regeneration.
  fi
  
  if [[ -n "${MEMORY_LIMIT}" ]]; then
    sed -i "/services:/,/app:/ s|memory: .*M|memory: ${MEMORY_LIMIT}|" "${COMPOSE_FILE}"
  fi
  
  (cd "${APP_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "${APP_NAME}" up -d --remove-orphans app) # Recreate app service to apply limits
  
  success "Resource limits updated for app '${APP_NAME}'. Container(s) recreated."
}

if [[ ${#FORTRESS_PARAMS[@]} -eq 0 ]]; then
    SUBCOMMAND="list"
    SUBCOMMAND_ARGS=()
else
    SUBCOMMAND="${FORTRESS_PARAMS[0]}"
    SUBCOMMAND_ARGS=("${FORTRESS_PARAMS[@]:1}")
fi

case "${SUBCOMMAND}" in
  deploy)
    deployApp "${SUBCOMMAND_ARGS[@]}"
    ;;
  import)
    # Parse import arguments: <compose-file> <app-name> [--domain=<domain>] [--env-file=<file>]
    local COMPOSE_FILE_ARG=""
    local APP_NAME_ARG=""
    local DOMAIN_ARG=""
    local ENV_FILE_ARG=""
    
    # Parse arguments for import command
    local import_args=("${SUBCOMMAND_ARGS[@]}")
    local idx=0
    
    while [[ $idx -lt ${#import_args[@]} ]]; do
      local arg="${import_args[$idx]}"
      case $arg in
        --domain=*)
          DOMAIN_ARG="${arg#*=}"
          ;;
        --env-file=*)
          ENV_FILE_ARG="${arg#*=}"
          ;;
        -*)
          fatal "app import: Unknown option: $arg"
          ;;
        *)
          if [[ -z "${COMPOSE_FILE_ARG}" ]]; then
            COMPOSE_FILE_ARG="$arg"
          elif [[ -z "${APP_NAME_ARG}" ]]; then
            APP_NAME_ARG="$arg"
          fi
          ;;
      esac
      idx=$((idx + 1))
    done
    
    importCompose "${COMPOSE_FILE_ARG}" "${APP_NAME_ARG}" "${DOMAIN_ARG}" "${ENV_FILE_ARG}"
    ;;
  list)
    listApps
    ;;
  status)
    [[ ${#SUBCOMMAND_ARGS[@]} -lt 1 ]] && fatal "app status: Application name required."
    appStatus "${SUBCOMMAND_ARGS[0]}" 
    ;;
  update)
    [[ ${#SUBCOMMAND_ARGS[@]} -lt 1 ]] && fatal "app update: Application name and options required."
    updateApp "${SUBCOMMAND_ARGS[@]}"
    ;;
  remove)
    [[ ${#SUBCOMMAND_ARGS[@]} -lt 1 ]] && fatal "app remove: Application name required."
    removeApp "${SUBCOMMAND_ARGS[0]}"
    ;;
  restart)
    [[ ${#SUBCOMMAND_ARGS[@]} -lt 1 ]] && fatal "app restart: Application name required."
    restartApp "${SUBCOMMAND_ARGS[0]}"
    ;;
  stop)
    [[ ${#SUBCOMMAND_ARGS[@]} -lt 1 ]] && fatal "app stop: Application name required."
    stopApp "${SUBCOMMAND_ARGS[0]}"
    ;;
  start)
    [[ ${#SUBCOMMAND_ARGS[@]} -lt 1 ]] && fatal "app start: Application name required."
    startApp "${SUBCOMMAND_ARGS[0]}"
    ;;
  scale)
    [[ ${#SUBCOMMAND_ARGS[@]} -lt 2 ]] && fatal "app scale: Application name and replica count required."
    scaleApp "${SUBCOMMAND_ARGS[0]}" "${SUBCOMMAND_ARGS[1]}" # Pass app name and replicas
    ;;
  limits)
    [[ ${#SUBCOMMAND_ARGS[@]} -lt 1 ]] && fatal "app limits: Application name and limit options required."
    # limits function parses its own --cpu and --memory from SUBCOMMAND_ARGS passed to it
    setAppLimits "${SUBCOMMAND_ARGS[@]}"
    ;;
  *)
    fatal "app: Unknown subcommand '${SUBCOMMAND}'. Use 'fortress app --help'."
    ;;
esac


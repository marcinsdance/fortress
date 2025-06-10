#!/usr/bin/env bash
[[ ! ${FORTRESS_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if [[ $EUID -ne 0 ]]; then
    fatal "This command must be run as root or with sudo"
fi

info "Installing Fortress on this server (Rocky Linux 9)..."
echo ""

if [[ ! -f /etc/os-release ]]; then
    fatal "Cannot detect OS. This installer requires Rocky Linux 9."
fi

source /etc/os-release
if [[ "${ID}" != "rocky" ]]; then
    fatal "This installer currently supports Rocky Linux 9. Detected OS: ${ID}"
fi
if [[ ! "$(echo "${VERSION_ID}" | cut -d. -f1)" == "9" ]]; then
    fatal "This installer requires Rocky Linux version 9. Detected version: ${VERSION_ID}"
fi

info "Installing system dependencies..."
dnf check-update -y || true
if ! dnf list installed epel-release > /dev/null 2>&1; then
    info "Installing EPEL repository..."
    dnf install -y epel-release
fi
dnf install -y \
    curl \
    git \
    wget \
    htop \
    nano \
    firewalld \
    fail2ban \
    dnf-automatic \
    logrotate \
    ca-certificates \
    gnupg \
    policycoreutils-python-utils

if ! command -v docker &> /dev/null; then
    info "Installing Docker Engine and Docker Compose plugin..."
    if ! dnf config-manager --help &>/dev/null ; then
        dnf install -y 'dnf-command(config-manager)'
    fi
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    info "Starting and enabling Docker service..."
    systemctl start docker
    systemctl enable docker
else
    info "Docker is already installed."
fi

if ! id -u fortress >/dev/null 2>&1; then
    info "Creating 'fortress' system user..."
    useradd -r -s /bin/bash -m -d "${FORTRESS_ROOT}" fortress
    usermod -aG docker fortress
    info "User 'fortress' created and added to 'docker' group."
else
    info "User 'fortress' already exists."
    if ! groups fortress | grep -q '\bdocker\b'; then
        usermod -aG docker fortress
        info "Added existing user 'fortress' to 'docker' group."
    fi
fi

info "Creating Fortress directory structure in ${FORTRESS_ROOT}..."
mkdir -p "${FORTRESS_APPS_DIR}"
mkdir -p "${FORTRESS_PROXY_DIR}"/{dynamic,acme,logs}
mkdir -p "${FORTRESS_SERVICES_DIR}"/postgres/{data,backups}
mkdir -p "${FORTRESS_SERVICES_DIR}"/redis/data
mkdir -p "${FORTRESS_BACKUPS_DIR}"/{scheduled,manual,removed}
mkdir -p "${FORTRESS_CONFIG_DIR}"
mkdir -p "${FORTRESS_ROOT}/logs"

# --- NEW ADDITION: Copy Fortress core files to their final destination ---
info "Copying Fortress core scripts, commands, and utilities to ${FORTRESS_ROOT}..."
mkdir -p "${FORTRESS_ROOT}/bin" # Ensure bin directory exists
cp -r "${FORTRESS_DIR}/commands" "${FORTRESS_ROOT}/"
cp -r "${FORTRESS_DIR}/utils" "${FORTRESS_ROOT}/"
cp "${FORTRESS_DIR}/bin/fortress" "${FORTRESS_ROOT}/bin/fortress"
chmod +x "${FORTRESS_ROOT}/bin/fortress"
# --- END NEW ADDITION ---

chown -R fortress:fortress "${FORTRESS_ROOT}"
chmod 700 "${FORTRESS_ROOT}/backups"
chmod 750 "${FORTRESS_ROOT}"

if ! docker network inspect fortress >/dev/null 2>&1; then
    info "Creating Docker network 'fortress'..."
    docker network create fortress
else
    info "Docker network 'fortress' already exists."
fi

info "Setting up Traefik proxy configuration in ${FORTRESS_PROXY_DIR}..."
cat > "${FORTRESS_PROXY_DIR}/traefik.yml" <<'EOF'
api:
  dashboard: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ADMIN_EMAIL}
      storage: /etc/traefik/acme/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    network: fortress
    exposedByDefault: false
    watch: true
  file:
    directory: /etc/traefik/dynamic
    watch: true

log:
  level: INFO
#  filePath: /var/log/traefik/traefik.log

accessLog:
#  filePath: /var/log/traefik/access.log
  bufferingSize: 100
  filters:
    statusCodes: "200-599"
EOF

cat > "${FORTRESS_PROXY_DIR}/dynamic/middlewares.yml" <<'EOF'
http:
  middlewares:
    fortress-security-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
        contentTypeNosniff: true
        contentSecurityPolicy: "frame-ancestors 'self'"
        referrerPolicy: "strict-origin-when-cross-origin"

    fortress-rate-limit:
      rateLimit:
        average: 100
        burst: 50

    fortress-compress:
      compress: {}
EOF

cat > "${FORTRESS_PROXY_DIR}/docker-compose.yml" <<'EOF'
services:
  traefik:
    image: traefik:v3.0
    container_name: fortress_traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - fortress
    ports:
      - "80:80"
      - "443:443"
    environment:
      - ADMIN_EMAIL=${ADMIN_EMAIL}
      - TRAEFIK_AUTH_USERS=${TRAEFIK_AUTH_USERS}
      - FORTRESS_DOMAIN=${FORTRESS_DOMAIN}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - ./acme:/etc/traefik/acme
      - ./logs:/var/log/traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(`monitor.${FORTRESS_DOMAIN}`)"
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.middlewares=fortress-dashboard-auth"
      - "traefik.http.middlewares.fortress-dashboard-auth.basicauth.users=${TRAEFIK_AUTH_USERS}"

networks:
  fortress:
    external: true
EOF
chown -R fortress:fortress "${FORTRESS_PROXY_DIR}"

info "Setting up PostgreSQL service in ${FORTRESS_SERVICES_DIR}/postgres..."
cat > "${FORTRESS_SERVICES_DIR}/postgres/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: fortress_postgres
    restart: unless-stopped
    networks:
      - fortress
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=postgres
    volumes:
      - ./data:/var/lib/postgresql/data
      - ./backups:/backups
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

networks:
  fortress:
    external: true
EOF
chown -R fortress:fortress "${FORTRESS_SERVICES_DIR}/postgres"

info "Setting up Redis service in ${FORTRESS_SERVICES_DIR}/redis..."
cat > "${FORTRESS_SERVICES_DIR}/redis/docker-compose.yml" <<'EOF'
services:
  redis:
    image: redis:7.2-alpine
    container_name: fortress_redis
    restart: unless-stopped
    networks:
      - fortress
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - ./data:/data
    ports:
      - "127.0.0.1:6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

networks:
  fortress:
    external: true
EOF
chown -R fortress:fortress "${FORTRESS_SERVICES_DIR}/redis"

info "Creating main Fortress configuration file..."

# Parse command line arguments for ADMIN_EMAIL and FORTRESS_DOMAIN
# This block will handle values passed directly to 'fortress install --admin-email ...'
local PARSED_ADMIN_EMAIL=""
local PARSED_FORTRESS_DOMAIN=""
local CMD_PARAMS=("${FORTRESS_PARAMS[@]}") # Use the FORTRESS_PARAMS array from bin/fortress

local i=0
while [[ $i -lt ${#CMD_PARAMS[@]} ]]; do
  local arg="${CMD_PARAMS[$i]}"
  case $arg in
    --admin-email=*)
      PARSED_ADMIN_EMAIL="${arg#*=}"
      ;;
    --fortress-domain=*)
      PARSED_FORTRESS_DOMAIN="${arg#*=}"
      ;;
    # Add other install-specific flags if needed here
  esac
  i=$((i + 1))
done


if [[ -n "${PARSED_ADMIN_EMAIL}" ]]; then
    ADMIN_EMAIL_INPUT="${PARSED_ADMIN_EMAIL}"
    info "Using ADMIN_EMAIL from command-line argument: ${ADMIN_EMAIL_INPUT}"
elif [[ -n "${ADMIN_EMAIL}" ]]; then # Fallback to environment variable if not in params
    ADMIN_EMAIL_INPUT="${ADMIN_EMAIL}"
    info "Using ADMIN_EMAIL from environment: ${ADMIN_EMAIL_INPUT}"
else
    read -p "Enter admin email for Let's Encrypt (e.g., your-email@example.com): " ADMIN_EMAIL_INPUT
    while [[ -z "${ADMIN_EMAIL_INPUT}" ]]; do
        read -p "Admin email cannot be empty. Please enter a valid email: " ADMIN_EMAIL_INPUT
    done
fi

if [[ -n "${PARSED_FORTRESS_DOMAIN}" ]]; then
    FORTRESS_DOMAIN_INPUT="${PARSED_FORTRESS_DOMAIN}"
    info "Using FORTRESS_DOMAIN from command-line argument: ${FORTRESS_DOMAIN_INPUT}"
elif [[ -n "${FORTRESS_DOMAIN}" ]]; then # Fallback to environment variable if not in params
    FORTRESS_DOMAIN_INPUT="${FORTRESS_DOMAIN}"
    info "Using FORTRESS_DOMAIN from environment: ${FORTRESS_DOMAIN_INPUT}"
else
    read -p "Enter the primary domain for Fortress services (e.g., fortress.yourdomain.com, for monitor.*): " FORTRESS_DOMAIN_INPUT
    while [[ -z "${FORTRESS_DOMAIN_INPUT}" ]]; do
        read -p "Fortress domain cannot be empty. Please enter a valid domain: " FORTRESS_DOMAIN_INPUT
    done
fi

POSTGRES_USER_DEF="fortress"
POSTGRES_PASSWORD_GEN=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9')
TRAEFIK_DASHBOARD_USER_DEF="admin"
TRAEFIK_DASHBOARD_PASSWORD_GEN=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9')
TRAEFIK_AUTH_USERS_HASHED=$(docker run --rm httpd:2.4 htpasswd -nbB "${TRAEFIK_DASHBOARD_USER_DEF}" "${TRAEFIK_DASHBOARD_PASSWORD_GEN}" | sed -e 's/\$/\$\$/g')
TRAEFIK_HTPASSWD_LINE_RAW=$(docker run --rm httpd:2.4 htpasswd -nbB "${TRAEFIK_DASHBOARD_USER_DEF}" "${TRAEFIK_DASHBOARD_PASSWORD_GEN}")

mkdir -p "${FORTRESS_CONFIG_DIR}"
cat > "${FORTRESS_CONFIG_DIR}/fortress.env" <<EOF
FORTRESS_VERSION="${FORTRESS_VERSION:-1.0.0}"
FORTRESS_DOMAIN="${FORTRESS_DOMAIN_INPUT}"
ADMIN_EMAIL="${ADMIN_EMAIL_INPUT}"

POSTGRES_USER="${POSTGRES_USER_DEF}"
POSTGRES_PASSWORD='${POSTGRES_PASSWORD_GEN}'

TRAEFIK_AUTH_USERS='${TRAEFIK_HTPASSWD_LINE_RAW}'

BACKUP_RETENTION_DAYS=30
BACKUP_SCHEDULE="0 2 * * *"

DEFAULT_APP_CPU_LIMIT="0.5"
DEFAULT_APP_MEMORY_LIMIT="512M"
EOF

chmod 600 "${FORTRESS_CONFIG_DIR}/fortress.env"
chown fortress:fortress "${FORTRESS_CONFIG_DIR}/fortress.env"
info "Main configuration saved to ${FORTRESS_CONFIG_DIR}/fortress.env"

info "Configuring firewall (firewalld)..."
if ! systemctl is-active --quiet firewalld; then
    info "Firewalld is not active. Starting and enabling..."
    systemctl enable firewalld --now
fi
for service_name in ssh http https; do
    if ! firewall-cmd --query-service="${service_name}" --permanent > /dev/null 2>&1; then
        firewall-cmd --permanent --add-service="${service_name}"
        info "Firewall: Added ${service_name} service."
    else
        info "Firewall: ${service_name} service already enabled."
    fi
done
firewall-cmd --reload
info "Firewall rules applied."

info "Configuring Fail2ban..."
mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/fortress-defaults.conf <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
destemail = ${ADMIN_EMAIL_INPUT}
sendername = Fail2ban-Fortress
action = %(action_mwl)s

[sshd]
enabled = true
backend = systemd

[docker-traefik]
enabled = true
filter = docker-traefik
logpath = ${FORTRESS_PROXY_DIR}/logs/access.log
port = http,https
maxretry = 20
findtime = 5m
bantime = 15m
EOF

mkdir -p /etc/fail2ban/filter.d
cat > /etc/fail2ban/filter.d/docker-traefik.conf <<'EOF'
[Definition]
failregex = ^<HOST> - .* "(GET|POST|HEAD) .*?" (400|401|403|404|405) .*$
            ^<HOST> - .* "(GET|POST|HEAD) .*?(phpmyadmin|admin|wp-login|setup|config|backup|dump|sql|script) .*?" .*$
ignoreregex =
EOF

if systemctl enable fail2ban --now &> /dev/null; then
    info "Fail2ban enabled and started/restarted."
else
    warning "Fail2ban already enabled or failed to start. Check 'systemctl status fail2ban'."
    systemctl restart fail2ban || error "Failed to restart fail2ban."
fi

info "Configuring log rotation for Fortress components..."
cat > /etc/logrotate.d/fortress <<EOF
${FORTRESS_PROXY_DIR}/logs/*.log
${FORTRESS_APPS_DIR}/*/logs/*.log
${FORTRESS_ROOT}/logs/*.log
{
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 fortress fortress
    sharedscripts
    postrotate
        if docker ps --format '{{.Names}}' | grep -qw '^fortress_traefik$'; then
            docker kill -s USR1 fortress_traefik >/dev/null 2>&1 || true
        fi
    endscript
}
EOF
info "Logrotate configuration for Fortress created."

info "Installing Fortress CLI into ${FORTRESS_ROOT}/bin ..."
# This block was already added correctly in the previous step
# It ensures bin/fortress is copied to the final location
# and symlinked BEFORE it's called again.
mkdir -p "${FORTRESS_ROOT}/bin"
cp "${FORTRESS_DIR}/bin/fortress" "${FORTRESS_ROOT}/bin/fortress"
chmod +x "${FORTRESS_ROOT}/bin/fortress"
ln -sf "${FORTRESS_ROOT}/bin/fortress" /usr/local/bin/fortress

info "Creating systemd service 'fortress-core.service'..."
cat > /etc/systemd/system/fortress-core.service <<EOF
[Unit]
Description=Fortress Core Services (Proxy, DB, Redis)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=${FORTRESS_CONFIG_DIR}/fortress.env
ExecStart=/usr/local/bin/fortress svc up -d proxy postgres redis
ExecStop=/usr/local/bin/fortress svc down proxy postgres redis
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

info "Attempting initial start of Fortress core services (Traefik, PostgreSQL, Redis)..."
if /usr/local/bin/fortress svc up -d proxy postgres redis; then
    info "Fortress core services started successfully."
else
    error "Failed to start one or more Fortress core services during installation."
    error "Please check Docker logs for 'fortress_traefik', 'fortress_postgres', 'fortress_redis'."
    error "You might need to run 'sudo /usr/local/bin/fortress svc up -d proxy postgres redis' manually after checks."
fi

systemctl daemon-reload
systemctl enable fortress-core.service
info "'fortress-core.service' enabled to manage core services on boot."

info "Configuring automatic system updates (dnf-automatic)..."
if ! grep -q "^\s*apply_updates\s*=\s*yes" /etc/dnf/automatic.conf; then
    if grep -q "^\s*#\?\s*apply_updates\s*=" /etc/dnf/automatic.conf; then
        sed -i 's/^\s*#\?\s*apply_updates\s*=.*/apply_updates = yes/' /etc/dnf/automatic.conf
    else
        echo "apply_updates = yes" >> /etc/dnf/automatic.conf
    fi
    info "Enabled application of automatic updates in dnf-automatic."
else
    info "Application of automatic updates already enabled in dnf-automatic."
fi
if systemctl enable --now dnf-automatic.timer &> /dev/null; then
    info "dnf-automatic.timer enabled and started for scheduled updates."
else
    warning "dnf-automatic.timer already enabled or failed to start. Check 'systemctl status dnf-automatic.timer'."
fi

success "Fortress installation on Rocky Linux 9 completed!"
echo ""
echo "=================================="
echo "Installation Summary:"
echo "=================================="
echo "Fortress Root: ${FORTRESS_ROOT}"
echo "Admin Email (for Let's Encrypt): ${ADMIN_EMAIL_INPUT}"
echo "Primary Fortress Domain (for monitor.* etc.): ${FORTRESS_DOMAIN_INPUT}"
echo ""
echo "PostgreSQL User: ${POSTGRES_USER_DEF}"
echo "PostgreSQL Password: ${POSTGRES_PASSWORD_GEN}"
echo ""
echo "Traefik Dashboard: https://monitor.${FORTRESS_DOMAIN_INPUT}"
echo "Traefik Dashboard User: ${TRAEFIK_DASHBOARD_USER_DEF}"
echo "Traefik Dashboard Password: ${TRAEFIK_DASHBOARD_PASSWORD_GEN}"
echo ""
echo "Main configuration: ${FORTRESS_CONFIG_DIR}/fortress.env"
echo "Fortress CLI: /usr/local/bin/fortress"
echo ""
echo "Next steps:"
echo "1. IMPORTANT: Ensure the domain '${FORTRESS_DOMAIN_INPUT}' (and 'monitor.${FORTRESS_DOMAIN_INPUT}') points to this server's public IP address."
echo "2. Review and secure generated passwords stored in ${FORTRESS_CONFIG_DIR}/fortress.env."
echo "3. Implement the 'fortress svc' commands if not already done, as the systemd service relies on them."
echo "4. To deploy your first app:"
echo "   sudo fortress app deploy myapp --domain=myapp.${FORTRESS_DOMAIN_INPUT} --port=3000 --image=yourimage"
echo ""
warning "IMPORTANT: Store the generated passwords (PostgreSQL, Traefik Dashboard) in a secure password manager!"
echo ""

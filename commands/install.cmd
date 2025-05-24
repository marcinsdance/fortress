#!/usr/bin/env bash
# commands/install.cmd - Install Fortress on the server
[[ ! ${FORTRESS_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   fatal "This command must be run as root or with sudo"
fi

info "Installing Fortress on this server..."
echo ""

# Check OS compatibility
if [[ ! -f /etc/os-release ]]; then
  fatal "Cannot detect OS. This installer requires Ubuntu 20.04+ or Debian 11+"
fi

source /etc/os-release
if [[ "${ID}" != "ubuntu" ]] && [[ "${ID}" != "debian" ]]; then
  fatal "This installer only supports Ubuntu and Debian"
fi

# Install dependencies
info "Installing system dependencies..."
apt-get update
apt-get install -y \
  curl \
  git \
  wget \
  htop \
  nano \
  ufw \
  fail2ban \
  unattended-upgrades \
  logrotate \
  ca-certificates \
  gnupg \
  lsb-release

# Install Docker if not present
if ! which docker >/dev/null; then
  info "Installing Docker..."
  curl -fsSL https://download.docker.com/linux/${ID}/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${ID} \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  
  # Start and enable Docker
  systemctl start docker
  systemctl enable docker
fi

# Create fortress user
if ! id -u fortress >/dev/null 2>&1; then
  info "Creating fortress user..."
  useradd -r -s /bin/bash -d /opt/fortress fortress
  usermod -aG docker fortress
fi

# Create directory structure
info "Creating Fortress directory structure..."
mkdir -p "${FORTRESS_ROOT}"/{apps,proxy,services,backups,config,logs}
mkdir -p "${FORTRESS_PROXY_DIR}"/{dynamic,certs}
mkdir -p "${FORTRESS_SERVICES_DIR}"/{postgres,redis,monitoring,backup}
mkdir -p "${FORTRESS_BACKUPS_DIR}"/{scheduled,manual,removed}

# Set permissions
chown -R fortress:fortress "${FORTRESS_ROOT}"
chmod 700 "${FORTRESS_ROOT}"/backups

# Create Docker network
if ! docker network ls | grep -q fortress; then
  info "Creating Docker network..."
  docker network create fortress
fi

# Install Traefik
info "Setting up Traefik proxy..."
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

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ADMIN_EMAIL}
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: web
      # Staging server for testing
      # caServer: https://acme-staging-v02.api.letsencrypt.org/directory

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
  filePath: /var/log/traefik/traefik.log

accessLog:
  filePath: /var/log/traefik/access.log
EOF

# Create dynamic configuration
cat > "${FORTRESS_PROXY_DIR}/dynamic/middlewares.yml" <<'EOF'
http:
  middlewares:
    security-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        customFrameOptionsValue: "SAMEORIGIN"
        customResponseHeaders:
          X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"
          X-Permitted-Cross-Domain-Policies: "none"
          
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        
    compress:
      compress:
        excludedContentTypes:
          - text/event-stream
EOF

# Traefik docker-compose
cat > "${FORTRESS_PROXY_DIR}/docker-compose.yml" <<'EOF'
version: '3.8'

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
      - ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - ./certs:/etc/traefik/certs
      - ./logs:/var/log/traefik
      - acme:/etc/traefik/acme
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`monitor.${FORTRESS_DOMAIN:-localhost}`)"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=${TRAEFIK_AUTH:-admin:$$2y$$10$$YourHashedPasswordHere}"

networks:
  fortress:
    external: true

volumes:
  acme:
EOF

# Install PostgreSQL
info "Setting up PostgreSQL..."
cat > "${FORTRESS_SERVICES_DIR}/postgres/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: fortress_postgres
    restart: unless-stopped
    networks:
      - fortress
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-fortress}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
      - POSTGRES_DB=postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backups:/backups
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-fortress}"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  fortress:
    external: true

volumes:
  postgres_data:
EOF

# Install Redis
info "Setting up Redis..."
cat > "${FORTRESS_SERVICES_DIR}/redis/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: fortress_redis
    restart: unless-stopped
    networks:
      - fortress
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  fortress:
    external: true

volumes:
  redis_data:
EOF

# Create main configuration
info "Creating main configuration..."
ADMIN_EMAIL=""
read -p "Enter admin email for Let's Encrypt: " ADMIN_EMAIL

POSTGRES_PASSWORD=$(openssl rand -base64 32)
TRAEFIK_PASSWORD=$(openssl rand -base64 32)
TRAEFIK_HASH=$(docker run --rm httpd:alpine htpasswd -nbB admin "${TRAEFIK_PASSWORD}" | sed -e s/\\$/\\$\\$/g)

cat > "${FORTRESS_CONFIG_DIR}/fortress.env" <<EOF
# Fortress Configuration
FORTRESS_VERSION=${FORTRESS_VERSION}
FORTRESS_DOMAIN=localhost
ADMIN_EMAIL=${ADMIN_EMAIL}

# Database
POSTGRES_USER=fortress
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Traefik
TRAEFIK_AUTH=admin:${TRAEFIK_HASH}

# Backup
BACKUP_RETENTION_DAYS=30
BACKUP_SCHEDULE="0 2 * * *"

# Resource Limits
DEFAULT_CPU_LIMIT=0.5
DEFAULT_MEMORY_LIMIT=512M
EOF

# Secure the configuration file
chmod 600 "${FORTRESS_CONFIG_DIR}/fortress.env"
chown fortress:fortress "${FORTRESS_CONFIG_DIR}/fortress.env"

# Setup firewall
info "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
echo "y" | ufw enable

# Setup fail2ban
info "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log

[docker-traefik]
enabled = true
filter = docker-traefik
logpath = /opt/fortress/proxy/logs/access.log
port = http,https
EOF

# Create fail2ban filter for Traefik
cat > /etc/fail2ban/filter.d/docker-traefik.conf <<'EOF'
[Definition]
failregex = ^<HOST> - - \[.*\] ".*" (404|403|401) .*$
ignoreregex =
EOF

systemctl restart fail2ban

# Setup log rotation
info "Configuring log rotation..."
cat > /etc/logrotate.d/fortress <<'EOF'
/opt/fortress/logs/*.log
/opt/fortress/proxy/logs/*.log
/opt/fortress/apps/*/logs/*.log
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
        docker kill -s USR1 fortress_traefik 2>/dev/null || true
    endscript
}
EOF

# Create systemd service
info "Creating systemd service..."
cat > /etc/systemd/system/fortress.service <<'EOF'
[Unit]
Description=Fortress Production Deployment System
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/fortress
ExecStart=/usr/local/bin/fortress svc start
ExecStop=/usr/local/bin/fortress svc stop
User=root
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

# Install fortress command globally
info "Installing fortress command..."
ln -sf "${FORTRESS_BIN}" /usr/local/bin/fortress
chmod +x /usr/local/bin/fortress

# Start services
info "Starting Fortress services..."
cd "${FORTRESS_PROXY_DIR}" && docker compose up -d
cd "${FORTRESS_SERVICES_DIR}/postgres" && docker compose up -d
cd "${FORTRESS_SERVICES_DIR}/redis" && docker compose up -d

# Enable fortress service
systemctl daemon-reload
systemctl enable fortress

# Final setup
success "Fortress installation completed!"
echo ""
echo "=================================="
echo "Installation Summary:"
echo "=================================="
echo "Admin Email: ${ADMIN_EMAIL}"
echo "PostgreSQL Password: ${POSTGRES_PASSWORD}"
echo "Traefik Dashboard: https://monitor.<your-domain>"
echo "Traefik Username: admin"
echo "Traefik Password: ${TRAEFIK_PASSWORD}"
echo ""
echo "Configuration saved to: ${FORTRESS_CONFIG_DIR}/fortress.env"
echo ""
echo "Next steps:"
echo "1. Point your domain(s) to this server's IP"
echo "2. Update FORTRESS_DOMAIN in ${FORTRESS_CONFIG_DIR}/fortress.env"
echo "3. Deploy your first app: fortress app deploy myapp --domain=myapp.com --port=3000"
echo ""
warning "IMPORTANT: Save the passwords above in a secure location!"
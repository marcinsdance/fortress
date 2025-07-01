# Fortress - Single VPS Production Deployment Tool

Fortress is a Docker-based deployment tool designed for hosting multiple production applications on a single VPS. Inspired by Warden's simplicity but built for production use, it provides automated SSL, monitoring, backups, and zero-downtime deployments without the complexity of Kubernetes.

## Why Fortress?

- **Cost Effective**: Host 10-20 small apps on a single $20-40/month VPS
- **Simple**: No Kubernetes complexity - just Docker Compose
- **Production Ready**: Automated SSL, monitoring, and backups included
- **Resource Efficient**: Shared services (PostgreSQL, Redis) reduce overhead
- **Zero Downtime**: Rolling deployments keep your apps always available

## Perfect For

- 🚀 SaaS MVPs and side projects
- 🏢 Small business applications
- 👥 Digital agencies hosting client sites
- 💼 Portfolio of small web apps
- 🎓 Learning production deployment

## Features

### 🔒 Automatic SSL Certificates
- Let's Encrypt integration
- Auto-renewal
- Force HTTPS redirect
- HTTP/2 enabled

### 📊 Built-in Monitoring
- Prometheus metrics
- Grafana dashboards
- Health checks
- Resource tracking

### 💾 Automated Backups
- Scheduled backups
- Database dumps
- Volume snapshots
- Easy restoration

### 🚀 Zero-Downtime Deployments
- Rolling updates
- Health check validation
- Automatic rollback
- Version management

### 🛡️ Security First
- Automated firewall setup
- Fail2ban integration
- Security headers
- Rate limiting

### 🗄️ Shared Services
- PostgreSQL database
- Redis cache
- Traefik proxy
- Monitoring stack

## Quick Start

### Requirements

- **OS**: Rocky Linux 9 (officially supported and tested). Other Linux distributions may work but are not guaranteed.
- **RAM**: 2+ GB (4–8 GB recommended)
- **Disk Space**: 20+ GB
- **Access**: Root or `sudo` user

### Installation

The recommended way to install Fortress is using the remote installer script.

```bash
# Run the one-line installer with sudo
curl -fsSL https://raw.githubusercontent.com/marcinsdance/fortress/master/install.sh | sudo bash
```

### Advanced Installation
The installer script accepts flags for automated setups or for installing a specific version. Pass arguments after -s --.
```bash
# Install non-interactively (for Ansible, etc.)
curl -fsSL https://raw.githubusercontent.com/marcinsdance/fortress/master/install.sh | sudo bash -s -- --yes

# Install a specific branch (e.g., 'develop')
curl -fsSL https://raw.githubusercontent.com/marcinsdance/fortress/master/install.sh | sudo bash -s -- --branch develop
```

### Deploy Your First App
```bash
# Deploy a containerized app
fortress app deploy myapp \
  --domain=myapp.com \
  --port=3000 \
  --image=myapp:latest

# Deploy from Docker Hub
fortress app deploy demo \
  --domain=demo.example.com \
  --port=8080 \
  --image=nginxdemos/hello
```

## Core Commands
### Application Management
```bash
fortress app list                             # List all apps
fortress app status myapp                     # View app status
fortress app update myapp --image=myapp:v2    # Update app
fortress app scale myapp 3                    # Scale app
fortress app remove myapp                     # Remove app
```

### Docker Compose Import
```bash
fortress app import docker-compose.yml myapp --domain=myapp.com    # Import existing compose file
fortress app deploy myapp --compose-file=docker-compose.yml --domain=myapp.com  # Deploy with compose file
```

### Resource Management
```bash
fortress app limits myapp --cpu=0.5 --memory=512M   # Set resource limits
fortress resources show                             # View resource usage
fortress resources optimize                         # Optimization suggestions
```

### Database Operations
```bash
fortress db create myapp_db                      # Create database
fortress db backup myapp_db                      # Backup database
fortress db restore myapp_db --from=backup.sql   # Restore database
fortress db connect myapp_db                     # Connect to database
```

### Monitoring & Logs
```bash
fortress logs myapp --follow            # View logs
fortress logs all --tail 50             # View logs for all components
fortress ssl status                     # Check SSL certificates
fortress health check --all             # Check health
fortress monitor dashboard              # Open monitoring dashboard
fortress monitor metrics myapp          # View metrics
```

### System Updates
```bash
fortress update                         # Update Fortress system
fortress update --dry-run              # Simulate update
fortress update verify                 # Verify system after update
```

### Backup & Restore
```bash
fortress backup create --full               # Create backup
fortress backup schedule --daily --retain=7 # Schedule backups
fortress backup list                        # List backups
fortress restore myapp --date=2024-05-24    # Restore backup
```

## Project Structure
```bash
/opt/fortress/
├── apps/                    # Your applications
│   ├── myapp/
│   │   ├── docker-compose.yml
│   │   ├── .env
│   │   └── data/
│   └── anotherapp/
├── proxy/                   # Traefik configuration
│   ├── traefik.yml
│   ├── dynamic/
│   └── certs/
├── services/                # Shared services
│   ├── postgres/            # PostgreSQL database
│   ├── redis/               # Redis cache
│   └── monitoring/          # Prometheus & Grafana
├── backups/                 # Backup storage
└── config/                  # Fortress configuration
```

## Application Configuration
Create a simple app configuration:
```yaml
# fortress.yml
name: myapp
domain: myapp.com
port: 3000
image: myapp:latest

environment:
NODE_ENV: production
DATABASE_URL: ${DATABASE_URL}
REDIS_URL: redis://redis:6379

resources:
cpu: 0.5
memory: 512M

health_check:
path: /health
interval: 30s
```

## Example Deployments
### Node.js Application
```bash
docker build -t myapp:latest .

fortress app deploy myapp \
--domain=myapp.com \
--port=3000 \
--image=myapp:latest \
--env-file=.env.production
```

### Import Existing Docker Compose Project
```bash
# Import a complete docker-compose.yml project
fortress app import ./my-project/docker-compose.yml myapp --domain=myapp.com

# Or use deploy with compose file
fortress app deploy myapp \
--compose-file=./docker-compose.yml \
--domain=myapp.com \
--env-file=.env.production
```

### WordPress Site
```bash
fortress app deploy myblog \
--domain=myblog.com \
--port=80 \
--image=wordpress:latest

fortress db create myblog_wp
```

### Static Site
```bash
fortress app deploy portfolio \
--domain=johndoe.com \
--port=80 \
--image=nginx:alpine \
--volume=./html:/usr/share/nginx/html:ro
```

## Advanced Features
### Custom Domains
```bash
fortress domain add myapp www.myapp.com
fortress domain add myapp api.myapp.com
```

### Environment Management
```bash
fortress env set myapp API_KEY=secret
fortress env set myapp --file=.env.production
fortress env list myapp
```

### SSL Management
```bash
fortress ssl status                     # Show SSL certificate status
fortress ssl list                      # List all certificates
fortress ssl renew myapp.com           # Renew Let's Encrypt certificate
fortress ssl add cert.crt cert.key     # Add manual SSL certificate
```

### System Updates
```bash
fortress update                         # Update Fortress system
fortress update --dry-run              # Simulate update without changes
fortress update --branch develop       # Update from specific branch
fortress update verify                 # Verify system after update
fortress update backup                 # Create system backup
```

Fortress includes a comprehensive update system that provides:
- ✅ **Zero Downtime**: Applications continue running during updates
- ✅ **Automatic Backup**: Creates backup before each update
- ✅ **Rollback Support**: Quick return to previous version if needed
- ✅ **Data Preservation**: All configurations and data remain intact

For detailed update instructions, see [UPDATE.md](UPDATE.md).

### Security
```bash
fortress firewall allow 8080
fortress security status
fortress security scan
```

## Architecture
Fortress uses a simple but powerful architecture:

- **Traefik Proxy**: Handles all incoming traffic, SSL, and routing
- **Docker Compose**: Manages application containers
- **Shared Services**: PostgreSQL and Redis available to all apps
- **Monitoring Stack**: Prometheus and Grafana for observability
- **Backup System**: Automated backups with configurable retention

## Resource Usage

Typical resource usage on a 4GB RAM VPS:

- **Fortress Core**: ~500MB RAM
- **Each App**: 100–500MB RAM
- **Database**: ~200MB RAM
- **Redis**: ~100MB RAM
- **Monitoring**: ~300MB RAM

This allows hosting 10–20 small applications comfortably.

## Comparison

| Feature        | Fortress | Kubernetes | Traditional VPS | PaaS (Heroku) |
|----------------|----------|------------|------------------|----------------|
| Complexity     | Low      | High       | Medium           | Low            |
| Cost           | $20-40/mo| $100+/mo   | $20-40/mo        | $100+/mo       |
| Setup Time     | 5 minutes| Hours      | Hours            | Minutes        |
| Scalability    | Single VPS | Unlimited | Single VPS       | Unlimited      |
| Control        | Full     | Full       | Full             | Limited        |


## Best Practices
- One Database Per App: Use separate databases for isolation
- Set Resource Limits: Prevent one app from consuming all resources
- Monitor Everything: Use built-in monitoring to catch issues early
- Automate Backups: Set up daily backups with proper retention
- Use Health Checks: Ensure apps are actually working, not just running
- Keep Images Small: Use multi-stage builds and Alpine Linux

## Troubleshooting
### App Won't Start
```bash
fortress logs myapp --tail=50
fortress exec myapp -- /bin/sh
fortress health check myapp --verbose
```

### SSL Issues
```bash
fortress ssl status myapp.com
docker logs fortress_traefik
```

### Database Problems
```bash
fortress db test myapp_db
fortress logs postgres
```

## Contributing
We welcome contributions! Please see CONTRIBUTING.md for guidelines.

## Support
🐛 Issues & Bug Reports: https://github.com/marcinsdance/fortress/issues

## License
Fortress is open source software licensed under the MIT License.

---

Built with ❤️ for developers who need production deployments without the complexity.

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

### 🔒 **Automatic SSL Certificates**
- Let's Encrypt integration
- Auto-renewal
- Force HTTPS redirect
- HTTP/2 enabled

### 📊 **Built-in Monitoring**
- Prometheus metrics
- Grafana dashboards
- Health checks
- Resource tracking

### 💾 **Automated Backups**
- Scheduled backups
- Database dumps
- Volume snapshots
- Easy restoration

### 🚀 **Zero-Downtime Deployments**
- Rolling updates
- Health check validation
- Automatic rollback
- Version management

### 🛡️ **Security First**
- Automated firewall setup
- Fail2ban integration
- Security headers
- Rate limiting

### 🗄️ **Shared Services**
- PostgreSQL database
- Redis cache
- Traefik proxy
- Monitoring stack

## Quick Start

### Requirements

- Ubuntu 20.04+ or Debian 11+ VPS
- 2+ GB RAM (4-8 GB recommended)
- 20+ GB disk space
- Root or sudo access

### Installation

```bash
# One-line installer
curl -fsSL https://get.fortress.io | sudo bash

# Or clone and install manually
git clone https://github.com/your-org/fortress.git
cd fortress
sudo ./install.sh
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
# List all apps
fortress app list

# View app status
fortress app status myapp

# Update app (zero-downtime)
fortress app update myapp --image=myapp:v2

# Scale app
fortress app scale myapp 3

# Remove app
fortress app remove myapp
```

### Resource Management

```bash
# Set resource limits
fortress app limits myapp --cpu=0.5 --memory=512M

# View resource usage
fortress resources show

# Get optimization suggestions
fortress resources optimize
```

### Database Operations

```bash
# Create database
fortress db create myapp_db

# Backup database
fortress db backup myapp_db

# Restore database
fortress db restore myapp_db --from=backup.sql

# Connect to database
fortress db connect myapp_db
```

### Monitoring & Logs

```bash
# View logs
fortress logs myapp --follow

# Check health
fortress health check --all

# Open monitoring dashboard
fortress monitor dashboard

# View metrics
fortress monitor metrics myapp
```

### Backup & Restore

```bash
# Create backup
fortress backup create --full

# Schedule backups
fortress backup schedule --daily --retain=7

# List backups
fortress backup list

# Restore from backup
fortress restore myapp --date=2024-05-24
```

## Project Structure

```
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
├── services/               # Shared services
│   ├── postgres/          # PostgreSQL database
│   ├── redis/            # Redis cache
│   └── monitoring/       # Prometheus & Grafana
├── backups/              # Backup storage
└── config/              # Fortress configuration
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
# Build your app
docker build -t myapp:latest .

# Deploy with Fortress
fortress app deploy myapp \
  --domain=myapp.com \
  --port=3000 \
  --image=myapp:latest \
  --env-file=.env.production
```

### WordPress Site

```bash
fortress app deploy myblog \
  --domain=myblog.com \
  --port=80 \
  --image=wordpress:latest

# Create database
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
# Add multiple domains
fortress domain add myapp www.myapp.com
fortress domain add myapp api.myapp.com
```

### Environment Management

```bash
# Set environment variables
fortress env set myapp API_KEY=secret
fortress env set myapp --file=.env.production

# View environment
fortress env list myapp
```

### SSL Management

```bash
# Force SSL renewal
fortress ssl renew myapp.com

# Add custom certificate
fortress ssl add myapp.com --cert=cert.pem --key=key.pem
```

### Security

```bash
# Update firewall rules
fortress firewall allow 8080

# View security status
fortress security status

# Run security scan
fortress security scan
```

## Architecture

Fortress uses a simple but powerful architecture:

1. **Traefik Proxy**: Handles all incoming traffic, SSL, and routing
2. **Docker Compose**: Manages application containers
3. **Shared Services**: PostgreSQL and Redis available to all apps
4. **Monitoring Stack**: Prometheus and Grafana for observability
5. **Backup System**: Automated backups with configurable retention

## Resource Usage

Typical resource usage on a 4GB RAM VPS:

- **Fortress Core**: ~500MB RAM
- **Each App**: 100-500MB RAM (configurable)
- **Database**: ~200MB RAM
- **Redis**: ~100MB RAM
- **Monitoring**: ~300MB RAM

This allows hosting 10-20 small applications comfortably.

## Comparison

| Feature | Fortress | Kubernetes | Traditional VPS | PaaS (Heroku) |
|---------|----------|------------|-----------------|---------------|
| Complexity | Low | High | Medium | Low |
| Cost | $20-40/mo | $100+/mo | $20-40/mo | $100+/mo |
| Setup Time | 5 minutes | Hours | Hours | Minutes |
| Scalability | Single VPS | Unlimited | Single VPS | Unlimited |
| Control | Full | Full | Full | Limited |

## Best Practices

1. **One Database Per App**: Use separate databases for isolation
2. **Set Resource Limits**: Prevent one app from consuming all resources
3. **Monitor Everything**: Use built-in monitoring to catch issues early
4. **Automate Backups**: Set up daily backups with proper retention
5. **Use Health Checks**: Ensure apps are actually working, not just running
6. **Keep Images Small**: Use multi-stage builds and Alpine Linux

## Troubleshooting

### App Won't Start

```bash
# Check logs
fortress logs myapp --tail=50

# Inspect container
fortress exec myapp -- /bin/sh

# Verify health
fortress health check myapp --verbose
```

### SSL Issues

```bash
# Check certificate status
fortress ssl status myapp.com

# View Traefik logs
docker logs fortress_traefik
```

### Database Problems

```bash
# Check connection
fortress db test myapp_db

# View database logs
fortress logs postgres
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Support

- 📖 Documentation: [https://fortress.dev/docs](https://fortress.dev/docs)
- 💬 Discord: [https://discord.gg/fortress](https://discord.gg/fortress)
- 🐛 Issues: [GitHub Issues](https://github.com/your-org/fortress/issues)
- 💼 Commercial Support: support@fortress.dev

## License

Fortress is open source software licensed under the MIT License.

---

Built with ❤️ for developers who need production deployments without the complexity.
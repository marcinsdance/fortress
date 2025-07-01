# Fortress Update Instructions for Google Cloud VPS

## 🚀 Safe Update with Application Preservation

This guide will help you safely update Fortress on your Google Cloud VPS without interrupting your web applications.

## ⚠️ Important Information

- **Zero Downtime**: Applications will continue running throughout the update
- **Automatic Backup**: System automatically creates backup before update
- **Rollback**: Quick ability to return to previous version
- **Data Preservation**: All configurations and application data remain untouched

## 📋 Requirements

- Root or sudo access to the server
- Running Fortress system
- Internet connection
- At least 2GB free disk space

## 🔄 Update Process

### Step 1: Prepare Scripts

Copy update scripts to your VPS server:

```bash
# Log in to VPS
ssh root@YOUR_VPS_IP

# Create directory for scripts
mkdir -p /opt/fortress-update

# Copy scripts (you can use scp, rsync or git)
# Example with git:
cd /tmp
git clone https://github.com/marcinsdance/fortress.git
cp fortress/scripts/fortress-*.sh /opt/fortress-update/
chmod +x /opt/fortress-update/*.sh
```

### Step 2: Check Current Status

```bash
# Check application status
fortress app list

# Check running containers
docker ps

# Check current Fortress version
fortress --version
```

### Step 3: Update Simulation (Optional)

It's recommended to run a simulation before the actual update:

```bash
# Run update simulation
/opt/fortress-update/fortress-update.sh --dry-run

# Check for errors
echo $?
```

### Step 4: Create Backup

```bash
# Automatic backup (also runs during update)
/opt/fortress-update/fortress-backup.sh

# Check if backup was created
ls -la /opt/fortress/backups/system/
```

### Step 5: Update Fortress

```bash
# Standard update from main branch
/opt/fortress-update/fortress-update.sh

# Or from specific branch/version
/opt/fortress-update/fortress-update.sh --branch main

# Force update (when versions are the same)
/opt/fortress-update/fortress-update.sh --force
```

### Step 6: Post-Update Verification

```bash
# Check new version
fortress --version

# Check application status
fortress app list
fortress app status APPLICATION_NAME

# Check system logs
docker logs fortress_traefik
```

## 🔧 Advanced Options

### Update from Specific Branch

```bash
# Update from develop branch
/opt/fortress-update/fortress-update.sh --branch develop

# Update from specific tag
/opt/fortress-update/fortress-update.sh --branch v2.0.0
```

### Update Without Backup (Not Recommended)

```bash
/opt/fortress-update/fortress-update.sh --no-backup
```

### Forced Update

```bash
# When you want to update despite same version
/opt/fortress-update/fortress-update.sh --force
```

## 🚨 Troubleshooting

### Problem: Applications Not Working After Update

```bash
# Check application logs
fortress logs APPLICATION_NAME

# Restart application
cd /opt/fortress/apps/APPLICATION_NAME
docker compose restart

# Or use fortress command
fortress app restart APPLICATION_NAME
```

### Problem: Traefik Won't Start

```bash
# Check Traefik logs
docker logs fortress_traefik

# Restart Traefik
cd /opt/fortress/proxy
docker compose down
docker compose up -d
```

### Problem: SSL Issues

```bash
# Check certificates
fortress ssl status YOUR_DOMAIN

# Renew certificates
fortress ssl renew YOUR_DOMAIN
```

## 🔄 Rollback - Return to Previous Version

If you encounter problems, you can quickly return to the previous version:

```bash
# Find latest backup
ls -la /opt/fortress/backups/system/

# Restore backup (replace TIMESTAMP with actual date)
cd /opt/fortress/backups/system/
tar -xzf fortress_backup_TIMESTAMP.tar.gz

# Stop services
docker stop fortress_traefik

# Restore files
cp -r fortress_backup_TIMESTAMP/bin/* /opt/fortress/bin/
cp -r fortress_backup_TIMESTAMP/commands/* /opt/fortress/commands/
cp -r fortress_backup_TIMESTAMP/proxy/* /opt/fortress/proxy/

# Set permissions
chmod +x /opt/fortress/bin/fortress
ln -sf /opt/fortress/bin/fortress /usr/local/bin/fortress

# Restart services
cd /opt/fortress/proxy
docker compose up -d
```

## 📊 Post-Update Monitoring

### System Health Check

```bash
# Status of all applications
fortress app list

# Resource metrics
fortress resources show

# Monitoring dashboard (if enabled)
fortress monitor dashboard
```

### Log Checking

```bash
# Application logs
fortress logs APPLICATION_NAME --follow

# System logs
journalctl -u docker -f
```

## 🔒 Security

### After Update Check:

```bash
# Firewall status
fortress firewall status

# Security scan
fortress security scan

# Update fail2ban (if used)
fail2ban-client status
```

## 📝 Notes

### What Gets Preserved:
- ✅ All applications and their data
- ✅ Databases (PostgreSQL, Redis)
- ✅ SSL certificates
- ✅ Application configurations
- ✅ Traefik configurations
- ✅ Firewall settings

### What Gets Updated:
- 🔄 Fortress executable files
- 🔄 Command scripts
- 🔄 Helper utilities
- 🔄 System version

## 🆘 Support

If you encounter problems:

1. **Check logs**: `fortress logs --system`
2. **Restore backup**: Use rollback instructions above
3. **Contact**: Report issue on [GitHub Issues](https://github.com/marcinsdance/fortress/issues)

## ✅ Update Checklist

- [ ] System backup created
- [ ] Application status checked before update
- [ ] Update simulation performed
- [ ] Update completed
- [ ] Application functionality verified
- [ ] System logs checked
- [ ] Domains and SSL tested
- [ ] Monitoring system working correctly

---

**Execution Time**: ~15-30 minutes  
**Downtime**: 0 minutes for applications  
**Required Skills**: Basic Linux and Docker knowledge
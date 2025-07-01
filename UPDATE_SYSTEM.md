# Fortress Update System

## 📁 Created Files

### System Scripts
- **`scripts/fortress-backup.sh`** - Complete Fortress system backup
- **`scripts/fortress-update.sh`** - Update script preserving configurations
- **`scripts/fortress-verify.sh`** - System verification after update

### Fortress Commands
- **`commands/update.cmd`** - `fortress update` command
- **`commands/update.help`** - Help for update command

### Documentation
- **`UPDATE.md`** - Detailed update instructions
- **`UPDATE_SYSTEM.md`** - This file - system summary

## 🚀 Update System Installation

### 1. Copy files to VPS server

```bash
# Log in to server
ssh root@YOUR_VPS_IP

# Copy files (option A: via git)
cd /tmp
git clone https://github.com/marcinsdance/fortress.git
cp -r fortress/scripts /opt/fortress/
cp fortress/commands/update.* /opt/fortress/commands/
cp fortress/UPDATE.md /opt/fortress/
chmod +x /opt/fortress/scripts/*.sh
chmod +x /opt/fortress/commands/update.cmd

# Copy files (option B: via scp)
scp scripts/* root@YOUR_VPS_IP:/opt/fortress/scripts/
scp commands/update.* root@YOUR_VPS_IP:/opt/fortress/commands/
scp UPDATE.md root@YOUR_VPS_IP:/opt/fortress/
```

### 2. Update main fortress file

```bash
# Modify /opt/fortress/bin/fortress to add update command to help
# Or replace file with new version from this repository
```

## 📋 Available Commands

### `fortress update` Command

```bash
# Standard update
fortress update

# Update simulation
fortress update --dry-run

# Update from specific branch
fortress update --branch develop

# Forced update
fortress update --force

# Update without backup (not recommended)
fortress update --no-backup
```

### Additional Functions

```bash
# System verification
fortress update verify

# System backup
fortress update backup

# Version information
fortress update version
```

## 🛠️ System Features

### Automatic Backup
- Backup of all configurations
- Backup of applications and their data
- Backup of databases (PostgreSQL, Redis)
- Backup of SSL certificates
- Archiving with automatic cleanup

### Safe Update
- Zero downtime for applications
- Preservation of all data and configurations
- Compatibility check before update
- Rollback in case of problems
- Automatic verification after update

### Comprehensive Verification
- System version check
- Directory structure verification
- Docker container testing
- User application checking
- Traefik configuration test
- SSL certificate verification
- System resource checking

## 🔧 Configuration

### Backup Settings
```bash
# Backup location
BACKUP_DIR="/opt/fortress/backups/system"

# Number of backups to keep (default: 5)
# Modify in fortress-backup.sh script
```

### Update Settings
```bash
# Default update branch
UPDATE_BRANCH="main"

# Repository URL
REPO_URL="https://github.com/marcinsdance/fortress.git"
```

## 🚨 Troubleshooting

### Backup Problems
```bash
# Check permissions
ls -la /opt/fortress/backups/

# Check disk space
df -h /opt/fortress/

# Check logs
journalctl -f
```

### Update Problems
```bash
# Check GitHub connection
curl -I https://github.com/marcinsdance/fortress.git

# Check permissions
ls -la /opt/fortress/bin/

# Rollback to previous version
# Use instructions from UPDATE.md
```

### Verification Problems
```bash
# Run verification with detailed logs
/opt/fortress/scripts/fortress-verify.sh

# Check verification report
cat /tmp/fortress-verification-*.txt
```

## 📊 Monitoring

### System Logs
```bash
# Docker logs
journalctl -u docker -f

# Traefik logs
docker logs fortress_traefik -f

# Application logs
fortress logs APPLICATION_NAME -f
```

### Resource Metrics
```bash
# Resource usage
fortress resources show

# System status
fortress health check --all

# Post-update verification
fortress update verify
```

## 🔄 Update Schedule

### Recommendations
- **Monthly**: Check for available updates
- **Before update**: Full system backup
- **After update**: Verify all functions
- **Monitoring**: 24h after update

### Automation (Optional)
```bash
# Add to crontab for regular backups
0 2 * * 0 /opt/fortress/scripts/fortress-backup.sh

# Check for updates (without executing)
0 9 * * 1 /opt/fortress/scripts/fortress-update.sh --dry-run
```

## 📚 Documentation

- **UPDATE.md** - Detailed step-by-step instructions
- **fortress update commands** - Built-in help: `fortress update --help`
- **Verification logs** - Automatic reports in `/tmp/fortress-verification-*.txt`

---

**Author**: Fortress Update System  
**Version**: 1.0  
**Date**: $(date +%Y-%m-%d)  
**Compatibility**: Fortress 1.0+
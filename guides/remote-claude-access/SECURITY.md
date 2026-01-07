# Security Configuration & Hardening Guide

## Overview
This guide provides comprehensive security measures for protecting your remote Claude Code CLI access. Implement these in order of priority.

## 🔴 Critical Security Measures (Implement Immediately)

### 1. SSH Key-Only Authentication
```bash
# Disable password authentication
sudo sed -i '' 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i '' 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sudo sed -i '' 's/^#*UsePAM.*/UsePAM no/' /etc/ssh/sshd_config

# Restart SSH service
sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
```

### 2. Strong SSH Key Management
```bash
# Generate strong Ed25519 key with passphrase
ssh-keygen -t ed25519 -a 100 -C "claude-access@$(date +%Y%m%d)"

# Set correct permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

### 3. Tailscale ACL Configuration
Create `/Users/[username]/.tailscale-acl.json`:
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:mobile"],
      "dst": ["tag:workstation:22,8080"]
    }
  ],
  "tagOwners": {
    "tag:mobile": ["your-email@example.com"],
    "tag:workstation": ["your-email@example.com"]
  }
}
```

## 🟡 Important Security Measures

### 4. SSH Hardening Configuration
Add to `/etc/ssh/sshd_config`:
```bash
# Security hardening
Protocol 2
PermitRootLogin no
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
PermitEmptyPasswords no
X11Forwarding no
IgnoreRhosts yes
HostbasedAuthentication no
AllowUsers [your-username]

# Only allow specific key types
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
PubkeyAcceptedKeyTypes ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# Logging
LogLevel VERBOSE
```

### 5. Fail2Ban Installation
```bash
# Install fail2ban
brew install fail2ban

# Configure for SSH protection
cat > /usr/local/etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[ssh]
enabled = true
port = 22
filter = sshd
logpath = /var/log/system.log
backend = auto
EOF

# Start fail2ban
brew services start fail2ban
```

### 6. GoTTY Security Hardening
Update `~/.gotty` with:
```ini
# Enhanced security settings
enable_basic_auth = true
credential = ""  # Use external auth instead

# Use random URL token
random_url = true
random_url_length = 32

# Limit connections
max_connection = 2
once = false

# Session timeout
timeout = 1800  # 30 minutes

# Restrict write access initially
permit_write = false
```

## 🟢 Best Practices

### 7. Regular Security Audits
Create `/Users/[username]/remote-claude-code-access/security-audit.sh`:
```bash
#!/bin/bash

echo "🔍 Security Audit Report - $(date)"
echo "================================"

# Check SSH configuration
echo -e "\n📋 SSH Configuration:"
grep -E "^(PasswordAuthentication|PermitRootLogin|PubkeyAuthentication)" /etc/ssh/sshd_config

# Check active SSH connections
echo -e "\n👥 Active SSH Connections:"
who | grep -E "pts|ttys"

# Check failed login attempts
echo -e "\n❌ Recent Failed Logins (last 24h):"
log show --predicate 'process == "sshd" AND messageType == error' --last 1d | tail -20

# Check listening ports
echo -e "\n🔌 Listening Ports:"
lsof -i -P | grep LISTEN

# Check Tailscale status
echo -e "\n🔐 Tailscale Status:"
tailscale status

# Check tmux sessions
echo -e "\n📺 Active tmux Sessions:"
tmux list-sessions 2>/dev/null || echo "No active sessions"

# File integrity check
echo -e "\n📁 Configuration File Integrity:"
shasum -a 256 ~/.ssh/authorized_keys
shasum -a 256 ~/.tmux.conf
shasum -a 256 ~/.gotty

# Check for suspicious processes
echo -e "\n⚠️  Unusual Processes:"
ps aux | grep -E "(nc|netcat|ncat)" | grep -v grep
```

### 8. Automated Security Monitoring
```bash
# Create monitoring script
cat > ~/remote-claude-code-access/monitor.sh << 'EOF'
#!/bin/bash

LOG_FILE="$HOME/remote-claude-code-access/security.log"

# Monitor SSH access
monitor_ssh() {
    echo "[$(date)] SSH Connection from: $(who | tail -1)" >> "$LOG_FILE"
}

# Monitor Claude Code sessions
monitor_claude() {
    active_sessions=$(tmux list-sessions 2>/dev/null | grep claude | wc -l)
    echo "[$(date)] Active Claude sessions: $active_sessions" >> "$LOG_FILE"
}

# Alert on suspicious activity
check_suspicious() {
    # Check for multiple failed login attempts
    failed_attempts=$(log show --predicate 'process == "sshd"' --last 1h | grep -c "Failed")
    if [ "$failed_attempts" -gt 5 ]; then
        echo "[$(date)] ALERT: $failed_attempts failed SSH attempts in last hour" >> "$LOG_FILE"
        # Send notification (requires terminal-notifier)
        terminal-notifier -title "Security Alert" -message "$failed_attempts failed SSH attempts"
    fi
}

# Run monitors
monitor_ssh
monitor_claude
check_suspicious
EOF

# Add to crontab for regular monitoring
(crontab -l 2>/dev/null; echo "*/5 * * * * $HOME/remote-claude-code-access/monitor.sh") | crontab -
```

### 9. iOS-Specific Security

#### Blink Shell Security
```bash
# In Blink Shell settings:
# 1. Enable Face ID/Touch ID
# 2. Set app lock timeout to 1 minute
# 3. Enable "Erase Data" after 10 failed attempts
# 4. Use hardware keys when possible
```

#### iOS Shortcuts Security
- Never store passwords in shortcuts
- Use Face ID for shortcut execution
- Avoid sharing shortcuts with credentials

### 10. Emergency Response Plan

Create `/Users/[username]/remote-claude-code-access/emergency-lockdown.sh`:
```bash
#!/bin/bash

echo "🚨 EMERGENCY LOCKDOWN INITIATED"

# Kill all Claude sessions
tmux kill-server

# Stop SSH service
sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist

# Stop GoTTY
pkill -f gotty

# Revoke Tailscale access
tailscale down

# Clear authorized_keys (backup first)
cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup.$(date +%Y%m%d)
> ~/.ssh/authorized_keys

echo "✅ Lockdown complete. Services stopped and access revoked."
echo "To restore: Review security, update credentials, then restart services"
```

## 🔐 Security Checklist

- [ ] SSH password authentication disabled
- [ ] Strong SSH keys with passphrase
- [ ] Tailscale ACLs configured
- [ ] SSH configuration hardened
- [ ] Fail2ban installed and configured
- [ ] GoTTY using HTTPS with strong auth
- [ ] Regular security audits scheduled
- [ ] Monitoring scripts in place
- [ ] iOS app security enabled
- [ ] Emergency response plan tested

## 📊 Monitoring & Logging

### Real-time Monitoring Dashboard
```bash
# Create monitoring dashboard
cat > ~/remote-claude-code-access/dashboard.sh << 'EOF'
#!/bin/bash

while true; do
    clear
    echo "🔒 Claude Code Remote Access Security Dashboard"
    echo "================================================"
    echo "Time: $(date)"
    echo ""
    
    echo "📡 Network Status:"
    tailscale status | head -5
    echo ""
    
    echo "👥 Active Connections:"
    who
    echo ""
    
    echo "📺 Claude Sessions:"
    tmux list-sessions 2>/dev/null | grep claude || echo "No active sessions"
    echo ""
    
    echo "🚨 Recent Security Events:"
    tail -5 ~/remote-claude-code-access/security.log 2>/dev/null
    echo ""
    
    echo "🔌 Port Status:"
    lsof -i :22,8080 | grep LISTEN
    
    sleep 5
done
EOF

chmod +x ~/remote-claude-code-access/dashboard.sh
```

## 🎯 Quick Security Commands

```bash
# Check who's connected
who

# View SSH logs
sudo log show --predicate 'process == "sshd"' --last 1h

# Kill specific session
tmux kill-session -t claude-main

# Emergency disconnect all
tmux kill-server && pkill sshd

# Check network connections
netstat -an | grep ESTABLISHED

# Verify file integrity
shasum -c ~/.ssh/checksums.txt
```

## 📝 Security Maintenance Schedule

### Daily
- Review active connections
- Check security logs

### Weekly
- Run security audit script
- Update software packages
- Review failed login attempts

### Monthly
- Rotate SSH keys
- Update passwords/credentials
- Test emergency lockdown procedure
- Review and update ACLs

### Quarterly
- Full security assessment
- Update this documentation
- Review and update security policies
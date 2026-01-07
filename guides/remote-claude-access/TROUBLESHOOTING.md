# Troubleshooting Guide for Remote Claude Code Access

## Quick Diagnostics Script

```bash
#!/bin/bash
# Save as: diagnose.sh

echo "🔍 Running diagnostics..."

# Check all components
checks=(
    "Tailscale:tailscale status"
    "SSH:ssh -o ConnectTimeout=3 localhost echo OK"
    "Tmux:tmux list-sessions"
    "Claude:which claude"
    "GoTTY:pgrep gotty"
    "Mosh:which mosh-server"
)

for check in "${checks[@]}"; do
    IFS=':' read -r name cmd <<< "$check"
    printf "%-15s" "$name:"
    if eval "$cmd" &>/dev/null; then
        echo "✅ OK"
    else
        echo "❌ Failed"
    fi
done
```

## Common Issues & Solutions

### 🔴 Cannot Connect from iPhone

#### Issue: "Connection refused" error
```bash
# Solution 1: Check if SSH is running
sudo systemsetup -getremotelogin
# If "Off", enable it:
sudo systemsetup -setremotelogin on

# Solution 2: Check Tailscale connection
tailscale ping $(tailscale status | grep iPhone | awk '{print $1}')

# Solution 3: Verify firewall settings
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
# If enabled, add SSH exception:
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/sbin/sshd
```

#### Issue: "Host key verification failed"
```bash
# Solution: Clear known hosts entry
ssh-keygen -R [tailscale-ip]
# Or remove the entire known_hosts file (use with caution)
rm ~/.ssh/known_hosts
```

#### Issue: Tailscale not connecting
```bash
# Solution 1: Restart Tailscale
tailscale down
tailscale up

# Solution 2: Re-authenticate
tailscale logout
tailscale up

# Solution 3: Check DNS
scutil --dns | grep -A5 "resolver #1"
# If issues, reset DNS:
sudo dscacheutil -flushcache
```

### 🟡 Claude Code CLI Issues

#### Issue: "claude: command not found"
```bash
# Solution 1: Check if Claude is in PATH
echo $PATH
which claude

# Solution 2: Add to PATH in shell config
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Solution 3: Create alias
echo 'alias claude="/path/to/claude"' >> ~/.zshrc
```

#### Issue: Claude session hangs or freezes
```bash
# Solution 1: Kill and restart session
tmux kill-session -t claude-main
tmux new-session -d -s claude-main "claude code"

# Solution 2: Clear Claude cache
rm -rf ~/.claude/cache/*

# Solution 3: Check system resources
top -l 1 | head -10
# If high CPU/memory, restart Claude
pkill -f claude
```

#### Issue: "API rate limit exceeded"
```bash
# Solution: Wait and implement rate limiting
# Add delay between commands in your scripts:
sleep 2  # Add 2-second delay between API calls
```

### 🟢 Tmux Session Problems

#### Issue: "no server running on /tmp/tmux-501/default"
```bash
# Solution: Start tmux server
tmux start-server
tmux new-session -d -s claude-main

# If persists, check socket permissions:
ls -la /tmp/tmux-$(id -u)/
# Fix permissions:
chmod 700 /tmp/tmux-$(id -u)/
```

#### Issue: Sessions disappear after reboot
```bash
# Solution 1: Install tmux-resurrect
git clone https://github.com/tmux-plugins/tmux-resurrect ~/.tmux/plugins/tmux-resurrect

# Solution 2: Create auto-start script
cat > ~/Library/LaunchAgents/com.claude.tmux.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.tmux</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/tmux</string>
        <string>new-session</string>
        <string>-d</string>
        <string>-s</string>
        <string>claude-main</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.claude.tmux.plist
```

#### Issue: Can't scroll in tmux
```bash
# Solution: Enter copy mode
# Press: Ctrl-A [
# Navigate with arrow keys
# Exit with: q

# Or enable mouse scrolling:
echo "set -g mouse on" >> ~/.tmux.conf
tmux source ~/.tmux.conf
```

### 🔵 Blink Shell Specific Issues

#### Issue: Mosh connection drops frequently
```bash
# Solution 1: Increase keep-alive interval
# In Blink host settings, add to RemoteCommand:
mosh-server new -p 60000:60010 -- tmux attach

# Solution 2: Check UDP ports
sudo pfctl -s rules | grep 60000

# Solution 3: Use SSH fallback
# In Blink, disable Mosh for the host temporarily
```

#### Issue: "Permission denied (publickey)"
```bash
# Solution 1: Verify key is added
ssh-add -l

# Solution 2: Check key permissions
ls -la ~/.ssh/
# Fix if needed:
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/*.pub

# Solution 3: Verify authorized_keys
cat ~/.ssh/authorized_keys
# Ensure your Blink key is present
```

#### Issue: Keyboard shortcuts not working
```
Solution: Blink keyboard mapping
1. In Blink: Settings → Keyboard
2. Enable "Send ESC as Meta"
3. Map Caps Lock to Control (optional)
4. Use external keyboard profile if applicable
```

### 🟣 GoTTY Web Access Issues

#### Issue: Certificate warning in Safari
```bash
# Solution 1: Accept certificate permanently
# In Safari: Advanced → Show Develop menu
# Develop → Disable certificate validation (temporary)

# Solution 2: Add certificate to keychain
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain ~/.gotty/server.crt

# Solution 3: Use Let's Encrypt (production)
brew install certbot
sudo certbot certonly --standalone -d your-domain.com
```

#### Issue: GoTTY performance is slow
```bash
# Solution 1: Reduce terminal size
# Edit ~/.gotty:
width = 80
height = 24

# Solution 2: Disable WebGL
enable_webgl = false

# Solution 3: Use compression
# Add to nginx config:
gzip on;
gzip_types application/javascript text/css;
```

### 🔧 Network & Performance Issues

#### Issue: High latency on cellular connection
```bash
# Solution 1: Use mosh instead of SSH
mosh claude-mbp

# Solution 2: Enable compression
ssh -C claude-mbp

# Solution 3: Reduce MTU size
sudo ifconfig en0 mtu 1400
```

#### Issue: "Broken pipe" errors
```bash
# Solution: Configure keep-alive
# Add to ~/.ssh/config:
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes

# For tmux:
set -g status-interval 60
```

## Performance Optimization

### Speed Test Script
```bash
#!/bin/bash
# Save as: speed-test.sh

echo "🏃 Testing connection speed..."

# Test SSH latency
echo -n "SSH Latency: "
time ssh claude-mbp echo "test" 2>&1 | grep real

# Test tmux responsiveness
echo -n "Tmux Response: "
time tmux list-sessions 2>&1 | grep real

# Test Claude CLI
echo -n "Claude CLI: "
time claude --version 2>&1 | grep real

# Network throughput
echo "Network Speed:"
iperf3 -c $(tailscale ip -4) -t 5 -f M
```

### Optimization Checklist
- [ ] Mosh enabled for mobile connections
- [ ] Compression enabled for SSH
- [ ] Tmux buffer optimized (10000 lines max)
- [ ] GoTTY WebGL disabled for slow devices
- [ ] Tailscale using nearest DERP server
- [ ] DNS using fast resolver (1.1.1.1)

## Log Files & Debugging

### Important Log Locations
```bash
# SSH logs
/var/log/system.log  # macOS system log
sudo log show --predicate 'process == "sshd"' --last 1h

# Tailscale logs
tailscale bugreport  # Generates debug bundle

# Tmux logs
tmux show-messages

# GoTTY logs
~/.gotty/gotty.log
~/.gotty/gotty.error.log

# Claude logs
~/.claude/logs/
```

### Debug Mode Commands
```bash
# SSH verbose mode
ssh -vvv claude-mbp

# Tmux debug
tmux -vvv new-session

# Tailscale debug
tailscale debug

# Network trace
sudo tcpdump -i any -n host $(tailscale ip -4)
```

## Recovery Procedures

### Complete System Reset
```bash
#!/bin/bash
# Save as: reset.sh

echo "⚠️  Resetting remote access system..."

# Stop all services
tmux kill-server
pkill gotty
tailscale down

# Backup configurations
mkdir -p ~/claude-backup-$(date +%Y%m%d)
cp -r ~/.ssh ~/claude-backup-$(date +%Y%m%d)/
cp ~/.tmux.conf ~/claude-backup-$(date +%Y%m%d)/
cp ~/.gotty ~/claude-backup-$(date +%Y%m%d)/

# Reset configurations
rm ~/.ssh/known_hosts
rm -rf ~/.tmux/resurrect

# Restart services
tailscale up
tmux start-server

echo "✅ Reset complete. Please reconfigure your connections."
```

## Getting Help

### Diagnostic Information to Collect
When seeking help, run this script and share the output:
```bash
#!/bin/bash
# Save as: collect-diagnostics.sh

echo "Collecting diagnostic information..."

{
    echo "=== System Info ==="
    uname -a
    sw_vers
    
    echo -e "\n=== Network Status ==="
    tailscale status
    ifconfig | grep -A1 "en0\|utun"
    
    echo -e "\n=== Service Status ==="
    ps aux | grep -E "(sshd|tmux|gotty|claude)" | grep -v grep
    
    echo -e "\n=== Port Status ==="
    lsof -i :22,8080,60000-61000 | grep LISTEN
    
    echo -e "\n=== Recent Errors ==="
    sudo log show --predicate 'messageType == error' --last 1h | tail -20
    
    echo -e "\n=== Configuration Checksums ==="
    shasum ~/.ssh/config ~/.tmux.conf ~/.gotty 2>/dev/null
} > diagnostic-report-$(date +%Y%m%d-%H%M%S).txt

echo "Report saved to diagnostic-report-*.txt"
```

### Support Resources
- Tailscale Support: https://tailscale.com/contact/support
- Blink Shell Discord: https://discord.gg/blink
- Tmux IRC: #tmux on Libera.Chat
- Claude Code Issues: https://github.com/anthropics/claude-code/issues

### Emergency Contacts
Keep these commands handy for emergencies:
```bash
# Kill everything
pkill -f "(sshd|tmux|gotty|claude)"

# Disable remote access
sudo systemsetup -setremotelogin off

# Lock down Tailscale
tailscale down

# Restore from backup
cp ~/claude-backup-*/.[!.]* ~/
```
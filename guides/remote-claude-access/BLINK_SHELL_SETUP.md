# Blink Shell Configuration Guide for Claude Code CLI

## Prerequisites
- Blink Shell installed on iPhone ($19.99/year from App Store)
- Tailscale configured on both devices
- SSH keys generated

## Step 1: Generate SSH Keys on iPhone

1. Open Blink Shell
2. Type `config` to enter configuration
3. Navigate to **Keys** → **+** (Add new key)
4. Name: `claude-mbp`
5. Type: `Ed25519` (recommended) or `RSA 4096`
6. Tap **Generate**
7. Copy the public key (tap and hold → Copy)

## Step 2: Add iPhone's Public Key to MacBook

On your MacBook, run:
```bash
# Add the public key to authorized_keys
echo "YOUR_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys

# Set correct permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

## Step 3: Configure Blink Shell Host

1. In Blink Shell, type `config`
2. Navigate to **Hosts** → **+** (Add new host)
3. Configure as follows:

```
Alias: claude-mbp
Hostname: [Your Tailscale IP or hostname]
Port: 22
User: [Your macOS username]
Key: claude-mbp
Mosh: ON (Enable for better mobile experience)
Mosh Port: Dynamic
Compression: ON
```

## Step 4: Advanced Settings (Optional but Recommended)

In the host configuration, tap **Advanced**:

```
ProxyCommand: (leave empty)
RemoteCommand: /Users/[username]/remote-claude-code-access/claude-session.sh quickstart
LocalForward: (leave empty)
RemoteForward: (leave empty)
SendEnv: LANG LC_*
ServerAliveInterval: 60
ServerAliveCountMax: 3
TCPKeepAlive: yes
```

## Step 5: Mosh Installation (for Better Mobile Experience)

On your MacBook:
```bash
# Install mosh
brew install mosh

# Mosh uses UDP ports 60000-61000
# These are automatically handled by Tailscale
```

## Step 6: Quick Connect Shortcuts

### Method 1: Blink Shell Shortcuts
1. In Blink, swipe down from top
2. Tap **Shortcuts** → **+**
3. Create shortcuts:
   - Name: "Claude Main"
   - Command: `ssh claude-mbp -t "/Users/[username]/remote-claude-code-access/claude-session.sh attach main"`
   
   - Name: "Claude New"
   - Command: `ssh claude-mbp -t "/Users/[username]/remote-claude-code-access/claude-session.sh new"`

### Method 2: iOS Shortcuts App Integration
1. Open iOS Shortcuts app
2. Create new shortcut
3. Add action: **Open App** → Blink Shell
4. Add action: **Text** → `mosh claude-mbp -- /Users/[username]/remote-claude-code-access/claude-session.sh quickstart`
5. Add action: **Copy to Clipboard**
6. Name: "Claude Code Remote"
7. Add to Home Screen

## Step 7: First Connection Test

1. Open Blink Shell
2. Type: `mosh claude-mbp`
3. You should connect to your MacBook
4. Run: `claude-session.sh quickstart`

## Keyboard Shortcuts in Blink

- **Cmd+T**: New tab
- **Cmd+1,2,3...**: Switch tabs
- **Cmd+W**: Close tab
- **Cmd+K**: Clear screen
- **Cmd+,**: Settings
- **Cmd+O**: Snippets/Clips
- **Ctrl+A**: Tmux prefix (after connection)

## Troubleshooting

### Connection Issues
```bash
# Test basic SSH
ssh claude-mbp

# Test with verbose output
ssh -vvv claude-mbp

# Check Tailscale connection
tailscale ping [hostname]
```

### Mosh Not Working
```bash
# Check mosh server on MacBook
which mosh-server

# Test mosh directly
mosh --server=/usr/local/bin/mosh-server claude-mbp

# Fallback to SSH
ssh claude-mbp
```

### Session Not Found
```bash
# List all tmux sessions
tmux ls

# Create new Claude session manually
tmux new-session -s claude-main "claude code"
```

## Performance Optimization

### Blink Settings
1. **Config** → **Appearance** → **Font Size**: 12-14 (optimal for iPhone)
2. **Config** → **Keyboard** → **External Keyboard**: Configure if using
3. **Config** → **Terminal** → **Buffer Size**: 10000 lines

### Network Settings
- Use 5GHz Wi-Fi when possible
- Enable Tailscale's MagicDNS for faster resolution
- Consider using Cloudflare's 1.1.1.1 DNS

## Security Best Practices

1. **Use Ed25519 keys** (faster and more secure than RSA)
2. **Enable Face ID** for Blink Shell (Settings → Security)
3. **Set key passphrase** for additional security
4. **Regular key rotation** (every 6-12 months)
5. **Monitor access logs**:
   ```bash
   # On MacBook, check SSH logs
   sudo log show --predicate 'process == "sshd"' --last 1d
   ```

## Quick Reference Card

```
# Connect to Claude
mosh claude-mbp

# Quick start Claude session
claude-session.sh quickstart

# List sessions
claude-session.sh list

# Attach to existing
claude-session.sh attach [name]

# Create new session
claude-session.sh new [name]

# Tmux shortcuts (after connection)
Ctrl-A c    → New window
Ctrl-A n    → Next window
Ctrl-A p    → Previous window
Ctrl-A d    → Detach session
Ctrl-A [    → Scroll mode (q to exit)
```
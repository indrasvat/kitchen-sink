#!/bin/bash
# GoTTY Web-Based Terminal Setup for Claude Code CLI
# Alternative solution for browser-based access

set -e

echo "🌐 Setting up GoTTY for web-based Claude Code access..."

# Check if Go is installed (required for building from source)
if ! command -v go &> /dev/null; then
    echo "📦 Installing Go..."
    brew install go
fi

# Install GoTTY
if ! command -v gotty &> /dev/null; then
    echo "📦 Installing GoTTY..."
    # Try homebrew first
    if command -v brew &> /dev/null; then
        brew install gotty
    else
        # Build from source
        go install github.com/yudai/gotty@latest
        export PATH=$PATH:$(go env GOPATH)/bin
    fi
fi

# Create GoTTY configuration file
CONFIG_FILE="$HOME/.gotty"
echo "📝 Creating GoTTY configuration..."
cat > "$CONFIG_FILE" << 'EOF'
# GoTTY Configuration for Claude Code CLI

# Server settings
port = "8080"
address = "0.0.0.0"

# Security settings
enable_basic_auth = true
credential = "claude:ChangeMeNow123!"  # CHANGE THIS!

# TLS/HTTPS settings (recommended)
enable_tls = true
tls_crt_file = "~/.gotty/server.crt"
tls_key_file = "~/.gotty/server.key"

# Terminal settings
term = "xterm-256color"
enable_reconnect = true
reconnect_time = 10
max_connection = 5
once = false
timeout = 0
width = 120
height = 40

# Client options
enable_webgl = true
title_format = "Claude Code CLI - {{ .Hostname }}"

# Security options
permit_write = true
close_signal = 1
preferences = {
    "fontFamily": "Menlo, Monaco, 'Courier New', monospace",
    "fontSize": 14,
    "cursorBlink": true,
    "scrollback": 10000,
    "theme": {
        "background": "#1e1e1e",
        "foreground": "#cccccc",
        "cursor": "#ffffff",
        "selection": "#3a3d41"
    }
}
EOF

# Create certificate directory
mkdir -p "$HOME/.gotty"

# Generate self-signed certificate for HTTPS
echo "🔐 Generating self-signed certificate for HTTPS..."
openssl req -x509 -newkey rsa:4096 -keyout "$HOME/.gotty/server.key" \
    -out "$HOME/.gotty/server.crt" -days 365 -nodes -subj \
    "/C=US/ST=State/L=City/O=Personal/CN=claude-code.local"

# Create systemd-style launch agent for macOS
PLIST_FILE="$HOME/Library/LaunchAgents/com.claude.gotty.plist"
echo "🚀 Creating launch agent..."
cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.gotty</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which gotty)</string>
        <string>-c</string>
        <string>$HOME/.gotty</string>
        <string>tmux</string>
        <string>attach-session</string>
        <string>-t</string>
        <string>claude-main</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.gotty/gotty.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.gotty/gotty.error.log</string>
</dict>
</plist>
EOF

# Create start/stop scripts
cat > "$HOME/remote-claude-code-access/gotty-start.sh" << 'EOF'
#!/bin/bash
# Start GoTTY service

# Ensure tmux session exists
if ! tmux has-session -t claude-main 2>/dev/null; then
    tmux new-session -d -s claude-main "claude code"
fi

# Start GoTTY
gotty -c ~/.gotty \
    --width 120 \
    --height 40 \
    --permit-write \
    --reconnect \
    --reconnect-time 10 \
    --title-format "Claude Code - {{ .Hostname }}" \
    tmux attach-session -t claude-main
EOF

cat > "$HOME/remote-claude-code-access/gotty-stop.sh" << 'EOF'
#!/bin/bash
# Stop GoTTY service

# Find and kill GoTTY process
pkill -f gotty
echo "GoTTY service stopped"
EOF

chmod +x "$HOME/remote-claude-code-access/gotty-start.sh"
chmod +x "$HOME/remote-claude-code-access/gotty-stop.sh"

# Create nginx reverse proxy configuration (optional, for better security)
cat > "$HOME/remote-claude-code-access/nginx-gotty.conf" << 'EOF'
# Nginx configuration for GoTTY reverse proxy
# Install nginx: brew install nginx

server {
    listen 443 ssl http2;
    server_name claude-code.local;

    ssl_certificate /Users/[username]/.gotty/server.crt;
    ssl_certificate_key /Users/[username]/.gotty/server.key;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Basic authentication
    auth_basic "Claude Code CLI";
    auth_basic_user_file /Users/[username]/.gotty/.htpasswd;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

# Create htpasswd file for basic authentication
echo "🔐 Setting up authentication..."
htpasswd -bc "$HOME/.gotty/.htpasswd" claude "ChangeMeNow123!"

echo "
✅ GoTTY setup complete!

🌐 Web Access Configuration:
─────────────────────────────────────
Local URL: https://localhost:8080
Tailscale URL: https://[your-tailscale-ip]:8080
Credentials: claude / ChangeMeNow123!

⚠️  IMPORTANT SECURITY STEPS:
1. Change the default password in ~/.gotty
2. Update ~/.gotty/.htpasswd with new password:
   htpasswd -b ~/.gotty/.htpasswd claude YOUR_NEW_PASSWORD

📱 iOS Safari Access:
1. Open Safari on iPhone
2. Navigate to: https://[your-tailscale-ip]:8080
3. Accept certificate warning (first time only)
4. Enter credentials
5. You now have full terminal access!

🚀 Quick Start Commands:
─────────────────────────────────────
Start service:  ./gotty-start.sh
Stop service:   ./gotty-stop.sh
Check status:   ps aux | grep gotty

📦 Launch at startup (optional):
launchctl load ~/Library/LaunchAgents/com.claude.gotty.plist

🔧 Troubleshooting:
─────────────────────────────────────
View logs:      tail -f ~/.gotty/gotty.log
Test locally:   curl -k https://localhost:8080
Check port:     lsof -i :8080

💡 Pro Tips:
- Add to iOS home screen for app-like experience
- Use landscape mode for better visibility
- Enable 'Desktop Website' in Safari for full features
- Consider using a reverse proxy for additional security
"
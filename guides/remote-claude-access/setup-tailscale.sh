#!/bin/bash
# Tailscale Setup Script for Claude Code CLI Remote Access
# Run this on your MacBook Pro

set -e

echo "🚀 Setting up Tailscale for secure remote access..."

# Check if Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    echo "📦 Installing Tailscale..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS installation
        brew install tailscale
    else
        echo "❌ Please install Tailscale manually from https://tailscale.com/download"
        exit 1
    fi
fi

# Start Tailscale
echo "🔧 Starting Tailscale..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # On macOS, Tailscale runs as an app
    open -a Tailscale
    echo "⏳ Please complete the Tailscale login in the menu bar app"
    echo "Press Enter when you've logged in..."
    read
fi

# Get Tailscale status
tailscale status

# Enable SSH
echo "🔐 Configuring SSH access..."
sudo tailscale up --ssh

# Get the Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
echo "✅ Your Tailscale IP: $TAILSCALE_IP"

# Create SSH config entry
SSH_CONFIG="$HOME/.ssh/config"
if ! grep -q "Host claude-mbp" "$SSH_CONFIG" 2>/dev/null; then
    echo "📝 Adding SSH config entry..."
    cat >> "$SSH_CONFIG" << EOF

# Claude Code CLI Remote Access via Tailscale
Host claude-mbp
    HostName $TAILSCALE_IP
    User $(whoami)
    Port 22
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
EOF
fi

# Ensure SSH is enabled on macOS
echo "🔧 Enabling SSH on macOS..."
sudo systemsetup -setremotelogin on 2>/dev/null || true
sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true

echo "
✅ Tailscale setup complete!

📱 Next steps for your iPhone:
1. Install Tailscale from the App Store
2. Log in with the same account
3. Your MacBook will appear as '$(hostname -s)'
4. Tailscale IP: $TAILSCALE_IP

🔐 Security notes:
- Only devices on your Tailscale network can connect
- SSH is key-only authentication by default
- All traffic is end-to-end encrypted via WireGuard
"
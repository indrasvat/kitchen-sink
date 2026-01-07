#!/bin/bash
# Automated Termius Setup Script for MacBook
# Run this to prepare your Mac for Termius connections

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Termius Setup for Claude Code CLI${NC}"
echo "======================================"
echo ""

# Step 1: Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"

# Check Tailscale
if ! command -v tailscale &> /dev/null; then
    echo -e "${RED}❌ Tailscale not found${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Tailscale installed${NC}"
fi

# Check tmux
if ! command -v tmux &> /dev/null; then
    echo -e "${RED}❌ tmux not found${NC}"
    exit 1
else
    echo -e "${GREEN}✅ tmux installed${NC}"
fi

# Check mosh
if ! command -v mosh-server &> /dev/null; then
    echo -e "${YELLOW}⚠️  mosh not found (optional but recommended)${NC}"
    read -p "Install mosh for better mobile experience? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        brew install mosh
    fi
else
    echo -e "${GREEN}✅ mosh installed${NC}"
fi

echo ""

# Step 2: Get Tailscale info
echo -e "${BLUE}Step 2: Getting your Tailscale information...${NC}"

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "Not connected")
TAILSCALE_NAME=$(tailscale status 2>/dev/null | grep $(hostname -s) | awk '{print $2}' || echo "Unknown")
MAC_USERNAME=$(whoami)

echo -e "Tailscale IP: ${GREEN}$TAILSCALE_IP${NC}"
echo -e "Tailscale Name: ${GREEN}$TAILSCALE_NAME${NC}"
echo -e "Mac Username: ${GREEN}$MAC_USERNAME${NC}"
echo ""

# Step 3: Enable SSH
echo -e "${BLUE}Step 3: Enabling SSH access...${NC}"

if sudo systemsetup -getremotelogin 2>/dev/null | grep -q "Off"; then
    echo "SSH is currently disabled. Enabling..."
    sudo systemsetup -setremotelogin on
    echo -e "${GREEN}✅ SSH enabled${NC}"
else
    echo -e "${GREEN}✅ SSH already enabled${NC}"
fi

# Enable SSH through Tailscale
echo "Enabling SSH through Tailscale..."
sudo tailscale up --ssh 2>/dev/null || true
echo ""

# Step 4: Setup SSH directory
echo -e "${BLUE}Step 4: Setting up SSH configuration...${NC}"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

if [ ! -f ~/.ssh/authorized_keys ]; then
    touch ~/.ssh/authorized_keys
    echo -e "${GREEN}✅ Created authorized_keys file${NC}"
else
    echo -e "${GREEN}✅ authorized_keys file exists${NC}"
fi

chmod 600 ~/.ssh/authorized_keys
echo ""

# Step 5: Copy tmux config
echo -e "${BLUE}Step 5: Installing tmux configuration...${NC}"

if [ -f .tmux.conf ]; then
    cp .tmux.conf ~/.tmux.conf
    echo -e "${GREEN}✅ tmux configuration installed${NC}"
else
    echo -e "${YELLOW}⚠️  tmux config not found in current directory${NC}"
fi
echo ""

# Step 6: Create Claude startup script
echo -e "${BLUE}Step 6: Setting up Claude startup script...${NC}"

if [ -f ~/start-claude.sh ]; then
    echo -e "${GREEN}✅ start-claude.sh already exists${NC}"
else
    echo -e "${YELLOW}Creating start-claude.sh...${NC}"
    cp "$(dirname "$0")/start-claude.sh" ~/start-claude.sh 2>/dev/null || {
        # If copy fails, create it
        cat > ~/start-claude.sh << 'EOF'
#!/bin/bash
SESSION_NAME="claude-main"
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    exec tmux attach-session -t $SESSION_NAME
else
    tmux new-session -s $SESSION_NAME -n main "claude code"
fi
EOF
    }
    chmod +x ~/start-claude.sh
    echo -e "${GREEN}✅ start-claude.sh created${NC}"
fi
echo ""

# Step 7: Test Claude CLI
echo -e "${BLUE}Step 7: Testing Claude Code CLI...${NC}"

if command -v claude &> /dev/null; then
    echo -e "${GREEN}✅ Claude Code CLI found${NC}"
    claude --version 2>/dev/null || true
else
    echo -e "${RED}❌ Claude Code CLI not found${NC}"
    echo "Please install Claude Code CLI first"
fi
echo ""

# Step 8: Create initial tmux session
echo -e "${BLUE}Step 8: Creating initial Claude session...${NC}"

if tmux has-session -t claude-main 2>/dev/null; then
    echo -e "${GREEN}✅ claude-main session already exists${NC}"
else
    echo "Creating claude-main session..."
    tmux new-session -d -s claude-main "claude code" 2>/dev/null || true
    echo -e "${GREEN}✅ claude-main session created${NC}"
fi
echo ""

# Step 9: Show Termius configuration
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Setup Complete! Here's your Termius configuration:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Add this to Termius on your iPhone:${NC}"
echo ""
echo "┌─────────────────────────────────────────┐"
echo "│ ${BLUE}Connection Settings:${NC}                   │"
echo "├─────────────────────────────────────────┤"
echo "│ Label: Claude Code                      │"
echo "│ Address: $TAILSCALE_IP          │"
echo "│    (or: $TAILSCALE_NAME)        │"
echo "│ Port: 22                                │"
echo "│ Username: $MAC_USERNAME                 │"
echo "└─────────────────────────────────────────┘"
echo ""
echo "┌─────────────────────────────────────────┐"
echo "│ ${BLUE}Advanced Settings:${NC}                     │"
echo "├─────────────────────────────────────────┤"
echo "│ Startup Command:                        │"
echo "│   /Users/$MAC_USERNAME/start-claude.sh  │"
echo "│                                         │"
echo "│ Mosh: ON                                │"
echo "│ Mosh Server Path:                       │"
echo "│   $(which mosh-server 2>/dev/null || echo "/usr/local/bin/mosh-server")     │"
echo "└─────────────────────────────────────────┘"
echo ""
echo -e "${RED}IMPORTANT NEXT STEPS:${NC}"
echo "1. Generate an SSH key in Termius (Settings → Keychain → Generate)"
echo "2. Copy the public key from Termius"
echo "3. Add it to this Mac with:"
echo -e "   ${GREEN}echo 'YOUR_PUBLIC_KEY' >> ~/.ssh/authorized_keys${NC}"
echo ""
echo -e "${YELLOW}To verify everything is working, run:${NC}"
echo -e "   ${GREEN}./verify-termius-setup.sh${NC}"
echo ""
echo -e "${BLUE}Happy coding with Claude from your iPhone! 🚀${NC}"
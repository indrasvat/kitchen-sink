#!/bin/bash
# Termius Setup Verification Script
# This checks that everything is properly configured for Termius access

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Termius Setup Verification Script${NC}"
echo "====================================="
echo ""

# Track if everything is working
ALL_GOOD=true

# 1. Check Tailscale
echo -e "${BLUE}1. Checking Tailscale...${NC}"
if command -v tailscale &> /dev/null; then
    if tailscale status &> /dev/null; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
        TAILSCALE_NAME=$(tailscale status | grep $(hostname -s) | awk '{print $2}')
        echo -e "${GREEN}✅ Tailscale is running${NC}"
        echo -e "   Your Tailscale IP: ${GREEN}$TAILSCALE_IP${NC}"
        echo -e "   Your Tailscale name: ${GREEN}$TAILSCALE_NAME${NC}"
        echo -e "   ${YELLOW}→ Use either of these in Termius as the host address${NC}"
    else
        echo -e "${RED}❌ Tailscale is installed but not running${NC}"
        echo -e "   Fix: Run ${YELLOW}tailscale up${NC}"
        ALL_GOOD=false
    fi
else
    echo -e "${RED}❌ Tailscale not found${NC}"
    echo -e "   Fix: Run ${YELLOW}brew install tailscale${NC}"
    ALL_GOOD=false
fi
echo ""

# 2. Check SSH
echo -e "${BLUE}2. Checking SSH Server...${NC}"
if sudo systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
    echo -e "${GREEN}✅ SSH is enabled${NC}"
    echo -e "   Your username for Termius: ${GREEN}$(whoami)${NC}"
else
    echo -e "${RED}❌ SSH is disabled${NC}"
    echo -e "   Fix: Run ${YELLOW}sudo systemsetup -setremotelogin on${NC}"
    ALL_GOOD=false
fi

# Check if SSH is actually listening
if lsof -i :22 | grep -q LISTEN; then
    echo -e "${GREEN}✅ SSH is listening on port 22${NC}"
else
    echo -e "${RED}❌ SSH is not listening${NC}"
    echo -e "   Fix: Restart SSH or check firewall settings"
    ALL_GOOD=false
fi
echo ""

# 3. Check SSH Keys
echo -e "${BLUE}3. Checking SSH Keys...${NC}"
if [ -f ~/.ssh/authorized_keys ]; then
    KEY_COUNT=$(wc -l < ~/.ssh/authorized_keys | tr -d ' ')
    echo -e "${GREEN}✅ authorized_keys file exists${NC}"
    echo -e "   Number of keys: ${GREEN}$KEY_COUNT${NC}"
    
    # Check permissions
    PERMS=$(stat -f %A ~/.ssh/authorized_keys)
    if [ "$PERMS" = "600" ]; then
        echo -e "${GREEN}✅ authorized_keys permissions are correct (600)${NC}"
    else
        echo -e "${RED}❌ authorized_keys has wrong permissions: $PERMS${NC}"
        echo -e "   Fix: Run ${YELLOW}chmod 600 ~/.ssh/authorized_keys${NC}"
        ALL_GOOD=false
    fi
else
    echo -e "${YELLOW}⚠️  No authorized_keys file found${NC}"
    echo -e "   You need to add your Termius public key"
    echo -e "   Fix: ${YELLOW}echo 'YOUR_PUBLIC_KEY' >> ~/.ssh/authorized_keys${NC}"
    ALL_GOOD=false
fi
echo ""

# 4. Check tmux
echo -e "${BLUE}4. Checking tmux...${NC}"
if command -v tmux &> /dev/null; then
    echo -e "${GREEN}✅ tmux is installed${NC}"
    TMUX_VERSION=$(tmux -V)
    echo -e "   Version: ${GREEN}$TMUX_VERSION${NC}"
    
    # Check for Claude sessions
    if tmux has-session -t claude-main 2>/dev/null; then
        echo -e "${GREEN}✅ claude-main session exists${NC}"
    else
        echo -e "${YELLOW}⚠️  No claude-main session found${NC}"
        echo -e "   This is OK - it will be created on first connect"
    fi
else
    echo -e "${RED}❌ tmux not found${NC}"
    echo -e "   Fix: Run ${YELLOW}brew install tmux${NC}"
    ALL_GOOD=false
fi
echo ""

# 5. Check mosh
echo -e "${BLUE}5. Checking mosh (for better mobile experience)...${NC}"
if command -v mosh-server &> /dev/null; then
    MOSH_PATH=$(which mosh-server)
    echo -e "${GREEN}✅ mosh-server is installed${NC}"
    echo -e "   Path: ${GREEN}$MOSH_PATH${NC}"
    echo -e "   ${YELLOW}→ Add this path to Termius Mosh settings${NC}"
    
    # Check if mosh ports are accessible
    if ! sudo pfctl -s rules 2>/dev/null | grep -q "60000:61000"; then
        echo -e "${YELLOW}⚠️  Firewall might block mosh (ports 60000-61000)${NC}"
        echo -e "   This is usually OK with Tailscale"
    fi
else
    echo -e "${YELLOW}⚠️  mosh-server not found${NC}"
    echo -e "   Mosh provides better mobile experience (optional)"
    echo -e "   Fix: Run ${YELLOW}brew install mosh${NC}"
fi
echo ""

# 6. Check Claude Code CLI
echo -e "${BLUE}6. Checking Claude Code CLI...${NC}"
if command -v claude &> /dev/null; then
    echo -e "${GREEN}✅ Claude Code CLI is installed${NC}"
    CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1)
    echo -e "   Version: ${GREEN}$CLAUDE_VERSION${NC}"
else
    echo -e "${RED}❌ Claude Code CLI not found${NC}"
    echo -e "   Fix: Install Claude Code CLI first"
    ALL_GOOD=false
fi
echo ""

# 7. Check startup script
echo -e "${BLUE}7. Checking startup script...${NC}"
if [ -f ~/start-claude.sh ]; then
    echo -e "${GREEN}✅ start-claude.sh exists${NC}"
    if [ -x ~/start-claude.sh ]; then
        echo -e "${GREEN}✅ start-claude.sh is executable${NC}"
    else
        echo -e "${RED}❌ start-claude.sh is not executable${NC}"
        echo -e "   Fix: Run ${YELLOW}chmod +x ~/start-claude.sh${NC}"
        ALL_GOOD=false
    fi
else
    echo -e "${YELLOW}⚠️  start-claude.sh not found${NC}"
    echo -e "   Fix: Create it following the guide"
fi
echo ""

# 8. Test local SSH connection
echo -e "${BLUE}8. Testing local SSH connection...${NC}"
if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no localhost echo "SSH test successful" 2>/dev/null; then
    echo -e "${GREEN}✅ Local SSH connection works${NC}"
else
    echo -e "${RED}❌ Cannot connect via SSH locally${NC}"
    echo -e "   This might be a key or permission issue"
    ALL_GOOD=false
fi
echo ""

# 9. Show connection info for Termius
echo -e "${BLUE}📱 Termius Connection Information:${NC}"
echo "====================================="
echo -e "Host Address: ${GREEN}$TAILSCALE_IP${NC} or ${GREEN}$TAILSCALE_NAME${NC}"
echo -e "Port: ${GREEN}22${NC}"
echo -e "Username: ${GREEN}$(whoami)${NC}"
echo -e "Authentication: ${GREEN}SSH Key (ED25519 recommended)${NC}"
if command -v mosh-server &> /dev/null; then
    echo -e "Mosh Server Path: ${GREEN}$(which mosh-server)${NC}"
fi
echo -e "Startup Command: ${GREEN}/Users/$(whoami)/start-claude.sh${NC}"
echo ""

# Final summary
echo -e "${BLUE}📊 Summary:${NC}"
echo "====================================="
if [ "$ALL_GOOD" = true ]; then
    echo -e "${GREEN}✅ Everything looks good! Your MacBook is ready for Termius connections.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Copy your Termius public key from the iPhone app"
    echo "2. Add it to ~/.ssh/authorized_keys on this Mac"
    echo "3. Configure the host in Termius using the information above"
    echo "4. Test the connection!"
else
    echo -e "${YELLOW}⚠️  Some issues were found. Please fix them before connecting.${NC}"
    echo "Run this script again after fixing to verify everything is working."
fi
echo ""

# Optional: Show recent SSH connection attempts
echo -e "${BLUE}📝 Recent SSH Connection Attempts (last 5):${NC}"
echo "====================================="
sudo log show --predicate 'process == "sshd"' --last 5m 2>/dev/null | grep -E "(Accepted|Failed|error)" | tail -5 || echo "No recent attempts"
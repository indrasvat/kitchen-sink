#!/bin/bash
# Claude Code CLI Automatic Session Manager for Termius
# This script ensures you always connect to a running Claude session

# Colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SESSION_NAME="claude-main"
CLAUDE_CMD="claude code"

# Function to print colored status
print_status() {
    echo -e "${BLUE}[Claude Session Manager]${NC} $1"
}

# Check if we're already inside tmux
if [ -n "$TMUX" ]; then
    print_status "Already in tmux session"
    # If we're in tmux but not in Claude, start Claude
    if ! pgrep -f "claude code" > /dev/null; then
        exec $CLAUDE_CMD
    fi
    exit 0
fi

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo -e "${YELLOW}⚠️  tmux not found. Running Claude directly...${NC}"
    exec $CLAUDE_CMD
fi

# Check if Claude session exists
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    print_status "Found existing Claude session '${GREEN}$SESSION_NAME${NC}'"
    print_status "Attaching..."
    
    # Clear screen for clean appearance
    clear
    
    # Show a brief connection message
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Welcome to Claude Code CLI        ║${NC}"
    echo -e "${GREEN}║     Session: $SESSION_NAME                  ║${NC}"
    echo -e "${GREEN}║     Press Ctrl-A D to disconnect      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    sleep 1
    clear
    
    # Attach to existing session
    exec tmux attach-session -t $SESSION_NAME
else
    print_status "No existing session found"
    print_status "Creating new Claude session '${GREEN}$SESSION_NAME${NC}'..."
    
    # Create new session with Claude Code
    tmux new-session -s $SESSION_NAME -n main "$CLAUDE_CMD"
fi

# This should never be reached, but just in case
echo -e "${YELLOW}If you see this message, something unexpected happened.${NC}"
echo "Try running: tmux attach -t $SESSION_NAME"
#!/usr/bin/env bash
set -e
# Claude Code CLI Session Management Script
# Provides easy session management for remote access

CLAUDE_SESSION_PREFIX="claude"
CLAUDE_CMD="claude"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to list all Claude sessions
list_sessions() {
    echo -e "${BLUE}📋 Active Claude Code sessions:${NC}"
    tmux list-sessions 2>/dev/null | grep "^${CLAUDE_SESSION_PREFIX}" || echo "No active Claude sessions"
}

# Function to create a new Claude session
new_session() {
    local session_name="${1:-main}"
    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"
    
    if tmux has-session -t "$full_session_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Session '$full_session_name' already exists${NC}"
        attach_session "$session_name"
    else
        echo -e "${GREEN}🚀 Creating new session: $full_session_name${NC}"
        tmux new-session -d -s "$full_session_name" -n main "$CLAUDE_CMD"
        echo -e "${GREEN}✅ Session created successfully${NC}"
        attach_session "$session_name"
    fi
}

# Function to attach to existing session
attach_session() {
    local session_name="${1:-main}"
    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"
    
    if tmux has-session -t "$full_session_name" 2>/dev/null; then
        echo -e "${GREEN}📎 Attaching to session: $full_session_name${NC}"
        tmux attach-session -t "$full_session_name"
    else
        echo -e "${RED}❌ Session '$full_session_name' not found${NC}"
        echo -e "${YELLOW}💡 Creating new session instead...${NC}"
        new_session "$session_name"
    fi
}

# Function to kill a Claude session
kill_session() {
    local session_name="${1:-main}"
    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"
    
    if tmux has-session -t "$full_session_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Killing session: $full_session_name${NC}"
        tmux kill-session -t "$full_session_name"
        echo -e "${GREEN}✅ Session killed${NC}"
    else
        echo -e "${RED}❌ Session '$full_session_name' not found${NC}"
    fi
}

# Function to send command to Claude session
send_command() {
    local session_name="${1:-main}"
    local command="${2}"
    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"
    
    if [ -z "$command" ]; then
        echo -e "${RED}❌ No command provided${NC}"
        return 1
    fi
    
    if tmux has-session -t "$full_session_name" 2>/dev/null; then
        echo -e "${GREEN}📤 Sending command to $full_session_name${NC}"
        tmux send-keys -t "$full_session_name" "$command" Enter
        echo -e "${GREEN}✅ Command sent${NC}"
    else
        echo -e "${RED}❌ Session '$full_session_name' not found${NC}"
    fi
}

# Function to capture session output
capture_output() {
    local session_name="${1:-main}"
    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"
    local output_file="${2:-claude-output-$(date +%Y%m%d-%H%M%S).txt}"
    
    if tmux has-session -t "$full_session_name" 2>/dev/null; then
        echo -e "${GREEN}📸 Capturing output from $full_session_name${NC}"
        tmux capture-pane -t "$full_session_name" -p > "$output_file"
        echo -e "${GREEN}✅ Output saved to: $output_file${NC}"
    else
        echo -e "${RED}❌ Session '$full_session_name' not found${NC}"
    fi
}

# Function to monitor session status
monitor_session() {
    local session_name="${1:-main}"
    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"
    
    if tmux has-session -t "$full_session_name" 2>/dev/null; then
        echo -e "${GREEN}👁️  Monitoring session: $full_session_name${NC}"
        echo "Press Ctrl-C to stop monitoring"
        while true; do
            clear
            echo -e "${BLUE}📊 Session Status: $full_session_name${NC}"
            echo "─────────────────────────────────────"
            tmux list-panes -t "$full_session_name" -F "Window: #{window_name} | Pane: #{pane_index} | PID: #{pane_pid} | Active: #{pane_active}"
            echo ""
            echo -e "${YELLOW}Last 10 lines of output:${NC}"
            echo "─────────────────────────────────────"
            tmux capture-pane -t "$full_session_name" -p | tail -10
            sleep 5
        done
    else
        echo -e "${RED}❌ Session '$full_session_name' not found${NC}"
    fi
}

# Quick start function for mobile access
quickstart() {
    echo -e "${BLUE}🚀 Claude Code CLI Quick Start${NC}"
    echo "─────────────────────────────────────"
    
    # Check if tmux is running
    if ! pgrep -x "tmux" > /dev/null; then
        echo -e "${YELLOW}Starting tmux server...${NC}"
        tmux start-server
    fi
    
    # Create or attach to default session
    local default_session="${CLAUDE_SESSION_PREFIX}-main"
    if tmux has-session -t "$default_session" 2>/dev/null; then
        echo -e "${GREEN}📎 Attaching to existing session${NC}"
        tmux attach-session -t "$default_session"
    else
        echo -e "${GREEN}🆕 Creating new Claude Code session${NC}"
        tmux new-session -s "$default_session" -n main "$CLAUDE_CMD"
    fi
}

# Main script logic
case "${1}" in
    list|ls)
        list_sessions
        ;;
    new|create)
        new_session "${2}"
        ;;
    attach|a)
        attach_session "${2}"
        ;;
    kill|stop)
        kill_session "${2}"
        ;;
    send)
        send_command "${2}" "${3}"
        ;;
    capture)
        capture_output "${2}" "${3}"
        ;;
    monitor|watch)
        monitor_session "${2}"
        ;;
    quickstart|qs)
        quickstart
        ;;
    *)
        echo -e "${BLUE}Claude Code CLI Session Manager${NC}"
        echo "─────────────────────────────────────"
        echo "Usage: $0 {command} [options]"
        echo ""
        echo "Commands:"
        echo "  list|ls                    - List all Claude sessions"
        echo "  new|create [name]          - Create new Claude session"
        echo "  attach|a [name]            - Attach to existing session"
        echo "  kill|stop [name]           - Kill a Claude session"
        echo "  send [name] [command]      - Send command to session"
        echo "  capture [name] [file]      - Capture session output"
        echo "  monitor|watch [name]       - Monitor session status"
        echo "  quickstart|qs              - Quick start (create/attach main)"
        echo ""
        echo "Examples:"
        echo "  $0 new project1           - Create session 'claude-project1'"
        echo "  $0 attach project1        - Attach to 'claude-project1'"
        echo "  $0 send main 'help'       - Send 'help' to main session"
        echo "  $0 quickstart             - Quick start for mobile access"
        ;;
esac
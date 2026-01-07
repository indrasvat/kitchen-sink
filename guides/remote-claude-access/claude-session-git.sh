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
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Function to sanitize names for tmux compatibility
sanitize_session_name() {
    local name="$1"
    # Replace spaces, dots, colons, and other special chars with hyphens
    # Keep only alphanumeric, hyphens, and underscores
    echo "$name" | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

# Function to get git repo name
get_git_repo_name() {
    # Check if we're in a git repo
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        # Try to get repo name from origin URL
        local origin_url=$(git remote get-url origin 2>/dev/null)
        if [ -n "$origin_url" ]; then
            # Extract repo name from URL (works for both HTTPS and SSH)
            # Remove .git extension and get last part of path
            basename "$origin_url" .git
        else
            # No origin, use the repo's root directory name
            basename "$(git rev-parse --show-toplevel)"
        fi
    else
        return 1
    fi
}

# Function to generate contextual session name
get_contextual_session_name() {
    local repo_name=$(get_git_repo_name)
    if [ $? -eq 0 ] && [ -n "$repo_name" ]; then
        # We're in a git repo
        sanitize_session_name "$repo_name"
    else
        # Not in a git repo, use current directory name
        local dir_name=$(basename "$(pwd)")
        if [ "$dir_name" = "/" ] || [ "$dir_name" = "~" ] || [ -z "$dir_name" ]; then
            # We're at root or home, default to "main"
            echo "main"
        else
            sanitize_session_name "$dir_name"
        fi
    fi
}

# Function to list all Claude sessions
list_sessions() {
    local interactive_mode="${1:-false}"

    # Get all Claude sessions
    local sessions=()
    local session_details=()

    echo -e "${BLUE}📋 Active Claude Code sessions:${NC}"
    echo "─────────────────────────────────────────────────────"

    # Check if any Claude sessions exist
    local found_sessions=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^${CLAUDE_SESSION_PREFIX}-([^:]+): ]]; then
            found_sessions=true
            local session_name="${line%%:*}"
            local short_name="${session_name#${CLAUDE_SESSION_PREFIX}-}"
            local session_info="${line#*: }"

            # Get detailed session status
            local window_count=$(tmux list-windows -t "$session_name" 2>/dev/null | wc -l | tr -d ' ')
            local active_pane=$(tmux display-message -t "$session_name" -p "#{pane_current_command}" 2>/dev/null || echo "unknown")
            local created=$(tmux display-message -t "$session_name" -p "#{session_created}" 2>/dev/null || echo "unknown")
            local last_activity=$(tmux display-message -t "$session_name" -p "#{session_activity}" 2>/dev/null || echo "unknown")

            # Format timestamps if available
            if [[ "$created" =~ ^[0-9]+$ ]]; then
                created=$(date -r "$created" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
            fi
            if [[ "$last_activity" =~ ^[0-9]+$ ]]; then
                last_activity=$(date -r "$last_activity" "+%H:%M:%S" 2>/dev/null || echo "unknown")
            fi

            # Check if session is attached
            local attached_status=""
            if tmux list-clients -t "$session_name" 2>/dev/null | grep -q .; then
                attached_status="${GREEN}[ATTACHED]${NC}"
            else
                attached_status="${DIM}[detached]${NC}"
            fi

            # Display session info
            echo -e "  ${BOLD}${GREEN}▶ ${short_name}${NC} ${attached_status}"
            echo -e "    ${DIM}Windows: ${window_count} | Running: ${active_pane}${NC}"
            echo -e "    ${DIM}Created: ${created} | Last activity: ${last_activity}${NC}"

            # Store for potential interactive mode
            sessions+=("$short_name")
            session_details+=("${short_name} (${window_count} windows, running: ${active_pane}) ${attached_status}")

            echo
        fi
    done < <(tmux list-sessions 2>/dev/null)

    if [ "$found_sessions" = false ]; then
        echo -e "  ${DIM}No active Claude sessions${NC}"
        echo -e "  ${YELLOW}💡 Use '$(basename "$0") new' to create a session${NC}"
        return 1
    fi

    # Show summary
    local total_sessions=${#sessions[@]}
    echo -e "${CYAN}📊 Total: ${total_sessions} session(s)${NC}"

    # Offer interactive options if requested or if fzf is available
    if [ "$interactive_mode" = "true" ] || [ "$interactive_mode" = "interactive" ] || [ "$interactive_mode" = "i" ]; then
        echo
        echo -e "${YELLOW}🎯 Interactive mode:${NC}"

        # Check if fzf is available for enhanced interactive mode
        if command -v fzf >/dev/null 2>&1; then
            echo -e "${DIM}What would you like to do?${NC}"

            local action
            action=$(printf "📎 Attach to session\n🗑️  Kill session\n📤 Send command to session\n❌ Exit" | fzf \
                --prompt="Action > " \
                --header="Choose an action" \
                --height=~30% \
                --border \
                --reverse \
                --color="header:blue,prompt:cyan,pointer:green")

            case "$action" in
                "📎 Attach to session")
                    interactive_session_selector "attach"
                    ;;
                "🗑️  Kill session")
                    interactive_session_selector "kill"
                    ;;
                "📤 Send command to session")
                    echo -n "Enter command to send: "
                    read -r command
                    if [ -n "$command" ]; then
                        interactive_session_selector "send" "$command"
                    else
                        echo -e "${YELLOW}No command entered${NC}"
                    fi
                    ;;
                "❌ Exit"|"")
                    echo -e "${YELLOW}Cancelled${NC}"
                    ;;
            esac
        else
            # Fallback for when fzf is not available
            echo -e "${DIM}fzf not available - basic interactive mode${NC}"
            echo -e "  ${CYAN}a${NC} - Attach to session"
            echo -e "  ${CYAN}k${NC} - Kill session"
            echo -e "  ${CYAN}s${NC} - Send command"
            echo -e "  ${CYAN}q${NC} - Quit"
            echo
            echo -n "Choose action [a/k/s/q]: "
            read -r choice

            case "$choice" in
                a|A)
                    echo -n "Session name to attach: "
                    read -r session_name
                    attach_session "$session_name"
                    ;;
                k|K)
                    echo -n "Session name to kill: "
                    read -r session_name
                    kill_session "$session_name"
                    ;;
                s|S)
                    echo -n "Session name: "
                    read -r session_name
                    echo -n "Command to send: "
                    read -r command
                    send_command "$session_name" "$command"
                    ;;
                q|Q|"")
                    echo -e "${YELLOW}Cancelled${NC}"
                    ;;
                *)
                    echo -e "${RED}Invalid choice${NC}"
                    ;;
            esac
        fi
    else
        # Show quick action hints
        echo
        echo -e "${DIM}Quick actions:${NC}"
        echo -e "  ${CYAN}$(basename "$0") attach${NC}     - Interactive session selection"
        echo -e "  ${CYAN}$(basename "$0") list interactive${NC} - Interactive list mode"
        echo -e "  ${CYAN}$(basename "$0") kill${NC}      - Interactive kill selection"
    fi
}

# Function to create a new Claude session
new_session() {
    local session_name="${1}"

    # If no session name provided, show interactive selector
    if [ -z "$session_name" ]; then
        echo -e "${BLUE}🆕 Interactive session creation${NC}"
        echo -e "${DIM}Choose an existing session to attach to, or create a new one${NC}"
        interactive_session_selector "attach"
        return
    fi

    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"
    
    if tmux has-session -t "$full_session_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Session '$full_session_name' already exists${NC}"
        attach_session "$session_name"
    else
        echo -e "${GREEN}🚀 Creating new session: $full_session_name${NC}"
        tmux new-session -d -s "$full_session_name" -n main "$CLAUDE_CMD"
        echo -e "${GREEN}✅ Session created successfully${NC}"
        tmux attach-session -t "$full_session_name"
    fi
}

# Function to attach to existing session
attach_session() {
    local session_name="${1}"

    # If no session name provided, show interactive selector
    if [ -z "$session_name" ]; then
        interactive_session_selector "attach"
        return
    fi

    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"
    
    if tmux has-session -t "$full_session_name" 2>/dev/null; then
        echo -e "${GREEN}📎 Attaching to session: $full_session_name${NC}"
        tmux attach-session -t "$full_session_name"
    else
        echo -e "${RED}❌ Session '$full_session_name' not found${NC}"
        echo -e "${YELLOW}💡 Creating new session instead...${NC}"
        tmux new-session -s "$full_session_name" -n main "$CLAUDE_CMD"
    fi
}

# Function to kill a Claude session
kill_session() {
    local session_name="${1}"

    # If no session name provided, show interactive selector
    if [ -z "$session_name" ]; then
        interactive_session_selector "kill"
        return
    fi

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
    local session_name="${1}"
    local command="${2}"

    # If no session name provided, show interactive selector
    if [ -z "$session_name" ]; then
        if [ -z "$command" ]; then
            echo -e "${RED}❌ No command provided${NC}"
            return 1
        fi
        interactive_session_selector "send" "$command"
        return
    fi

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
    local session_name="${1:-$(get_contextual_session_name)}"
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
    local session_name="${1:-$(get_contextual_session_name)}"
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
    
    # Get contextual session name
    local contextual_name=$(get_contextual_session_name)
    local default_session="${CLAUDE_SESSION_PREFIX}-${contextual_name}"
    
    if tmux has-session -t "$default_session" 2>/dev/null; then
        echo -e "${GREEN}📎 Attaching to existing session: $default_session${NC}"
        tmux attach-session -t "$default_session"
    else
        echo -e "${GREEN}🆕 Creating new Claude Code session: $default_session${NC}"
        tmux new-session -s "$default_session" -n main "$CLAUDE_CMD"
    fi
}

# Interactive session selector using fzf
interactive_session_selector() {
    local action="${1:-attach}" # attach, kill, or send
    local command="${2:-}"      # for send action

    # Check if fzf is available
    if ! command -v fzf >/dev/null 2>&1; then
        echo -e "${RED}❌ fzf is required for interactive mode but not found${NC}"
        echo -e "${YELLOW}Please install fzf: brew install fzf${NC}"
        return 1
    fi

    # Get all Claude sessions with status info
    local sessions_info=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^${CLAUDE_SESSION_PREFIX}-([^:]+): ]]; then
            local session_name="${line%%:*}"
            local short_name="${session_name#${CLAUDE_SESSION_PREFIX}-}"

            # Get session status
            local window_count=$(tmux list-windows -t "$session_name" 2>/dev/null | wc -l | tr -d ' ')
            local active_pane=$(tmux display-message -t "$session_name" -p "#{pane_current_command}" 2>/dev/null || echo "unknown")

            sessions_info+=("${short_name} (${window_count} windows, running: ${active_pane})")
        fi
    done < <(tmux list-sessions 2>/dev/null)

    # Add option to create new session
    sessions_info+=("🆕 Create new session")

    if [ ${#sessions_info[@]} -eq 1 ]; then
        echo -e "${YELLOW}No existing Claude sessions found.${NC}"
        if [ "$action" = "attach" ]; then
            echo -e "${GREEN}Creating new session instead...${NC}"
            local contextual_name=$(get_contextual_session_name)
            new_session "$contextual_name"
            return
        fi
        return 1
    fi

    # Create fzf prompt based on action
    local fzf_prompt
    case "$action" in
        "attach") fzf_prompt="📎 Select session to attach to" ;;
        "kill") fzf_prompt="🗑️  Select session to kill" ;;
        "send") fzf_prompt="📤 Select session to send command: $command" ;;
        *) fzf_prompt="📋 Select session" ;;
    esac

    # Use fzf to select session
    local selected_session
    selected_session=$(printf '%s\n' "${sessions_info[@]}" | fzf \
        --prompt="$fzf_prompt > " \
        --header="Claude Sessions" \
        --height=~50% \
        --border \
        --reverse \
        --preview-window=hidden \
        --color="header:blue,prompt:cyan,pointer:green")

    if [ -z "$selected_session" ]; then
        echo -e "${YELLOW}Selection cancelled${NC}"
        return 1
    fi

    # Handle "Create new session" option
    if [[ "$selected_session" == "🆕 Create new session" ]]; then
        echo -e "${GREEN}Creating new session...${NC}"
        local contextual_name=$(get_contextual_session_name)
        new_session "$contextual_name"
        return
    fi

    # Extract session name (everything before the first space)
    local session_name="${selected_session%% *}"
    local full_session_name="${CLAUDE_SESSION_PREFIX}-${session_name}"

    # Execute the action
    case "$action" in
        "attach")
            echo -e "${GREEN}📎 Attaching to: $full_session_name${NC}"
            tmux attach-session -t "$full_session_name"
            ;;
        "kill")
            echo -e "${YELLOW}🗑️  Killing session: $full_session_name${NC}"
            tmux kill-session -t "$full_session_name"
            echo -e "${GREEN}✅ Session killed${NC}"
            ;;
        "send")
            echo -e "${GREEN}📤 Sending command to: $full_session_name${NC}"
            tmux send-keys -t "$full_session_name" "$command" Enter
            echo -e "${GREEN}✅ Command sent${NC}"
            ;;
    esac
}

# Main script logic
case "${1}" in
    list|ls)
        if [ "$2" = "interactive" ] || [ "$2" = "i" ]; then
            list_sessions "interactive"
        else
            list_sessions
        fi
        ;;
    new|create)
        new_session "${2}"
        ;;
    attach|a)
        attach_session "${2}"
        ;;
    interactive|i)
        # Interactive mode - show session selector
        interactive_session_selector "attach"
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
    dashboard|d)
        # Load and run dashboard mode
        # Resolve symlinks to find the real script location
        SCRIPT_PATH="${BASH_SOURCE[0]}"
        while [ -h "$SCRIPT_PATH" ]; do
            SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
            SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
            [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
        done
        SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
        
        if [ -f "${SCRIPT_DIR}/claude-dashboard-addon.sh" ]; then
            # Mark that we're the parent script to prevent circular sourcing
            export CLAUDE_SESSION_SOURCED=1
            source "${SCRIPT_DIR}/claude-dashboard-addon.sh"
            dashboard_mode
            # Clean up the environment variable
            unset CLAUDE_SESSION_SOURCED
        else
            echo -e "${RED}Dashboard addon not found${NC}"
            echo "Looking in: ${SCRIPT_DIR}"
            echo "Please ensure claude-dashboard-addon.sh is in the same directory as claude-session-git.sh"
        fi
        ;;
    *)
        echo -e "${BLUE}Claude Code CLI Session Manager${NC}"
        echo "─────────────────────────────────────"
        echo "Usage: $0 {command} [options]"
        echo ""
        echo "Commands:"
        echo "  list|ls [interactive]      - List all Claude sessions (interactive mode available)"
        echo "  new|create [name]          - Create new Claude session (interactive if no name)"
        echo "  attach|a [name]            - Attach to existing session (interactive if no name)"
        echo "  interactive|i              - 🎯 Interactive session selector"
        echo "  kill|stop [name]           - Kill a Claude session (interactive if no name)"
        echo "  send [name] [command]      - Send command to session (interactive if no name)"
        echo "  capture [name] [file]      - Capture session output"
        echo "  monitor|watch [name]       - Monitor session status"
        echo "  quickstart|qs              - Quick start (create/attach contextual session)"
        echo "  dashboard|d                - 📱 Interactive dashboard (mobile-friendly)"
        echo ""
        echo "Interactive Features:"
        echo "  • Use up/down arrow keys or j/k to navigate"
        echo "  • Press Enter to select, q to quit"
        echo "  • Shows session status and running commands"
        echo "  • Option to create new session from selector"
        echo ""
        echo "Examples:"
        echo "  $0 list                   - Show detailed session list"
        echo "  $0 list interactive       - 📋 Interactive list with actions"
        echo "  $0 interactive            - 🎯 Show interactive session selector"
        echo "  $0 attach                 - Interactive session selection"
        echo "  $0 new                    - Interactive session creation/selection"
        echo "  $0 kill                   - Interactive session killing"
        echo "  $0 new project1           - Create session 'claude-project1'"
        echo "  $0 attach project1        - Attach to 'claude-project1'"
        echo "  $0 send '' 'help'         - Interactive session selection for sending command"
        echo "  $0 quickstart             - Quick start with contextual naming"
        echo ""
        echo "Note: When no session name is provided, commands become interactive."
        echo "Contextual naming uses git repo or directory name when available."
        ;;
esac

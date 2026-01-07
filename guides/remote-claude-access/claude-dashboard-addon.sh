#!/usr/bin/env bash
# Interactive Dashboard Mode for claude-session-git.sh
# Optimized for mobile/iPhone access via SSH

# Only source the main script if we haven't already
# This prevents infinite recursion when called from the main script
if [ -z "$CLAUDE_SESSION_SOURCED" ]; then
    # Resolve symlinks to find the real script location
    SCRIPT_PATH="${BASH_SOURCE[0]}"
    while [ -h "$SCRIPT_PATH" ]; do
        SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
        SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
        [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
    done
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    
    # Mark that we're sourcing to prevent recursion
    export CLAUDE_SESSION_SOURCED=1
    source "${SCRIPT_DIR}/claude-session-git.sh" 2>/dev/null || {
        echo "Error: claude-session-git.sh not found in $SCRIPT_DIR"
        exit 1
    }
fi

# Additional colors
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'

# Function to get session status with emoji
get_session_status() {
    local session="$1"
    local last_line=$(tmux capture-pane -t "$session" -p 2>/dev/null | grep -v '^$' | tail -1 | tr -d '\n' | cut -c1-30)
    
    # Get idle time in seconds
    local idle_time=$(tmux display -p -t "$session" -F '#{pane_idle_time}' 2>/dev/null || echo "999999")
    
    # Ensure idle_time is a number
    if ! [[ "$idle_time" =~ ^[0-9]+$ ]]; then
        idle_time="999999"
    fi
    
    # Determine status indicator (using simple ASCII)
    local status_indicator="o"
    if [ "$idle_time" -lt 120 ]; then
        status_indicator="*"  # Active
    elif [ "$idle_time" -lt 900 ]; then
        status_indicator="+"  # Recent
    else
        status_indicator="o"  # Idle
    fi
    
    # Format time ago
    local time_ago=""
    if [ "$idle_time" -lt 60 ]; then
        time_ago="<1m"
    elif [ "$idle_time" -lt 3600 ]; then
        time_ago="$((idle_time / 60))m"
    else
        time_ago="$((idle_time / 3600))h"
    fi
    
    echo "${status_indicator}|${time_ago}|${last_line}"
}

# Function to display dashboard (mobile-optimized)
show_dashboard() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${BOLD}     Claude Sessions Dashboard${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    # List all Claude sessions with numbers
    local sessions=($(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${CLAUDE_SESSION_PREFIX}" | head -9))
    local count=0
    
    if [ ${#sessions[@]} -eq 0 ]; then
        echo -e "${YELLOW}  No active sessions${NC}"
        echo ""
    else
        echo ""
        for session in "${sessions[@]}"; do
            count=$((count + 1))
            local status_info=$(get_session_status "$session")
            IFS='|' read -r indicator time_ago last_line <<< "$status_info"
            
            # Truncate session name for display
            local short_name="${session#${CLAUDE_SESSION_PREFIX}-}"
            short_name=$(echo "$short_name" | cut -c1-20)
            
            # Format session line
            printf "  ${BOLD}[%d]${NC} %s %-20s ${DIM}(%s)${NC}\n" "$count" "$indicator" "$short_name" "$time_ago"
            
            # Show last activity if not empty
            if [ -n "$last_line" ] && [ "$last_line" != " " ]; then
                printf "      ${DIM}%.30s${NC}\n" "$last_line"
            fi
        done
        echo ""
    fi
    
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${BOLD}Commands:${NC}"
    
    if [ ${#sessions[@]} -gt 0 ]; then
        echo -e "  ${GREEN}1-${count}${NC} = Attach to session"
    fi
    
    echo -e "  ${GREEN}n${NC} = New session"
    echo -e "  ${GREEN}k${NC} = Kill session"
    echo -e "  ${GREEN}s${NC} = Send command"
    echo -e "  ${GREEN}l${NC} = List all sessions"
    echo -e "  ${GREEN}r${NC} = Refresh"
    echo -e "  ${GREEN}q${NC} = Quit"
    echo -e "${CYAN}========================================${NC}"
    
    # Store sessions array for later use
    DASHBOARD_SESSIONS=("${sessions[@]}")
}

# Simplified input handler
handle_dashboard_input() {
    local choice="$1"
    
    # Handle numeric choices for session attachment
    if [[ "$choice" =~ ^[1-9]$ ]] && [ "$choice" -le "${#DASHBOARD_SESSIONS[@]}" ]; then
        local selected_session="${DASHBOARD_SESSIONS[$((choice-1))]}"
        echo -e "\n${GREEN}Attaching to ${selected_session}...${NC}"
        sleep 1
        tmux attach-session -t "$selected_session"
        return 0
    fi
    
    # Handle other commands
    case "$choice" in
        n|N)
            echo -ne "\n${BOLD}Session name (Enter for auto): ${NC}"
            read -r session_name
            echo ""
            new_session "$session_name"
            echo -e "\n${GREEN}Press Enter to continue...${NC}"
            read -r
            ;;
        k|K)
            if [ ${#DASHBOARD_SESSIONS[@]} -eq 0 ]; then
                echo -e "\n${RED}No sessions to kill${NC}"
                sleep 1
                return 0
            fi
            echo -ne "\n${BOLD}Kill session (1-${#DASHBOARD_SESSIONS[@]} or name): ${NC}"
            read -r session_input
            
            if [[ "$session_input" =~ ^[1-9]$ ]] && [ "$session_input" -le "${#DASHBOARD_SESSIONS[@]}" ]; then
                local target="${DASHBOARD_SESSIONS[$((session_input-1))]}"
                local name="${target#${CLAUDE_SESSION_PREFIX}-}"
            else
                local name="$session_input"
            fi
            
            kill_session "$name"
            echo -e "\n${GREEN}Press Enter to continue...${NC}"
            read -r
            ;;
        s|S)
            if [ ${#DASHBOARD_SESSIONS[@]} -eq 0 ]; then
                echo -e "\n${RED}No sessions available${NC}"
                sleep 1
                return 0
            fi
            echo -ne "\n${BOLD}Session (1-${#DASHBOARD_SESSIONS[@]}): ${NC}"
            read -r session_num
            echo -ne "${BOLD}Command: ${NC}"
            read -r command
            
            if [[ "$session_num" =~ ^[1-9]$ ]] && [ "$session_num" -le "${#DASHBOARD_SESSIONS[@]}" ]; then
                local target="${DASHBOARD_SESSIONS[$((session_num-1))]}"
                local name="${target#${CLAUDE_SESSION_PREFIX}-}"
                send_command "$name" "$command"
                echo -e "\n${GREEN}Command sent! Press Enter...${NC}"
                read -r
            else
                echo -e "\n${RED}Invalid session number${NC}"
                sleep 1
            fi
            ;;
        l|L)
            echo ""
            list_sessions
            echo -e "\n${GREEN}Press Enter to continue...${NC}"
            read -r
            ;;
        r|R)
            # Refresh will happen automatically
            ;;
        q|Q)
            echo -e "\n${GREEN}Goodbye!${NC}"
            return 1
            ;;
        "")
            # Just Enter pressed, refresh
            ;;
        *)
            echo -e "\n${RED}Invalid choice: '$choice'${NC}"
            sleep 1
            ;;
    esac
    return 0
}

# Main dashboard loop
dashboard_mode() {
    # Disable auto-refresh for mobile stability
    trap 'echo -e "\n${YELLOW}Dashboard interrupted${NC}"; exit 0' INT
    
    while true; do
        show_dashboard
        
        # Simple read without timeout to avoid flashing
        echo -ne "\n${BOLD}Choice: ${NC}"
        read -r -n 1 choice
        
        # Handle input
        handle_dashboard_input "$choice" || break
    done
    
    trap - INT
}

# Export functions
export -f dashboard_mode
export -f show_dashboard
export -f get_session_status
export -f handle_dashboard_input

# If called directly, run dashboard
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    dashboard_mode
fi
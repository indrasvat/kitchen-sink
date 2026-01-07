#!/bin/bash
#
# ChatGPT Receipt Downloader - Installation Script
#
# This script installs and configures the ChatGPT receipt downloader as a
# scheduled launchd job on macOS.
#
# What gets installed:
#   ~/Scripts/download_chatgpt_receipt.py     - Main Python script
#   ~/Scripts/run-chatgpt-receipt.sh          - Wrapper script with notifications
#   ~/Scripts/chatgpt-receipt                 - CLI helper tool
#   ~/Library/LaunchAgents/com.user.chatgpt-receipt.plist
#
# The job runs on days 28-31 of each month at 11:00 AM local time.
#

set -e  # Exit on error

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Installation targets
SCRIPTS_DIR="$HOME/Scripts"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOGS_DIR="$HOME/Library/Logs/ChatGPTReceiptDownloader"
STATE_DIR="$HOME/Library/Application Support/ChatGPTReceiptDownloader"
RECEIPTS_DIR="$HOME/Documents/ChatGPT-Receipts"

# Source files
PLIST_NAME="com.user.chatgpt-receipt.plist"
PYTHON_SCRIPT="download_chatgpt_receipt.py"
WRAPPER_SCRIPT="run-chatgpt-receipt.sh"

# Job identifier
JOB_LABEL="com.user.chatgpt-receipt"

# ══════════════════════════════════════════════════════════════════════════════
# COLORS & OUTPUT
# ══════════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
# MAGENTA='\033[0;35m'  # unused
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}        ChatGPT Receipt Downloader - Installation           ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_step() {
    echo -e "${CYAN}▶${NC} $1"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

# ══════════════════════════════════════════════════════════════════════════════
# PREREQUISITE CHECKS
# ══════════════════════════════════════════════════════════════════════════════

check_macos() {
    print_step "Checking macOS..."
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "This script only runs on macOS"
        exit 1
    fi

    local macos_version
    macos_version=$(sw_vers -productVersion)
    print_ok "macOS $macos_version"
}

check_source_files() {
    print_step "Checking source files..."

    local missing=0

    if [[ ! -f "$SCRIPT_DIR/$PYTHON_SCRIPT" ]]; then
        print_error "Missing: $PYTHON_SCRIPT"
        missing=1
    else
        print_ok "Found: $PYTHON_SCRIPT"
    fi

    if [[ ! -f "$SCRIPT_DIR/$PLIST_NAME" ]]; then
        print_error "Missing: $PLIST_NAME"
        missing=1
    else
        print_ok "Found: $PLIST_NAME"
    fi

    if [[ ! -f "$SCRIPT_DIR/$WRAPPER_SCRIPT" ]]; then
        print_error "Missing: $WRAPPER_SCRIPT"
        missing=1
    else
        print_ok "Found: $WRAPPER_SCRIPT"
    fi

    if [[ $missing -eq 1 ]]; then
        echo
        print_error "Some required files are missing. Please ensure all files are in: $SCRIPT_DIR"
        exit 1
    fi
}

check_uv() {
    print_step "Checking for 'uv' package manager..."

    if ! command -v uv &> /dev/null; then
        print_error "'uv' is not installed"
        echo
        echo -e "  ${YELLOW}Install uv with:${NC}"
        echo -e "    ${CYAN}curl -LsSf https://astral.sh/uv/install.sh | sh${NC}"
        echo
        exit 1
    fi

    UV_PATH=$(which uv)
    print_ok "Found uv at: $UV_PATH"
}

check_chrome() {
    print_step "Checking Chrome installation..."

    local chrome_path="/Applications/Google Chrome.app"
    if [[ -d "$chrome_path" ]]; then
        print_ok "Chrome is installed"
    else
        print_warn "Chrome not found at $chrome_path"
        print_info "Browser automation requires Google Chrome"
    fi
}

check_aws_credentials() {
    print_step "Checking AWS credentials (for Bedrock)..."

    if [[ -n "${AWS_PROFILE:-}" ]]; then
        print_ok "AWS_PROFILE is set: $AWS_PROFILE"
    elif [[ -f "$HOME/.aws/credentials" ]]; then
        print_ok "AWS credentials file exists"
        if grep -q "development" "$HOME/.aws/credentials" 2>/dev/null; then
            print_ok "Found 'development' profile in credentials"
        else
            print_warn "Profile 'development' not found in credentials"
            print_info "The plist is configured to use AWS_PROFILE=development"
        fi
    else
        print_warn "No AWS credentials found"
        print_info "You'll need AWS credentials for Bedrock (Claude Opus 4.5)"
    fi
}


# ══════════════════════════════════════════════════════════════════════════════
# INSTALLATION
# ══════════════════════════════════════════════════════════════════════════════

create_directories() {
    print_step "Creating directories..."

    mkdir -p "$SCRIPTS_DIR"
    print_ok "Created: $SCRIPTS_DIR"

    mkdir -p "$LAUNCH_AGENTS_DIR"
    print_ok "Created: $LAUNCH_AGENTS_DIR"

    mkdir -p "$LOGS_DIR"
    print_ok "Created: $LOGS_DIR"

    mkdir -p "$STATE_DIR"
    print_ok "Created: $STATE_DIR"

    mkdir -p "$RECEIPTS_DIR"
    print_ok "Created: $RECEIPTS_DIR"
}

install_python_script() {
    print_step "Installing Python script..."

    cp "$SCRIPT_DIR/$PYTHON_SCRIPT" "$SCRIPTS_DIR/download_chatgpt_receipt.py"
    chmod +x "$SCRIPTS_DIR/download_chatgpt_receipt.py"
    print_ok "Installed: $SCRIPTS_DIR/download_chatgpt_receipt.py"
}

install_wrapper_script() {
    print_step "Installing wrapper script..."

    cp "$SCRIPT_DIR/$WRAPPER_SCRIPT" "$SCRIPTS_DIR/run-chatgpt-receipt.sh"
    chmod +x "$SCRIPTS_DIR/run-chatgpt-receipt.sh"
    print_ok "Installed: $SCRIPTS_DIR/run-chatgpt-receipt.sh"
}

create_cli_helper() {
    print_step "Creating CLI helper tool..."

    cat > "$SCRIPTS_DIR/chatgpt-receipt" << 'HELPER_EOF'
#!/bin/bash
#
# chatgpt-receipt - CLI helper for ChatGPT Receipt Downloader
#
# Usage:
#   chatgpt-receipt status    - Show job status
#   chatgpt-receipt run       - Run the job now (manual trigger)
#   chatgpt-receipt logs      - View recent logs
#   chatgpt-receipt tail      - Follow logs in real-time
#   chatgpt-receipt receipts  - Open receipts folder
#   chatgpt-receipt uninstall - Uninstall the scheduled job
#   chatgpt-receipt help      - Show this help
#

set -e

JOB_LABEL="com.user.chatgpt-receipt"
LOGS_DIR="$HOME/Library/Logs/ChatGPTReceiptDownloader"
RECEIPTS_DIR="$HOME/Documents/ChatGPT-Receipts"
SCRIPTS_DIR="$HOME/Scripts"
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.chatgpt-receipt.plist"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

cmd_status() {
    echo -e "${BOLD}ChatGPT Receipt Downloader - Status${NC}"
    echo "────────────────────────────────────────"
    echo

    # Check if job is loaded
    if launchctl print "gui/$(id -u)/$JOB_LABEL" &>/dev/null; then
        echo -e "Job status:    ${GREEN}Loaded${NC}"

        # Get more details
        local status_output
        status_output=$(launchctl print gui/$(id -u)/$JOB_LABEL 2>/dev/null)

        # Extract last exit status if available
        local last_exit
        last_exit=$(echo "$status_output" | grep -i "last exit" | head -1 || echo "")
        if [[ -n "$last_exit" ]]; then
            echo -e "Last exit:     $last_exit"
        fi

        # Extract run count if available
        local run_count
        run_count=$(echo "$status_output" | grep -i "runs" | head -1 || echo "")
        if [[ -n "$run_count" ]]; then
            echo -e "Run count:     $run_count"
        fi
    else
        echo -e "Job status:    ${RED}Not loaded${NC}"
    fi

    echo

    # Check for receipts this month
    local current_month
    current_month=$(date +%Y-%m)
    echo -e "${BOLD}This month ($current_month):${NC}"

    if [[ -d "$RECEIPTS_DIR" ]]; then
        local receipt
        receipt=$(find "$RECEIPTS_DIR" -name "ChatGPT-Plus-Receipt-${current_month}*.pdf" -type f 2>/dev/null | head -1)
        if [[ -n "$receipt" ]]; then
            echo -e "  Receipt:     ${GREEN}Downloaded${NC}"
            echo -e "  File:        $(basename "$receipt")"
        else
            echo -e "  Receipt:     ${YELLOW}Not yet downloaded${NC}"
        fi
    else
        echo -e "  Receipt:     ${YELLOW}Receipts folder doesn't exist${NC}"
    fi

    echo

    # Show schedule
    echo -e "${BOLD}Schedule:${NC}"
    echo "  Days 28, 29, 30, 31 at 11:00 AM local time"
    echo

    # Show next scheduled run (approximate)
    local today_day
    today_day=$(date +%d)
    if [[ $today_day -lt 28 ]]; then
        echo -e "  Next run:    Day 28 of this month"
    elif [[ $today_day -le 31 ]]; then
        echo -e "  Next run:    Tomorrow or later this month (if not already run)"
    else
        echo -e "  Next run:    Day 28 of next month"
    fi
}

cmd_run() {
    echo -e "${BOLD}Running ChatGPT Receipt Downloader...${NC}"
    echo
    echo "Starting job via launchctl..."
    echo "(You'll see a macOS notification when it completes)"
    echo

    launchctl kickstart -p gui/$(id -u)/$JOB_LABEL

    echo -e "${GREEN}Job started!${NC}"
    echo
    echo "Monitor progress with:"
    echo -e "  ${CYAN}chatgpt-receipt tail${NC}"
}

cmd_logs() {
    echo -e "${BOLD}Recent Logs${NC}"
    echo "────────────────────────────────────────"
    echo

    if [[ ! -d "$LOGS_DIR" ]]; then
        echo "No logs directory found."
        exit 0
    fi

    # Show most recent run log
    local latest_log
    latest_log=$(ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | head -1)

    if [[ -n "$latest_log" ]]; then
        echo -e "${CYAN}Latest run log: $(basename "$latest_log")${NC}"
        echo
        tail -50 "$latest_log"
    else
        echo "No run logs found."
    fi

    echo
    echo "────────────────────────────────────────"
    echo -e "Log directory: ${CYAN}$LOGS_DIR${NC}"
    echo
    echo "Other commands:"
    echo -e "  ${CYAN}chatgpt-receipt tail${NC}      - Follow logs in real-time"
    echo -e "  ${CYAN}open \"$LOGS_DIR\"${NC}  - Open in Finder"
}

cmd_tail() {
    echo -e "${BOLD}Following logs (Ctrl+C to stop)...${NC}"
    echo

    if [[ ! -d "$LOGS_DIR" ]]; then
        echo "No logs directory found."
        exit 0
    fi

    # Tail the launchd stdout log
    tail -f "$LOGS_DIR/launchd-stdout.log" 2>/dev/null || {
        echo "No stdout log found. The job may not have run yet."
        echo
        echo "Trying to find any log file..."
        local any_log
        any_log=$(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -1)
        if [[ -n "$any_log" ]]; then
            echo "Found: $any_log"
            tail -f "$any_log"
        fi
    }
}

cmd_receipts() {
    echo -e "${BOLD}Opening receipts folder...${NC}"

    if [[ ! -d "$RECEIPTS_DIR" ]]; then
        mkdir -p "$RECEIPTS_DIR"
    fi

    open "$RECEIPTS_DIR"

    # List receipts
    echo
    echo "Receipts found:"
    ls -la "$RECEIPTS_DIR"/*.pdf 2>/dev/null || echo "  (none yet)"
}

cmd_uninstall() {
    echo -e "${BOLD}Uninstalling ChatGPT Receipt Downloader...${NC}"
    echo

    read -p "Are you sure you want to uninstall? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    echo

    # Unload the job
    echo "Unloading launchd job..."
    launchctl bootout gui/$(id -u)/$JOB_LABEL 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Job unloaded"

    # Remove plist
    if [[ -f "$PLIST_PATH" ]]; then
        rm "$PLIST_PATH"
        echo -e "  ${GREEN}✓${NC} Removed plist"
    fi

    # Remove scripts
    rm -f "$SCRIPTS_DIR/download_chatgpt_receipt.py"
    rm -f "$SCRIPTS_DIR/run-chatgpt-receipt.sh"
    rm -f "$SCRIPTS_DIR/chatgpt-receipt"
    echo -e "  ${GREEN}✓${NC} Removed scripts"

    echo
    echo -e "${GREEN}Uninstalled!${NC}"
    echo
    echo "Note: Logs and receipts were preserved:"
    echo "  Logs:     $LOGS_DIR"
    echo "  Receipts: $RECEIPTS_DIR"
}

cmd_help() {
    echo -e "${BOLD}chatgpt-receipt${NC} - CLI helper for ChatGPT Receipt Downloader"
    echo
    echo "Usage:"
    echo -e "  ${CYAN}chatgpt-receipt status${NC}     Show job status and recent activity"
    echo -e "  ${CYAN}chatgpt-receipt run${NC}        Run the job now (manual trigger)"
    echo -e "  ${CYAN}chatgpt-receipt logs${NC}       View recent logs"
    echo -e "  ${CYAN}chatgpt-receipt tail${NC}       Follow logs in real-time"
    echo -e "  ${CYAN}chatgpt-receipt receipts${NC}   Open receipts folder"
    echo -e "  ${CYAN}chatgpt-receipt uninstall${NC}  Uninstall the scheduled job"
    echo -e "  ${CYAN}chatgpt-receipt help${NC}       Show this help"
    echo
    echo "Schedule:"
    echo "  The job runs on days 28-31 of each month at 11:00 AM."
    echo "  If your Mac is asleep, it runs when you wake it up."
    echo
    echo "Features:"
    echo "  - macOS notifications on success or failure"
    echo "  - Automatic retries on failure"
    echo "  - Idempotent (won't re-download if already done this month)"
}

# Main
case "${1:-help}" in
    status)
        cmd_status
        ;;
    run)
        cmd_run
        ;;
    logs)
        cmd_logs
        ;;
    tail)
        cmd_tail
        ;;
    receipts)
        cmd_receipts
        ;;
    uninstall)
        cmd_uninstall
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'chatgpt-receipt help' for usage."
        exit 1
        ;;
esac
HELPER_EOF

    chmod +x "$SCRIPTS_DIR/chatgpt-receipt"
    print_ok "Installed: $SCRIPTS_DIR/chatgpt-receipt"
}

install_plist() {
    print_step "Installing launchd plist..."

    # Get actual paths for substitution
    local user_home="$HOME"
    local uv_path
    uv_path=$(which uv)

    # Copy and customize the plist
    sed -e "s|$HOME|$user_home|g" \
        -e "s|$HOME/.local/bin/uv|$uv_path|g" \
        "$SCRIPT_DIR/$PLIST_NAME" > "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

    print_ok "Installed: $LAUNCH_AGENTS_DIR/$PLIST_NAME"
}

load_launchd_job() {
    print_step "Loading launchd job..."

    # Unload if already loaded (ignore errors)
    launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true

    # Load the new plist
    if launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENTS_DIR/$PLIST_NAME"; then
        print_ok "Job loaded successfully"
    else
        print_error "Failed to load job"
        print_info "Try: launchctl bootstrap gui/\$(id -u) $LAUNCH_AGENTS_DIR/$PLIST_NAME"
        exit 1
    fi

    # Verify
    if launchctl print "gui/$(id -u)/$JOB_LABEL" &>/dev/null; then
        print_ok "Job is active and ready"
    else
        print_warn "Job loaded but status check failed"
    fi
}

add_to_path() {
    print_step "Checking PATH..."

    if [[ ":$PATH:" != *":$SCRIPTS_DIR:"* ]]; then
        print_warn "$SCRIPTS_DIR is not in your PATH"
        print_info "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
        echo
        echo -e "    ${CYAN}export PATH=\"\$HOME/Scripts:\$PATH\"${NC}"
        echo
        print_info "Or run commands with full path: $SCRIPTS_DIR/chatgpt-receipt"
    else
        print_ok "$SCRIPTS_DIR is in PATH"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# COMPLETION
# ══════════════════════════════════════════════════════════════════════════════

print_completion() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}${BOLD}              Installation Complete!                         ${NC}${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BOLD}Schedule:${NC}"
    echo "  The job runs on days ${YELLOW}28, 29, 30, 31${NC} at ${YELLOW}11:00 AM${NC} local time."
    echo "  If your Mac is asleep, it will run when you wake it up."
    echo
    echo -e "${BOLD}What happens when it runs:${NC}"
    echo "  1. Downloads your ChatGPT Plus receipt"
    echo "  2. Emails it to your-email@example.com"
    echo "  3. Shows a macOS notification on success or failure"
    echo "  4. Opens the receipts folder on success"
    echo
    echo -e "${BOLD}CLI Commands:${NC}"
    echo -e "  ${CYAN}chatgpt-receipt status${NC}     - Check job status"
    echo -e "  ${CYAN}chatgpt-receipt run${NC}        - Run now (test/manual)"
    echo -e "  ${CYAN}chatgpt-receipt logs${NC}       - View recent logs"
    echo -e "  ${CYAN}chatgpt-receipt tail${NC}       - Follow logs live"
    echo -e "  ${CYAN}chatgpt-receipt receipts${NC}   - Open receipts folder"
    echo -e "  ${CYAN}chatgpt-receipt uninstall${NC}  - Remove everything"
    echo
    echo -e "${BOLD}Logs:${NC}"
    echo "  $LOGS_DIR/"
    echo
    echo -e "${BOLD}Receipts:${NC}"
    echo "  $RECEIPTS_DIR/"
    echo
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

main() {
    print_header

    # Prerequisite checks
    check_macos
    check_source_files
    check_uv
    check_chrome
    check_aws_credentials

    echo
    echo -e "${BOLD}Installing...${NC}"
    echo

    # Installation steps
    create_directories
    install_python_script
    install_wrapper_script
    create_cli_helper
    install_plist
    load_launchd_job
    add_to_path

    # Done
    print_completion
}

main "$@"

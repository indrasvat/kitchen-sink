#!/bin/bash
#
# ChatGPT Receipt Downloader - Wrapper Script
#
# This wrapper provides:
#   - macOS notifications for success/failure
#   - Chrome running detection with user notification
#   - Automatic retry logic
#   - Detailed logging with timestamps
#   - Error visibility via Notification Center
#
# This script is called by launchd, not directly by the user.
#

set -o pipefail

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

SCRIPT_NAME="ChatGPT Receipt Downloader"
SCRIPT_DIR="$HOME/Scripts"
PYTHON_SCRIPT="$SCRIPT_DIR/download_chatgpt_receipt.py"
LOG_DIR="$HOME/Library/Logs/ChatGPTReceiptDownloader"
RECEIPTS_DIR="$HOME/Documents/ChatGPT-Receipts"
STATE_FILE="$HOME/Library/Application Support/ChatGPTReceiptDownloader/state.json"

# Retry configuration
MAX_RETRIES=2
RETRY_DELAY_SECONDS=300  # 5 minutes between retries


# ══════════════════════════════════════════════════════════════════════════════
# LOGGING
# ══════════════════════════════════════════════════════════════════════════════

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$RUN_LOG"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ══════════════════════════════════════════════════════════════════════════════
# macOS NOTIFICATIONS
# ══════════════════════════════════════════════════════════════════════════════

notify() {
    local title="$1"
    local message="$2"
    local sound="${3:-default}"  # default, Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink

    osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

notify_success() {
    notify "$SCRIPT_NAME" "$1" "Glass"
}

notify_warning() {
    notify "$SCRIPT_NAME" "$1" "Basso"
}

notify_error() {
    notify "$SCRIPT_NAME" "$1" "Sosumi"

    # Also create a persistent alert for critical errors
    if osascript -e "display dialog \"$1\" with title \"$SCRIPT_NAME - Error\" buttons {\"View Logs\", \"OK\"} default button \"OK\" with icon stop" 2>/dev/null; then
        # If user clicked "View Logs", open the log directory
        open "$LOG_DIR"
    fi
}


# ══════════════════════════════════════════════════════════════════════════════
# IDEMPOTENCY CHECK
#
# We track state granularly to prevent:
#   - Duplicate downloads
#   - Duplicate emails (most important!)
#
# State file tracks:
#   - last_success_month: Full success (download + email)
#   - last_email_sent_month: Email was sent (even if overall run had issues)
#   - last_download_month: Receipt was downloaded
# ══════════════════════════════════════════════════════════════════════════════

get_current_month_year() {
    date +%Y-%m
}

was_email_already_sent_this_month() {
    local current_month
    current_month=$(get_current_month_year)

    if [[ -f "$STATE_FILE" ]]; then
        local last_email
        last_email=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('last_email_sent_month', ''))" 2>/dev/null || echo "")
        if [[ "$last_email" == "$current_month" ]]; then
            log_info "Email already sent for $current_month (per state file)"
            return 0
        fi
    fi

    return 1
}

was_already_run_this_month() {
    local current_month
    current_month=$(get_current_month_year)

    # Check state file first (most reliable)
    if [[ -f "$STATE_FILE" ]]; then
        local last_success
        last_success=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('last_success_month', ''))" 2>/dev/null || echo "")
        if [[ "$last_success" == "$current_month" ]]; then
            log_info "State file indicates full success for $current_month"
            return 0
        fi
    fi

    # Also check if we have a receipt file AND email was sent
    # (handles case where state file was corrupted but we have evidence of completion)
    if [[ -d "$RECEIPTS_DIR" ]]; then
        local receipt_file
        receipt_file=$(find "$RECEIPTS_DIR" -name "ChatGPT-Plus-Receipt-${current_month}*.pdf" -type f 2>/dev/null | head -1)
        if [[ -n "$receipt_file" ]]; then
            # We have a receipt - but was email sent?
            if was_email_already_sent_this_month; then
                log_info "Receipt exists AND email was sent for $current_month"
                return 0
            else
                log_warn "Receipt exists for $current_month but email status unknown"
                # Don't skip - let it try to email (Python script handles this)
            fi
        fi
    fi

    return 1
}

# shellcheck disable=SC2329  # May be used in future or called indirectly
record_email_sent() {
    local current_month
    current_month=$(get_current_month_year)

    mkdir -p "$(dirname "$STATE_FILE")"

    python3 -c "
import json
from datetime import datetime
from pathlib import Path

state_file = Path('$STATE_FILE')
state = {}
if state_file.exists():
    try:
        state = json.loads(state_file.read_text())
    except:
        pass

state['last_email_sent_month'] = '$current_month'
state['last_email_sent_timestamp'] = datetime.now().isoformat()

state_file.write_text(json.dumps(state, indent=2))
" 2>/dev/null || true

    log_info "Recorded: email sent for $current_month"
}

record_success() {
    local current_month
    current_month=$(get_current_month_year)

    mkdir -p "$(dirname "$STATE_FILE")"

    python3 -c "
import json
from datetime import datetime
from pathlib import Path

state_file = Path('$STATE_FILE')
state = {}
if state_file.exists():
    try:
        state = json.loads(state_file.read_text())
    except:
        pass

state['last_success_month'] = '$current_month'
state['last_success_timestamp'] = datetime.now().isoformat()
state['last_email_sent_month'] = '$current_month'
state['run_count'] = state.get('run_count', 0) + 1

state_file.write_text(json.dumps(state, indent=2))
" 2>/dev/null || true

    log_info "Recorded: full success for $current_month"
}

# ══════════════════════════════════════════════════════════════════════════════
# PREREQUISITES CHECK
# ══════════════════════════════════════════════════════════════════════════════

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Python script exists
    if [[ ! -f "$PYTHON_SCRIPT" ]]; then
        log_error "Python script not found: $PYTHON_SCRIPT"
        notify_error "Installation broken: Python script missing. Please reinstall."
        return 1
    fi

    # Check uv is available
    if ! command -v uv &> /dev/null; then
        log_error "'uv' command not found in PATH"
        notify_error "Installation broken: 'uv' not found. Please install uv."
        return 1
    fi

    # Check AWS credentials (for Bedrock)
    if [[ -z "${AWS_PROFILE:-}" ]] && [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        log_warn "No AWS credentials configured (AWS_PROFILE or AWS_ACCESS_KEY_ID)"
        # Don't fail - the Python script will provide better error messages
    fi

    log_info "Prerequisites OK"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

run_download() {
    local attempt=$1

    log_info "Starting download attempt $attempt of $((MAX_RETRIES + 1))..."

    # Run the Python script and capture output
    local exit_code
    local output

    output=$(uv run "$PYTHON_SCRIPT" \
        --provider bedrock \
        --profile "Profile 2" \
        --auto \
        --email-to "your-email@example.com" \
        2>&1) || exit_code=$?

    exit_code=${exit_code:-0}

    # Log the output
    echo "$output" >> "$RUN_LOG"

    if [[ $exit_code -eq 0 ]]; then
        log_info "Download completed successfully!"
        return 0
    else
        log_error "Download failed with exit code $exit_code"
        return "$exit_code"
    fi
}

main() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "$SCRIPT_NAME - Automated Run"
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "Log file: $RUN_LOG"
    log_info "Date: $(date)"
    log_info "User: $(whoami)"

    # Check if already run this month
    if was_already_run_this_month; then
        log_info "Already successfully downloaded receipt this month - skipping"
        exit 0
    fi

    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi

    # Run with retries
    local attempt=1
    local success=false

    while [[ $attempt -le $((MAX_RETRIES + 1)) ]]; do
        if run_download $attempt; then
            success=true
            break
        fi

        if [[ $attempt -le $MAX_RETRIES ]]; then
            log_warn "Attempt $attempt failed. Retrying in $((RETRY_DELAY_SECONDS / 60)) minutes..."
            notify_warning "Download attempt $attempt failed. Retrying in $((RETRY_DELAY_SECONDS / 60)) minutes..."
            sleep $RETRY_DELAY_SECONDS
        fi

        attempt=$((attempt + 1))
    done

    # Final result
    log_info "═══════════════════════════════════════════════════════════════"

    if $success; then
        record_success
        log_info "SUCCESS: Receipt downloaded and emailed!"
        notify_success "Receipt downloaded and emailed successfully!"

        # Open the receipts folder so user can see the file
        if [[ -d "$RECEIPTS_DIR" ]]; then
            open "$RECEIPTS_DIR"
        fi

        exit 0
    else
        log_error "FAILED: All $((MAX_RETRIES + 1)) attempts failed"
        notify_error "Failed to download receipt after $((MAX_RETRIES + 1)) attempts. Check logs for details."

        # Open log directory so user can investigate
        open "$LOG_DIR"

        exit 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

main "$@"

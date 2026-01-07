#!/usr/bin/env bash

# tmux-screenshot.sh - Automated CLI Screenshot Tool for macOS with iTerm2
# Usage: ./tmux-screenshot.sh [options] -- command [args...]
#
# Examples:
#   ./tmux-screenshot.sh -- ls -la
#   ./tmux-screenshot.sh -o screenshot.png -d 2 -- "npm start"
#   ./tmux-screenshot.sh -w 150 -h 50 -p "My Profile" -- ./my-cli --help
#   ./tmux-screenshot.sh -D /path/to/project -e "source venv/bin/activate" -- python app.py

# Don't exit on error during getopt
set +e

# Default values
SESSION_NAME="screenshot_session_$"
OUTPUT_FILE="screenshot.png"
TMUX_WIDTH=120
TMUX_HEIGHT=40
COMMAND_DELAY=2
SCREENSHOT_DELAY=1
WORKING_DIR="$PWD"
KEEP_SESSION=false
CROP_SCREENSHOT=false
CROP_TOP=0
CROP_BOTTOM=0
CROP_LEFT=0
CROP_RIGHT=0
ITERM_PROFILE="Default"
PRE_COMMANDS=""
POST_COMMANDS=""
CLEAR_SCREEN=true
WINDOW_ONLY=false
HIDE_SHADOW=true
DEBUG=false
FONT_SIZE=""
BACKGROUND_COLOR=""
MAXIMIZE_WINDOW=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1"
    fi
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] -- COMMAND

Automated CLI screenshot tool using tmux and iTerm2 on macOS.

OPTIONS:
    -o, --output FILE          Output screenshot file (default: screenshot.png)
    -s, --session NAME         tmux session name (default: auto-generated)
    -w, --width COLS          Terminal width in columns (default: 120)
    -h, --height ROWS         Terminal height in rows (default: 40)
    -d, --delay SECONDS       Delay after command execution (default: 2)
    -D, --directory PATH      Working directory for command (default: current)
    -p, --profile NAME        iTerm2 profile name (default: Default)
    -e, --pre-command CMD     Commands to run before main command (can be used multiple times)
    -E, --post-command CMD    Commands to run after main command (can be used multiple times)
    -k, --keep-session        Keep tmux session after screenshot
    -c, --crop T:B:L:R        Crop screenshot (top:bottom:left:right pixels)
    -n, --no-clear            Don't clear screen before running command
    -W, --window-only         Capture only window content (no decorations)
    -S, --show-shadow         Show window shadow in screenshot
    -M, --maximize            Maximize iTerm2 window
    -f, --font-size SIZE      Set font size in iTerm2 (e.g., 14)
    -b, --bg-color COLOR      Set background color (hex, e.g., "#1e1e1e")
    --screenshot-delay SEC    Delay before taking screenshot (default: 1)
    --debug                   Enable debug output
    --help                    Show this help message

COMMAND:
    The command to execute and screenshot. Use quotes for complex commands.

EXAMPLES:
    # Simple command
    $0 -- ls -la

    # Custom output file and dimensions
    $0 -o help.png -w 100 -h 30 -- ./my-cli --help

    # With working directory and pre-commands
    $0 -D ~/project -e "source venv/bin/activate" -- python app.py

    # Multiple pre-commands with custom profile
    $0 -p "Presentation" -e "clear" -e "echo 'Demo Time!'" -- npm start

    # Keep session alive for inspection
    $0 -k -s my_debug_session -- ./buggy-script.sh

    # Crop screenshot (remove 30px from top, 20px from bottom)
    $0 -c 30:20:0:0 -- htop

    # Maximize window for full-screen capture
    $0 -M -w 200 -h 70 -- ./my-cli dashboard

    # Full featured example
    $0 -o demo.png -w 150 -h 50 -d 3 -D ~/myapp \\
       -e "nvm use 18" -e "npm install" \\
       -f 16 -b "#282c34" \\
       -- npm run dev

EOF
    exit 0
}

# Parse command line arguments
# Note: macOS uses BSD getopt, not GNU getopt, so we need to handle this carefully
ARGS=("$@")
PARSED_ARGS=()
COMMAND_ARGS=()
FOUND_SEPARATOR=false

# Manual parsing for better compatibility
i=0
while [ $i -lt ${#ARGS[@]} ]; do
    arg="${ARGS[$i]}"
    
    if [ "$FOUND_SEPARATOR" = true ]; then
        COMMAND_ARGS+=("$arg")
        ((i++))
        continue
    fi
    
    case "$arg" in
        -o|--output)
            OUTPUT_FILE="${ARGS[$((i+1))]}"
            log_debug "Set OUTPUT_FILE to: $OUTPUT_FILE"
            ((i+=2))
            ;;
        -s|--session)
            SESSION_NAME="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -w|--width)
            TMUX_WIDTH="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -h|--height)
            TMUX_HEIGHT="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -d|--delay)
            COMMAND_DELAY="${ARGS[$((i+1))]}"
            log_debug "Set COMMAND_DELAY to: $COMMAND_DELAY"
            ((i+=2))
            ;;
        -D|--directory)
            WORKING_DIR="${ARGS[$((i+1))]}"
            log_debug "Set WORKING_DIR to: $WORKING_DIR"
            ((i+=2))
            ;;
        -p|--profile)
            ITERM_PROFILE="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -e|--pre-command)
            PRE_COMMANDS="${PRE_COMMANDS}${ARGS[$((i+1))]};"
            log_debug "Added pre-command: ${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -E|--post-command)
            POST_COMMANDS="${POST_COMMANDS}${ARGS[$((i+1))]};"
            ((i+=2))
            ;;
        -c|--crop)
            CROP_SCREENSHOT=true
            IFS=':' read -r CROP_TOP CROP_BOTTOM CROP_LEFT CROP_RIGHT <<< "${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -f|--font-size)
            FONT_SIZE="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -b|--bg-color)
            BACKGROUND_COLOR="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -M|--maximize)
            MAXIMIZE_WINDOW=true
            ((i++))
            ;;
        -k|--keep-session)
            KEEP_SESSION=true
            ((i++))
            ;;
        -n|--no-clear)
            CLEAR_SCREEN=false
            ((i++))
            ;;
        -W|--window-only)
            WINDOW_ONLY=true
            ((i++))
            ;;
        -S|--show-shadow)
            HIDE_SHADOW=false
            ((i++))
            ;;
        --screenshot-delay)
            SCREENSHOT_DELAY="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        --debug)
            DEBUG=true
            ((i++))
            ;;
        -H|--help)
            usage
            ;;
        --)
            FOUND_SEPARATOR=true
            ((i++))
            ;;
        *)
            log_error "Unknown option: $arg"
            log_error "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Re-enable exit on error
set -e

# Set command from remaining arguments
if [ ${#COMMAND_ARGS[@]} -eq 0 ]; then
    log_error "No command specified after --. Use --help for usage."
    exit 1
fi

COMMAND="${COMMAND_ARGS[*]}"
log_debug "Parsed command: '$COMMAND'"

# Validate working directory
if [ ! -d "$WORKING_DIR" ]; then
    log_error "Working directory does not exist: $WORKING_DIR"
    exit 1
fi

# Debug: Show final configuration
if [ "$DEBUG" = true ]; then
    log_debug "=== Final Configuration ==="
    log_debug "OUTPUT_FILE: $OUTPUT_FILE"
    log_debug "SESSION_NAME: $SESSION_NAME"
    log_debug "WORKING_DIR: $WORKING_DIR"
    log_debug "COMMAND: $COMMAND"
    log_debug "PRE_COMMANDS: $PRE_COMMANDS"
    log_debug "COMMAND_DELAY: $COMMAND_DELAY"
    log_debug "=========================="
fi

# Function to cleanup
cleanup() {
    if [ "$KEEP_SESSION" = false ]; then
        log_debug "Cleaning up tmux session: $SESSION_NAME"
        tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    else
        log_info "tmux session kept alive: $SESSION_NAME"
        log_info "Attach with: tmux attach -t $SESSION_NAME"
    fi
    
    # Close iTerm window if we opened it (and not keeping session)
    if [ "$KEEP_SESSION" = false ] && [ -n "$ITERM_WINDOW_ID" ]; then
        log_debug "Closing iTerm window"
        osascript -e "tell application \"iTerm\" to close (every window whose id is $ITERM_WINDOW_ID)" 2>/dev/null || true
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Kill existing session if it exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log_info "Killing existing session: $SESSION_NAME"
    tmux kill-session -t "$SESSION_NAME"
fi

# Create new tmux session
log_info "Creating tmux session: $SESSION_NAME (${TMUX_WIDTH}x${TMUX_HEIGHT})"
tmux new-session -d -s "$SESSION_NAME" -x "$TMUX_WIDTH" -y "$TMUX_HEIGHT" -c "$WORKING_DIR"

# Function to send command to tmux
send_command() {
    local cmd="$1"
    log_debug "Sending command: $cmd"
    tmux send-keys -t "$SESSION_NAME" "$cmd" C-m
}

# Clear screen if requested
if [ "$CLEAR_SCREEN" = true ]; then
    send_command "clear"
    sleep 0.1
fi

# Execute pre-commands
if [ -n "$PRE_COMMANDS" ]; then
    log_info "Executing pre-commands..."
    log_debug "PRE_COMMANDS string: '$PRE_COMMANDS'"
    IFS=';' read -ra COMMANDS <<< "$PRE_COMMANDS"
    for cmd in "${COMMANDS[@]}"; do
        if [ -n "$cmd" ]; then
            log_debug "Executing pre-command: '$cmd'"
            send_command "$cmd"
            sleep 0.2
        fi
    done
fi

# Execute main command
log_info "Executing command: $COMMAND"
log_debug "About to send command to tmux: '$COMMAND'"
send_command "$COMMAND"

# Execute post-commands
if [ -n "$POST_COMMANDS" ]; then
    sleep 0.5
    log_info "Executing post-commands..."
    IFS=';' read -ra COMMANDS <<< "$POST_COMMANDS"
    for cmd in "${COMMANDS[@]}"; do
        if [ -n "$cmd" ]; then
            send_command "$cmd"
            sleep 0.2
        fi
    done
fi

# Wait for command to complete
log_info "Waiting ${COMMAND_DELAY} seconds for command to complete..."
sleep "$COMMAND_DELAY"

# Open iTerm2 and attach to tmux session
log_info "Opening iTerm2 window..."

# Build AppleScript for iTerm
APPLESCRIPT="tell application \"iTerm\"
    create window with profile \"${ITERM_PROFILE}\"
    tell current session of current window"

# Set font size if specified
if [ -n "$FONT_SIZE" ]; then
    APPLESCRIPT="${APPLESCRIPT}
        set font size to ${FONT_SIZE}"
fi

# Set background color if specified
if [ -n "$BACKGROUND_COLOR" ]; then
    APPLESCRIPT="${APPLESCRIPT}
        set background color to {$(echo "$BACKGROUND_COLOR" | sed 's/#//g' | sed 's/\(..\)/0x\1, /g' | sed 's/, $//')}"
fi

APPLESCRIPT="${APPLESCRIPT}
        write text \"tmux attach -t ${SESSION_NAME}\"
        delay ${SCREENSHOT_DELAY}
    end tell
    "

# Add window maximization if requested
if [ "$MAXIMIZE_WINDOW" = true ]; then
    APPLESCRIPT="${APPLESCRIPT}
    -- Maximize window
    tell application \"System Events\" to tell process \"iTerm2\"
        set value of attribute \"AXFullScreen\" of window 1 to true
    end tell
    delay 1
    "
else
    # Resize window to fit the terminal dimensions
    # Calculate approximate window size based on character dimensions
    # Rough estimates: ~7px per column, ~14px per row, plus chrome
    WINDOW_WIDTH=$((TMUX_WIDTH * 7 + 100))
    WINDOW_HEIGHT=$((TMUX_HEIGHT * 14 + 100))
    
    # Cap at reasonable screen dimensions
    if [ $WINDOW_WIDTH -gt 1800 ]; then
        WINDOW_WIDTH=1800
    fi
    if [ $WINDOW_HEIGHT -gt 1100 ]; then
        WINDOW_HEIGHT=1100
    fi
    
    APPLESCRIPT="${APPLESCRIPT}
    -- Resize window to fit terminal dimensions
    set bounds of current window to {100, 50, $((100 + WINDOW_WIDTH)), $((50 + WINDOW_HEIGHT))}
    "
    
    log_debug "Resizing iTerm window to approximately ${WINDOW_WIDTH}x${WINDOW_HEIGHT} pixels"
fi

APPLESCRIPT="${APPLESCRIPT}
    -- Return window ID
    return id of current window
end tell"

# Execute AppleScript and get window ID
ITERM_WINDOW_ID=$(osascript -e "$APPLESCRIPT" 2>&1)
if [ $? -ne 0 ]; then
    log_error "Failed to create iTerm window or get window ID"
    log_error "AppleScript output: $ITERM_WINDOW_ID"
    exit 1
fi
log_debug "iTerm window ID: $ITERM_WINDOW_ID"

# Verify we got a valid window ID (should be a number)
if ! [[ "$ITERM_WINDOW_ID" =~ ^[0-9]+$ ]]; then
    log_error "Invalid window ID received: $ITERM_WINDOW_ID"
    log_error "Trying alternative method to get window ID..."
    sleep 2
    ITERM_WINDOW_ID=$(osascript -e 'tell application "iTerm" to return id of front window' 2>&1)
    if ! [[ "$ITERM_WINDOW_ID" =~ ^[0-9]+$ ]]; then
        log_error "Still couldn't get valid window ID: $ITERM_WINDOW_ID"
        exit 1
    fi
    log_debug "Got window ID using alternative method: $ITERM_WINDOW_ID"
fi

# Additional delay for terminal to stabilize
sleep "$SCREENSHOT_DELAY"

# Prepare screencapture options
SCREENCAPTURE_OPTS="-l${ITERM_WINDOW_ID}"

if [ "$HIDE_SHADOW" = true ]; then
    SCREENCAPTURE_OPTS="${SCREENCAPTURE_OPTS} -o"
fi

if [ "$WINDOW_ONLY" = true ]; then
    SCREENCAPTURE_OPTS="${SCREENCAPTURE_OPTS} -B"
fi

# Debug: Test if screencapture works at all
if [ "$DEBUG" = true ]; then
    log_debug "Testing basic screencapture functionality..."
    TEST_FILE="/tmp/test_screencapture_$.png"
    if screencapture -x "$TEST_FILE" 2>&1; then
        if [ -f "$TEST_FILE" ]; then
            log_debug "Basic screencapture works (created $TEST_FILE)"
            rm -f "$TEST_FILE"
        else
            log_debug "screencapture command succeeded but no file created"
        fi
    else
        log_debug "Basic screencapture command failed - may need permissions"
    fi
fi

# Take screenshot
log_info "Taking screenshot..."
log_debug "Output file path: ${OUTPUT_FILE}"
log_debug "screencapture command: screencapture ${SCREENCAPTURE_OPTS} \"${OUTPUT_FILE}\""

# Try to capture the screenshot
if ! screencapture ${SCREENCAPTURE_OPTS} "${OUTPUT_FILE}" 2>&1; then
    log_error "screencapture command failed"
    log_error "Attempting fallback without window ID..."
    
    # Try without window ID (will capture after a click)
    log_info "Click on the iTerm window within 5 seconds..."
    if ! screencapture -o -i "${OUTPUT_FILE}" 2>&1; then
        log_error "Fallback screencapture also failed"
        log_error "Please check:"
        log_error "  1. Screen Recording permissions in System Preferences > Security & Privacy > Privacy > Screen Recording"
        log_error "  2. Terminal/iTerm2 has permission to control your computer"
        exit 1
    fi
fi

# Verify the file was actually created
if [ ! -f "${OUTPUT_FILE}" ]; then
    log_error "Screenshot file was not created: ${OUTPUT_FILE}"
    log_error "Checking current directory for screenshot.png..."
    if [ -f "screenshot.png" ]; then
        log_error "Found screenshot.png in current directory - moving to ${OUTPUT_FILE}"
        mv "screenshot.png" "${OUTPUT_FILE}"
    elif [ -f "${WORKING_DIR}/screenshot.png" ]; then
        log_error "Found screenshot.png in working directory - moving to ${OUTPUT_FILE}"
        mv "${WORKING_DIR}/screenshot.png" "${OUTPUT_FILE}"
    else
        log_error "Directory contents of $(pwd):"
        ls -la "$(pwd)" | head -10
        
        # Try one more time with interactive mode
        log_info "Trying interactive screenshot - press space and click the iTerm window..."
        screencapture -i -o "${OUTPUT_FILE}"
        
        if [ ! -f "${OUTPUT_FILE}" ]; then
            log_error "Failed to create screenshot file after multiple attempts"
            log_error "Please ensure you have granted screen recording permissions to Terminal/iTerm2"
            exit 1
        fi
    fi
fi

log_debug "Screenshot file created: $(ls -la "${OUTPUT_FILE}" 2>/dev/null || echo 'File info not available')"

# Crop if requested
if [ "$CROP_SCREENSHOT" = true ]; then
    log_info "Cropping screenshot (top:${CROP_TOP} bottom:${CROP_BOTTOM} left:${CROP_LEFT} right:${CROP_RIGHT})"
    
    # Get image dimensions
    WIDTH=$(sips -g pixelWidth "${OUTPUT_FILE}" | tail -n1 | cut -d' ' -f4)
    HEIGHT=$(sips -g pixelHeight "${OUTPUT_FILE}" | tail -n1 | cut -d' ' -f4)
    
    # Calculate new dimensions
    NEW_WIDTH=$((WIDTH - CROP_LEFT - CROP_RIGHT))
    NEW_HEIGHT=$((HEIGHT - CROP_TOP - CROP_BOTTOM))
    
    # Create temporary file
    TEMP_FILE="${OUTPUT_FILE}.tmp.png"
    
    # Crop using sips
    sips "${OUTPUT_FILE}" \
         --cropOffset "$CROP_LEFT" "$CROP_TOP" \
         --cropToHeightWidth "$NEW_HEIGHT" "$NEW_WIDTH" \
         --out "${TEMP_FILE}" > /dev/null 2>&1
    
    mv "${TEMP_FILE}" "${OUTPUT_FILE}"
fi

# Report success
if [ -f "${OUTPUT_FILE}" ]; then
    FILE_SIZE=$(du -h "${OUTPUT_FILE}" | cut -f1)
    IMAGE_INFO=$(sips -g pixelWidth -g pixelHeight "${OUTPUT_FILE}" 2>/dev/null | tail -n2 | awk '{print $4}' | tr '\n' 'x' | sed 's/x$//')
    
    log_info "${GREEN}Screenshot saved successfully!${NC}"
    log_info "  File: ${OUTPUT_FILE}"
    log_info "  Size: ${FILE_SIZE}"
    if [ -n "$IMAGE_INFO" ] && [ "$IMAGE_INFO" != "x" ]; then
        log_info "  Dimensions: ${IMAGE_INFO}"
    fi
else
    log_error "Screenshot was not created successfully"
    exit 1
fi

if [ "$KEEP_SESSION" = true ]; then
    log_info "  Session: ${SESSION_NAME} (still running)"
    echo ""
    log_info "To re-attach to the session:"
    echo "  tmux attach -t ${SESSION_NAME}"
fi
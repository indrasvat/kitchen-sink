#!/usr/bin/env bash

# zellij-screenshot.sh - Automated CLI Screenshot Tool for macOS with iTerm2 using Zellij
# Zellij supports Sixel graphics protocol which may work better with images
# Usage: ./zellij-screenshot.sh [options] -- command [args...]
#
# Examples:
#   ./zellij-screenshot.sh -- ls -la
#   ./zellij-screenshot.sh -o screenshot.png -d 2 -- "npm start"
#   ./zellij-screenshot.sh -w 150 -h 50 -p "My Profile" -- ./my-cli --help
#   ./zellij-screenshot.sh -D /path/to/project -e "source venv/bin/activate" -- python app.py

# Don't exit on error during getopt
set +e

# Default values
SESSION_NAME="zellij_screenshot_$$"
OUTPUT_FILE="screenshot.png"
PANE_WIDTH=120
PANE_HEIGHT=40
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
LAYOUT_FILE=""

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

Automated CLI screenshot tool using Zellij and iTerm2 on macOS.
Zellij has better support for graphics protocols than tmux.

OPTIONS:
    -o, --output FILE          Output screenshot file (default: screenshot.png)
    -s, --session NAME         Zellij session name (default: auto-generated)
    -w, --width COLS          Terminal width in columns (default: 120)
    -h, --height ROWS         Terminal height in rows (default: 40)
    -d, --delay SECONDS       Delay after command execution (default: 2)
    -D, --directory PATH      Working directory for command (default: current)
    -p, --profile NAME        iTerm2 profile name (default: Default)
    -e, --pre-command CMD     Commands to run before main command (can be used multiple times)
    -E, --post-command CMD    Commands to run after main command (can be used multiple times)
    -k, --keep-session        Keep Zellij session after screenshot
    -c, --crop T:B:L:R        Crop screenshot (top:bottom:left:right pixels)
    -n, --no-clear            Don't clear screen before running command
    -W, --window-only         Capture only window content (no decorations)
    -S, --show-shadow         Show window shadow in screenshot
    -M, --maximize            Maximize iTerm2 window
    -f, --font-size SIZE      Set font size in iTerm2 (e.g., 14)
    -b, --bg-color COLOR      Set background color (hex, e.g., "#1e1e1e")
    -l, --layout FILE         Use custom Zellij layout file
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

    # Display image with imgcat (Zellij may preserve it better than tmux)
    $0 -e "imgcat logo.png" -d 3 -- echo "Image above should be visible"

    # Full featured example
    $0 -o demo.png -w 150 -h 50 -d 3 -D ~/myapp \\
       -e "nvm use 18" -e "npm install" \\
       -f 16 -b "#282c34" \\
       -- npm run dev

NOTE: Zellij has better support for graphics protocols than tmux. 
      Images displayed with imgcat may be preserved in the screenshot.

EOF
    exit 0
}

# Parse command line arguments
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
            PANE_WIDTH="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -h|--height)
            PANE_HEIGHT="${ARGS[$((i+1))]}"
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
        -l|--layout)
            LAYOUT_FILE="${ARGS[$((i+1))]}"
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

# Check if zellij is installed
if ! command -v zellij &> /dev/null; then
    log_error "Zellij is not installed. Please install it first:"
    log_error "  brew install zellij"
    exit 1
fi

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
        log_debug "Cleaning up Zellij session: $SESSION_NAME"
        zellij delete-session "$SESSION_NAME" --force 2>/dev/null || true
    else
        log_info "Zellij session kept alive: $SESSION_NAME"
        log_info "Attach with: zellij attach $SESSION_NAME"
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
if zellij list-sessions 2>/dev/null | grep -q "^$SESSION_NAME"; then
    log_info "Killing existing session: $SESSION_NAME"
    zellij delete-session "$SESSION_NAME" --force 2>/dev/null || true
fi

# Create temporary script file for commands
TEMP_SCRIPT="/tmp/zellij_commands_$$.sh"
cat > "$TEMP_SCRIPT" << SCRIPT_EOF
#!/bin/bash
cd "$WORKING_DIR"

# Clear screen if requested
$([ "$CLEAR_SCREEN" = true ] && echo "clear")

# Execute pre-commands
$(if [ -n "$PRE_COMMANDS" ]; then
    IFS=';' read -ra COMMANDS <<< "$PRE_COMMANDS"
    for cmd in "${COMMANDS[@]}"; do
        [ -n "$cmd" ] && echo "$cmd"
    done
fi)

# Execute main command
$COMMAND

# Execute post-commands
$(if [ -n "$POST_COMMANDS" ]; then
    IFS=';' read -ra COMMANDS <<< "$POST_COMMANDS"
    for cmd in "${COMMANDS[@]}"; do
        [ -n "$cmd" ] && echo "$cmd"
    done
fi)

# Keep shell open
exec bash
SCRIPT_EOF

chmod +x "$TEMP_SCRIPT"

# Create Zellij session in detached mode
log_info "Creating Zellij session: $SESSION_NAME (${PANE_WIDTH}x${PANE_HEIGHT})"

# Start Zellij session detached with initial command
export ZELLIJ_AUTO_ATTACH=false
export ZELLIJ_AUTO_EXIT=false

# Open iTerm2 first and create the Zellij session inside it
log_info "Opening iTerm2 and creating Zellij session..."

# Build AppleScript to create iTerm window with Zellij session
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

# Start zellij session with options to disable welcome and start in the right directory
APPLESCRIPT="${APPLESCRIPT}
        write text \"cd '$WORKING_DIR'\"
        delay 0.5
        write text \"zellij --session ${SESSION_NAME} --disable-welcome\"
        delay 2"

# Now we need to send commands AFTER zellij has started
# Clear screen if requested
if [ "$CLEAR_SCREEN" = true ]; then
    APPLESCRIPT="${APPLESCRIPT}
        write text \"clear\"
        delay 0.2"
fi

# Execute pre-commands
if [ -n "$PRE_COMMANDS" ]; then
    log_info "Executing pre-commands..."
    IFS=';' read -ra COMMANDS <<< "$PRE_COMMANDS"
    for cmd in "${COMMANDS[@]}"; do
        if [ -n "$cmd" ]; then
            log_debug "Executing pre-command: '$cmd'"
            APPLESCRIPT="${APPLESCRIPT}
        write text \"$cmd\"
        delay 0.5"
        fi
    done
fi

# Execute main command
log_info "Executing command: $COMMAND"
APPLESCRIPT="${APPLESCRIPT}
        write text \"$COMMAND\"
        delay 0.5"

# Execute post-commands
if [ -n "$POST_COMMANDS" ]; then
    log_info "Executing post-commands..."
    IFS=';' read -ra COMMANDS <<< "$POST_COMMANDS"
    for cmd in "${COMMANDS[@]}"; do
        if [ -n "$cmd" ]; then
            APPLESCRIPT="${APPLESCRIPT}
        write text \"$cmd\"
        delay 0.5"
        fi
    done
fi

# Wait for command to complete
APPLESCRIPT="${APPLESCRIPT}
        delay ${COMMAND_DELAY}
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
    WINDOW_WIDTH=$((PANE_WIDTH * 7 + 100))
    WINDOW_HEIGHT=$((PANE_HEIGHT * 14 + 100))
    
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

# Verify we got a valid window ID
if ! [[ "$ITERM_WINDOW_ID" =~ ^[0-9]+$ ]]; then
    log_error "Invalid window ID received: $ITERM_WINDOW_ID"
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

# Take screenshot
log_info "Taking screenshot..."
log_debug "screencapture command: screencapture ${SCREENCAPTURE_OPTS} \"${OUTPUT_FILE}\""

# Try to capture the screenshot
if ! screencapture ${SCREENCAPTURE_OPTS} "${OUTPUT_FILE}" 2>&1; then
    log_error "screencapture command failed"
    log_error "Attempting fallback without window ID..."
    
    log_info "Click on the iTerm window within 5 seconds..."
    if ! screencapture -o -i "${OUTPUT_FILE}" 2>&1; then
        log_error "Fallback screencapture also failed"
        log_error "Please check Screen Recording permissions"
        exit 1
    fi
fi

# Verify the file was created
if [ ! -f "${OUTPUT_FILE}" ]; then
    log_error "Screenshot file was not created: ${OUTPUT_FILE}"
    exit 1
fi

# Crop if requested
if [ "$CROP_SCREENSHOT" = true ]; then
    log_info "Cropping screenshot (top:${CROP_TOP} bottom:${CROP_BOTTOM} left:${CROP_LEFT} right:${CROP_RIGHT})"
    
    WIDTH=$(sips -g pixelWidth "${OUTPUT_FILE}" | tail -n1 | cut -d' ' -f4)
    HEIGHT=$(sips -g pixelHeight "${OUTPUT_FILE}" | tail -n1 | cut -d' ' -f4)
    
    NEW_WIDTH=$((WIDTH - CROP_LEFT - CROP_RIGHT))
    NEW_HEIGHT=$((HEIGHT - CROP_TOP - CROP_BOTTOM))
    
    TEMP_FILE="${OUTPUT_FILE}.tmp.png"
    
    sips "${OUTPUT_FILE}" \
         --cropOffset "$CROP_LEFT" "$CROP_TOP" \
         --cropToHeightWidth "$NEW_HEIGHT" "$NEW_WIDTH" \
         --out "${TEMP_FILE}" > /dev/null 2>&1
    
    mv "${TEMP_FILE}" "${OUTPUT_FILE}"
fi

# Clean up temp script
rm -f "$TEMP_SCRIPT"

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
    echo "  zellij attach ${SESSION_NAME}"
fi
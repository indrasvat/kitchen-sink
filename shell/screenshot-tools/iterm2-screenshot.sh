#!/usr/bin/env bash

# iterm2-screenshot.sh - Direct iTerm2 Screenshot Tool for macOS (no tmux/zellij)
# This version controls iTerm2 directly, preserving inline images from imgcat
# Usage: ./iterm2-screenshot.sh [options] -- command [args...]
#
# Examples:
#   ./iterm2-screenshot.sh -- ls -la
#   ./iterm2-screenshot.sh -o screenshot.png -d 2 -- "npm start"
#   ./iterm2-screenshot.sh -w 150 -h 50 -p "My Profile" -- ./my-cli --help
#   ./iterm2-screenshot.sh -D /path/to/project -e "source venv/bin/activate" -- python app.py
#   ./iterm2-screenshot.sh -e "imgcat logo.png" -d 3 -- echo "Logo displayed above"

# Don't exit on error during getopt
set +e

# Default values
OUTPUT_FILE="screenshot.png"
TERMINAL_WIDTH=120
TERMINAL_HEIGHT=40
COMMAND_DELAY=2
SCREENSHOT_DELAY=1
WORKING_DIR="$PWD"
KEEP_WINDOW=false
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
USE_EXISTING_WINDOW=false
WAIT_FOR_KEYPRESS=false

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

Direct iTerm2 screenshot tool for macOS - no terminal multiplexer required.
Preserves iTerm2 inline images (imgcat) perfectly since no tmux/zellij is involved.

OPTIONS:
    -o, --output FILE          Output screenshot file (default: screenshot.png)
    -w, --width COLS          Terminal width in columns (default: 120)
    -h, --height ROWS         Terminal height in rows (default: 40)
    -d, --delay SECONDS       Delay after command execution (default: 2)
    -D, --directory PATH      Working directory for command (default: current)
    -p, --profile NAME        iTerm2 profile name (default: Default)
    -e, --pre-command CMD     Commands to run before main command (can be used multiple times)
    -E, --post-command CMD    Commands to run after main command (can be used multiple times)
    -k, --keep-window         Keep iTerm2 window open after screenshot
    -c, --crop T:B:L:R        Crop screenshot (top:bottom:left:right pixels)
    -n, --no-clear            Don't clear screen before running command
    -W, --window-only         Capture only window content (no decorations)
    -S, --show-shadow         Show window shadow in screenshot
    -M, --maximize            Maximize iTerm2 window
    -f, --font-size SIZE      Set font size in iTerm2 (e.g., 14)
    -b, --bg-color COLOR      Set background color (hex, e.g., "#1e1e1e")
    -x, --use-existing        Use existing iTerm2 window instead of creating new one
    -K, --wait-keypress       Wait for keypress before taking screenshot
    --screenshot-delay SEC    Delay before taking screenshot (default: 1)
    --debug                   Enable debug output
    --help                    Show this help message

COMMAND:
    The command to execute and screenshot. Use quotes for complex commands.

EXAMPLES:
    # Simple command
    $0 -- ls -la

    # Display image with imgcat (will be captured properly!)
    $0 -e "imgcat ~/Pictures/logo.png" -d 3 -- echo "Logo above is captured"

    # Custom output file and dimensions
    $0 -o help.png -w 100 -h 30 -- ./my-cli --help

    # With working directory and pre-commands
    $0 -D ~/project -e "source venv/bin/activate" -- python app.py

    # Multiple pre-commands with custom profile
    $0 -p "Presentation" -e "clear" -e "echo 'Demo Time!'" -- npm start

    # Use existing window (run commands in current iTerm2 session)
    $0 -x -o output.png -- htop

    # Wait for keypress before screenshot (useful for interactive commands)
    $0 -K -d 5 -- vim myfile.txt

    # Full featured example with image
    $0 -o demo.png -w 150 -h 50 -d 3 -D ~/myapp \\
       -e "imgcat logo.png" \\
       -e "echo '=== MyApp Demo ==='" \\
       -f 16 -b "#282c34" \\
       -- npm run dev

ADVANTAGES:
    - Captures iTerm2 inline images (imgcat) perfectly
    - No terminal multiplexer overhead or limitations
    - Direct control over iTerm2 via AppleScript
    - Faster execution than tmux/zellij versions
    - Better color and font rendering

EOF
    exit 0
}

# Parse command line arguments
ARGS=("$@")
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
        -w|--width)
            TERMINAL_WIDTH="${ARGS[$((i+1))]}"
            ((i+=2))
            ;;
        -h|--height)
            TERMINAL_HEIGHT="${ARGS[$((i+1))]}"
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
        -k|--keep-window)
            KEEP_WINDOW=true
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
        -x|--use-existing)
            USE_EXISTING_WINDOW=true
            ((i++))
            ;;
        -K|--wait-keypress)
            WAIT_FOR_KEYPRESS=true
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
    log_debug "WORKING_DIR: $WORKING_DIR"
    log_debug "COMMAND: $COMMAND"
    log_debug "PRE_COMMANDS: $PRE_COMMANDS"
    log_debug "COMMAND_DELAY: $COMMAND_DELAY"
    log_debug "USE_EXISTING_WINDOW: $USE_EXISTING_WINDOW"
    log_debug "=========================="
fi

# Function to cleanup
cleanup() {
    # Close iTerm window if we opened it (and not keeping window)
    if [ "$KEEP_WINDOW" = false ] && [ "$USE_EXISTING_WINDOW" = false ] && [ -n "$ITERM_WINDOW_ID" ]; then
        log_debug "Closing iTerm window"
        osascript -e "tell application \"iTerm\" to close (every window whose id is $ITERM_WINDOW_ID)" 2>/dev/null || true
    elif [ "$KEEP_WINDOW" = true ]; then
        log_info "iTerm2 window kept open"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Build AppleScript commands
build_commands() {
    local commands=""
    
    # Change directory
    commands="cd '$WORKING_DIR'"$'\n'
    
    # Clear screen if requested
    if [ "$CLEAR_SCREEN" = true ]; then
        commands="${commands}clear"$'\n'
    fi
    
    # Add pre-commands
    if [ -n "$PRE_COMMANDS" ]; then
        IFS=';' read -ra CMDS <<< "$PRE_COMMANDS"
        for cmd in "${CMDS[@]}"; do
            [ -n "$cmd" ] && commands="${commands}${cmd}"$'\n'
        done
    fi
    
    # Add main command
    commands="${commands}${COMMAND}"$'\n'
    
    # Add post-commands
    if [ -n "$POST_COMMANDS" ]; then
        IFS=';' read -ra CMDS <<< "$POST_COMMANDS"
        for cmd in "${CMDS[@]}"; do
            [ -n "$cmd" ] && commands="${commands}${cmd}"$'\n'
        done
    fi
    
    # Add wait for keypress if requested
    if [ "$WAIT_FOR_KEYPRESS" = true ]; then
        commands="${commands}echo 'Press any key to take screenshot...'; read -n 1"$'\n'
    fi
    
    echo "$commands"
}

# Get commands to execute
COMMANDS_TO_RUN=$(build_commands)
log_debug "Commands to run:"
log_debug "$COMMANDS_TO_RUN"

if [ "$USE_EXISTING_WINDOW" = true ]; then
    # Use existing iTerm2 window
    log_info "Using existing iTerm2 window..."
    
    # Build AppleScript for existing window
    APPLESCRIPT="tell application \"iTerm\"
        tell current session of current window"
    
    # Send each command
    while IFS=$'\n' read -r cmd; do
        if [ -n "$cmd" ]; then
            APPLESCRIPT="${APPLESCRIPT}
            write text \"$cmd\""
        fi
    done <<< "$COMMANDS_TO_RUN"
    
    APPLESCRIPT="${APPLESCRIPT}
            delay ${COMMAND_DELAY}
        end tell
        return id of current window
    end tell"
    
    # Execute AppleScript
    if ! ITERM_WINDOW_ID=$(osascript -e "$APPLESCRIPT" 2>&1); then
        log_error "Failed to use existing iTerm window or get window ID"
        log_error "AppleScript output: $ITERM_WINDOW_ID"
        exit 1
    fi

else
    # Create new iTerm2 window
    log_info "Creating new iTerm2 window..."
    
    # Build AppleScript for new window
    APPLESCRIPT="tell application \"iTerm\"
        create window with profile \"${ITERM_PROFILE}\"
        tell current session of current window"
    
    # Set terminal size
    APPLESCRIPT="${APPLESCRIPT}
            set columns to ${TERMINAL_WIDTH}
            set rows to ${TERMINAL_HEIGHT}"
    
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
    
    # Send each command
    while IFS=$'\n' read -r cmd; do
        if [ -n "$cmd" ]; then
            APPLESCRIPT="${APPLESCRIPT}
            write text \"$cmd\""
        fi
    done <<< "$COMMANDS_TO_RUN"
    
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
        WINDOW_WIDTH=$((TERMINAL_WIDTH * 7 + 100))
        WINDOW_HEIGHT=$((TERMINAL_HEIGHT * 14 + 100))
        
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
    if ! ITERM_WINDOW_ID=$(osascript -e "$APPLESCRIPT" 2>&1); then
        log_error "Failed to create new iTerm window or get window ID"
        log_error "AppleScript output: $ITERM_WINDOW_ID"
        exit 1
    fi
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

# Wait for commands to complete
log_info "Waiting for commands to complete..."
sleep "$COMMAND_DELAY"

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
# shellcheck disable=SC2086 # SCREENCAPTURE_OPTS needs word splitting
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
    
    if [ "$USE_EXISTING_WINDOW" = true ]; then
        log_info "  Note: Used existing iTerm2 window"
    fi
else
    log_error "Screenshot was not created successfully"
    exit 1
fi

if [ "$KEEP_WINDOW" = true ] && [ "$USE_EXISTING_WINDOW" = false ]; then
    log_info "  Window: Kept open (ID: ${ITERM_WINDOW_ID})"
fi
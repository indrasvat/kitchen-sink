#!/usr/bin/env bash
#
# ChatGPT Receipt Downloader - Interactive Setup Wizard
#
# This wizard guides you through the initial configuration:
#   1. Email recipient
#   2. Chrome profile selection
#   3. LLM provider (Bedrock/OpenAI/Anthropic)
#   4. AWS profile (if using Bedrock)
#   5. Schedule preferences
#
# Run: ./setup.sh
#      ./setup.sh --dry-run    # Preview what would be configured
#

set -e

# ══════════════════════════════════════════════════════════════════════════════
# COLORS (defined early for error_exit)
# ══════════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ══════════════════════════════════════════════════════════════════════════════
# ERROR HANDLING
# ══════════════════════════════════════════════════════════════════════════════

# Store the selected choice (used by select_option)
SELECTED_CHOICE=""

cleanup() {
    # Reset terminal on exit
    tput cnorm 2>/dev/null || true  # Show cursor
}
trap cleanup EXIT

error_exit() {
    local message="$1"
    local code="${2:-1}"

    echo "" >&2
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${RED}║${NC}${BOLD}                         ERROR                                       ${NC}${RED}║${NC}" >&2
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
    echo -e "  ${RED}✗${NC} $message" >&2
    echo "" >&2
    echo -e "  ${DIM}If this seems like a bug, please report it.${NC}" >&2
    echo "" >&2

    exit "$code"
}

# ══════════════════════════════════════════════════════════════════════════════
# COMMAND LINE ARGUMENTS
# ══════════════════════════════════════════════════════════════════════════════

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./setup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run, -n    Preview configuration without making changes"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run './setup.sh --help' for usage"
            exit 1
            ;;
    esac
done

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# Terminal width for formatting
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
if [[ $TERM_WIDTH -gt 80 ]]; then
    TERM_WIDTH=80
fi

print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}           ChatGPT Receipt Downloader - Setup Wizard                ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local title=$3
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Step $step of $total: $title${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

# Read input with default value
read_with_default() {
    local prompt=$1
    local default=$2
    local var_name=$3

    if [[ -n "$default" ]]; then
        echo -ne "${prompt} ${DIM}[$default]${NC}: "
    else
        echo -ne "${prompt}: "
    fi

    read -r input
    if [[ -z "$input" ]]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$input'"
    fi
}

# Yes/No prompt
confirm() {
    local prompt=$1
    local default=${2:-y}

    if [[ "$default" == "y" ]]; then
        echo -ne "${prompt} ${DIM}[Y/n]${NC}: "
    else
        echo -ne "${prompt} ${DIM}[y/N]${NC}: "
    fi

    read -r -n 1 response
    echo ""

    if [[ -z "$response" ]]; then
        response=$default
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# Select from numbered options
# Sets SELECTED_CHOICE to the 0-based index of the selected option
select_option() {
    local prompt=$1
    shift
    local options=("$@")
    local count=${#options[@]}

    echo "$prompt"
    echo ""

    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i+1))${NC}) ${options[$i]}"
    done

    echo ""
    while true; do
        echo -ne "Enter choice ${DIM}[1-$count]${NC}: "
        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $count ]]; then
            SELECTED_CHOICE=$((choice - 1))
            return 0
        else
            echo -e "${RED}Invalid choice. Please enter a number between 1 and $count.${NC}"
        fi
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# DETECTION FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

detect_chrome_profiles() {
    local chrome_dir="$HOME/Library/Application Support/Google/Chrome"

    if [[ -d "$chrome_dir" ]]; then
        # Always include Default if it exists
        if [[ -d "$chrome_dir/Default" ]]; then
            echo "Default"
        fi

        # Find Profile N directories
        for dir in "$chrome_dir"/Profile\ *; do
            if [[ -d "$dir" ]]; then
                basename "$dir"
            fi
        done
    fi
}

detect_aws_profiles() {
    local -A seen=()
    local creds_file="$HOME/.aws/credentials"
    local config_file="$HOME/.aws/config"

    # Parse credentials file
    if [[ -f "$creds_file" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
                local profile="${BASH_REMATCH[1]}"
                if [[ -z "${seen[$profile]:-}" ]]; then
                    seen[$profile]=1
                    echo "$profile"
                fi
            fi
        done < "$creds_file"
    fi

    # Parse config file (profiles are prefixed with "profile ")
    if [[ -f "$config_file" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[profile\ ([^\]]+)\]$ ]]; then
                local profile="${BASH_REMATCH[1]}"
                if [[ -z "${seen[$profile]:-}" ]]; then
                    seen[$profile]=1
                    echo "$profile"
                fi
            fi
        done < "$config_file"
    fi
}

get_chrome_profile_name() {
    local profile_dir=$1
    local chrome_dir="$HOME/Library/Application Support/Google/Chrome"
    local prefs_file="$chrome_dir/$profile_dir/Preferences"

    if [[ -f "$prefs_file" ]]; then
        # Try to extract the profile name from Preferences JSON
        local name
        name=$(python3 -c "
import json
try:
    with open('$prefs_file') as f:
        prefs = json.load(f)
    print(prefs.get('profile', {}).get('name', '$profile_dir'))
except:
    print('$profile_dir')
" 2>/dev/null)
        echo "$name"
    else
        echo "$profile_dir"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# VALIDATION FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

validate_email() {
    local email=$1
    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_prerequisites() {
    local missing=0

    echo "Checking prerequisites..."
    echo ""

    # Check uv
    if command -v uv &> /dev/null; then
        print_success "uv is installed ($(uv --version 2>/dev/null | head -1))"
    else
        print_error "'uv' is not installed"
        echo ""
        echo "    Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo ""
        missing=1
    fi

    # Check Chrome
    if [[ -d "/Applications/Google Chrome.app" ]]; then
        print_success "Google Chrome is installed"
    else
        print_error "Google Chrome not found"
        missing=1
    fi

    # Check Python
    if command -v python3 &> /dev/null; then
        print_success "Python 3 is installed ($(python3 --version 2>/dev/null))"
    else
        print_error "Python 3 not found"
        missing=1
    fi

    return $missing
}

# ══════════════════════════════════════════════════════════════════════════════
# WIZARD STEPS
# ══════════════════════════════════════════════════════════════════════════════

step_welcome() {
    print_header

    echo "Welcome! This wizard will help you set up automatic monthly"
    echo "downloading of your ChatGPT Plus receipts."
    echo ""
    echo -e "${BOLD}What this tool does:${NC}"
    echo "  • Downloads your ChatGPT Plus receipt at the end of each month"
    echo "  • Optionally emails it to you (via Outlook/M365)"
    echo "  • Runs automatically in the background"
    echo ""
    echo -e "${BOLD}Requirements:${NC}"
    echo "  • Google Chrome with active ChatGPT login"
    echo "  • API access (AWS Bedrock, OpenAI, or Anthropic)"
    echo "  • Optional: Microsoft 365 account for email"
    echo ""

    if ! confirm "Ready to begin?"; then
        echo ""
        echo "Setup cancelled. Run ./setup.sh when you're ready."
        exit 0
    fi
}

step_prerequisites() {
    print_header
    print_step 1 6 "Prerequisites Check"

    if ! check_prerequisites; then
        echo ""
        print_error "Please install missing prerequisites and run setup again."
        exit 1
    fi

    echo ""
    print_success "All prerequisites met!"
    echo ""
    read -rp "Press Enter to continue..."
}

step_email() {
    print_header
    print_step 2 6 "Email Configuration"

    echo "Where should the receipt be emailed?"
    echo ""
    echo -e "${DIM}The receipt will be sent via Microsoft Outlook (M365).${NC}"
    echo -e "${DIM}Make sure you're logged into Outlook in Chrome.${NC}"
    echo ""

    while true; do
        read_with_default "Email address" "" EMAIL_TO

        if [[ -z "$EMAIL_TO" ]]; then
            if confirm "Skip email? (receipt will only be saved locally)" "n"; then
                EMAIL_TO=""
                break
            fi
        elif validate_email "$EMAIL_TO"; then
            print_success "Email set to: $EMAIL_TO"
            break
        else
            print_error "Invalid email format. Please try again."
        fi
    done

    echo ""
    read -rp "Press Enter to continue..."
}

step_chrome_profile() {
    print_header
    print_step 3 6 "Chrome Profile"

    echo "Which Chrome profile has your ChatGPT login?"
    echo ""
    echo -e "${DIM}The script uses your existing Chrome session to access ChatGPT.${NC}"
    echo ""

    # Detect available profiles (newline-separated to handle spaces in names)
    local PROFILES=()
    while IFS= read -r profile; do
        [[ -n "$profile" ]] && PROFILES+=("$profile")
    done < <(detect_chrome_profiles)

    if [[ ${#PROFILES[@]} -eq 0 ]]; then
        print_warn "No Chrome profiles found. Using 'Default'."
        CHROME_PROFILE="Default"
    elif [[ ${#PROFILES[@]} -eq 1 ]]; then
        CHROME_PROFILE="${PROFILES[0]}"
        print_info "Found one profile: $CHROME_PROFILE"
    else
        # Build options with friendly names
        local options=()
        for profile in "${PROFILES[@]}"; do
            local friendly_name
            friendly_name=$(get_chrome_profile_name "$profile")
            if [[ "$friendly_name" != "$profile" ]]; then
                options+=("$profile ($friendly_name)")
            else
                options+=("$profile")
            fi
        done
        options+=("Enter manually...")

        select_option "Select your Chrome profile:" "${options[@]}"

        if [[ $SELECTED_CHOICE -eq ${#PROFILES[@]} ]]; then
            # Manual entry
            read_with_default "Enter Chrome profile directory name" "Default" CHROME_PROFILE
        else
            CHROME_PROFILE="${PROFILES[$SELECTED_CHOICE]}"
        fi
    fi

    echo ""
    print_success "Chrome profile: $CHROME_PROFILE"
    echo ""
    read -rp "Press Enter to continue..."
}

step_llm_provider() {
    print_header
    print_step 4 6 "LLM Provider"

    echo "Which LLM provider do you want to use?"
    echo ""
    echo -e "${DIM}The script uses an LLM to navigate ChatGPT and Outlook.${NC}"
    echo ""

    local options=(
        "AWS Bedrock (Claude Opus 4.5) - Recommended"
        "Anthropic API (Claude Sonnet)"
        "OpenAI API (GPT-4)"
    )

    select_option "Select your LLM provider:" "${options[@]}"

    case $SELECTED_CHOICE in
        0) LLM_PROVIDER="bedrock" ;;
        1) LLM_PROVIDER="anthropic" ;;
        2) LLM_PROVIDER="openai" ;;
    esac

    echo ""
    print_success "LLM provider: $LLM_PROVIDER"

    # Provider-specific configuration
    case $LLM_PROVIDER in
        bedrock)
            echo ""
            echo -e "${BOLD}AWS Bedrock Configuration${NC}"
            echo ""

            # Detect AWS profiles (newline-separated to handle spaces in names)
            local AWS_PROFILES=()
            while IFS= read -r profile; do
                [[ -n "$profile" ]] && AWS_PROFILES+=("$profile")
            done < <(detect_aws_profiles)

            if [[ ${#AWS_PROFILES[@]} -eq 0 ]]; then
                print_warn "No AWS profiles found in ~/.aws/credentials"
                read_with_default "Enter AWS profile name" "default" AWS_PROFILE
            else
                local options=("${AWS_PROFILES[@]}")
                options+=("Enter manually...")

                select_option "Select your AWS profile:" "${options[@]}"

                if [[ $SELECTED_CHOICE -eq ${#AWS_PROFILES[@]} ]]; then
                    read_with_default "Enter AWS profile name" "default" AWS_PROFILE
                else
                    AWS_PROFILE="${AWS_PROFILES[$SELECTED_CHOICE]}"
                fi
            fi

            print_success "AWS profile: $AWS_PROFILE"
            ;;

        anthropic)
            echo ""
            if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
                print_success "ANTHROPIC_API_KEY is set"
            else
                print_warn "ANTHROPIC_API_KEY not found in environment"
                echo ""
                echo "    Make sure to set it before running:"
                echo "    export ANTHROPIC_API_KEY='sk-ant-...'"
            fi
            AWS_PROFILE=""
            ;;

        openai)
            echo ""
            if [[ -n "${OPENAI_API_KEY:-}" ]]; then
                print_success "OPENAI_API_KEY is set"
            else
                print_warn "OPENAI_API_KEY not found in environment"
                echo ""
                echo "    Make sure to set it before running:"
                echo "    export OPENAI_API_KEY='sk-...'"
            fi
            AWS_PROFILE=""
            ;;
    esac

    echo ""
    read -rp "Press Enter to continue..."
}

step_schedule() {
    print_header
    print_step 5 6 "Schedule"

    echo "When should the receipt be downloaded?"
    echo ""
    echo -e "${DIM}The job runs on days 28-31 of each month (to catch${NC}"
    echo -e "${DIM}the last day regardless of month length).${NC}"
    echo ""

    local options=(
        "11:00 AM (recommended)"
        "9:00 AM"
        "2:00 PM"
        "6:00 PM"
        "Custom time..."
    )

    select_option "Select preferred time:" "${options[@]}"

    case $SELECTED_CHOICE in
        0) SCHEDULE_HOUR=11 ;;
        1) SCHEDULE_HOUR=9 ;;
        2) SCHEDULE_HOUR=14 ;;
        3) SCHEDULE_HOUR=18 ;;
        4)
            while true; do
                read_with_default "Enter hour (0-23)" "11" SCHEDULE_HOUR
                if [[ "$SCHEDULE_HOUR" =~ ^[0-9]+$ ]] && [[ $SCHEDULE_HOUR -ge 0 ]] && [[ $SCHEDULE_HOUR -le 23 ]]; then
                    break
                else
                    print_error "Invalid hour. Enter a number between 0 and 23."
                fi
            done
            ;;
    esac

    echo ""
    if [[ $SCHEDULE_HOUR -lt 12 ]]; then
        print_success "Schedule: Days 28-31 at ${SCHEDULE_HOUR}:00 AM"
    elif [[ $SCHEDULE_HOUR -eq 12 ]]; then
        print_success "Schedule: Days 28-31 at 12:00 PM"
    else
        print_success "Schedule: Days 28-31 at $((SCHEDULE_HOUR - 12)):00 PM"
    fi

    echo ""
    read -rp "Press Enter to continue..."
}

step_confirm() {
    print_header
    print_step 6 6 "Confirm Configuration"

    echo -e "${BOLD}Please review your settings:${NC}"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    printf "│ %-20s │ %-36s │\n" "Setting" "Value"
    echo "├─────────────────────────────────────────────────────────────┤"

    if [[ -n "$EMAIL_TO" ]]; then
        printf "│ %-20s │ %-36s │\n" "Email to" "$EMAIL_TO"
    else
        printf "│ %-20s │ %-36s │\n" "Email to" "(disabled)"
    fi

    printf "│ %-20s │ %-36s │\n" "Chrome profile" "$CHROME_PROFILE"
    printf "│ %-20s │ %-36s │\n" "LLM provider" "$LLM_PROVIDER"

    if [[ "$LLM_PROVIDER" == "bedrock" ]]; then
        printf "│ %-20s │ %-36s │\n" "AWS profile" "$AWS_PROFILE"
    fi

    if [[ $SCHEDULE_HOUR -lt 12 ]]; then
        printf "│ %-20s │ %-36s │\n" "Schedule" "Days 28-31 at ${SCHEDULE_HOUR}:00 AM"
    elif [[ $SCHEDULE_HOUR -eq 12 ]]; then
        printf "│ %-20s │ %-36s │\n" "Schedule" "Days 28-31 at 12:00 PM"
    else
        printf "│ %-20s │ %-36s │\n" "Schedule" "Days 28-31 at $((SCHEDULE_HOUR - 12)):00 PM"
    fi

    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    if ! confirm "Is this correct?"; then
        echo ""
        echo "Setup cancelled. Run ./setup.sh to start over."
        exit 0
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION GENERATION
# ══════════════════════════════════════════════════════════════════════════════

generate_config() {
    echo "Generating configuration..."

    # Generate unique job label based on username
    local username
    username=$(whoami)
    JOB_LABEL="com.${username}.chatgpt-receipt"

    # Write config file
    cat > "$CONFIG_FILE" << EOF
# ChatGPT Receipt Downloader Configuration
# Generated by setup wizard on $(date)

# Email recipient (leave empty to disable email)
EMAIL_TO="$EMAIL_TO"

# Chrome profile directory name
CHROME_PROFILE="$CHROME_PROFILE"

# LLM provider: bedrock, anthropic, or openai
LLM_PROVIDER="$LLM_PROVIDER"

# AWS profile (only used if LLM_PROVIDER=bedrock)
AWS_PROFILE="$AWS_PROFILE"

# Schedule hour (0-23)
SCHEDULE_HOUR="$SCHEDULE_HOUR"

# Job label for launchd
JOB_LABEL="$JOB_LABEL"
EOF

    print_success "Created config.env"
}

generate_plist() {
    local plist_file="$SCRIPT_DIR/com.user.chatgpt-receipt.plist"
    local user_home="$HOME"
    local username
    username=$(whoami)

    # Build environment variables section
    local aws_env=""
    if [[ "$LLM_PROVIDER" == "bedrock" ]] && [[ -n "$AWS_PROFILE" ]]; then
        aws_env="
        <key>AWS_PROFILE</key>
        <string>$AWS_PROFILE</string>"
    fi

    cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$JOB_LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$user_home/Scripts/run-chatgpt-receipt.sh</string>
    </array>

    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Day</key>
            <integer>28</integer>
            <key>Hour</key>
            <integer>$SCHEDULE_HOUR</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Day</key>
            <integer>29</integer>
            <key>Hour</key>
            <integer>$SCHEDULE_HOUR</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Day</key>
            <integer>30</integer>
            <key>Hour</key>
            <integer>$SCHEDULE_HOUR</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Day</key>
            <integer>31</integer>
            <key>Hour</key>
            <integer>$SCHEDULE_HOUR</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
    </array>

    <key>EnvironmentVariables</key>
    <dict>$aws_env
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$user_home/.local/bin</string>
        <key>HOME</key>
        <string>$user_home</string>
        <key>LANG</key>
        <string>en_US.UTF-8</string>
        <key>LC_ALL</key>
        <string>en_US.UTF-8</string>
    </dict>

    <key>WorkingDirectory</key>
    <string>$user_home/Scripts</string>

    <key>StandardOutPath</key>
    <string>$user_home/Library/Logs/ChatGPTReceiptDownloader/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$user_home/Library/Logs/ChatGPTReceiptDownloader/launchd-stderr.log</string>

    <key>StartCalendarIntervalAllowsLateExecution</key>
    <true/>

    <key>RunAtLoad</key>
    <false/>

    <key>TimeOut</key>
    <integer>3600</integer>

    <key>Nice</key>
    <integer>10</integer>

    <key>SessionCreate</key>
    <true/>

    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

    print_success "Created plist template"
}

generate_wrapper() {
    # Update wrapper script with config values
    local wrapper_file="$SCRIPT_DIR/run-chatgpt-receipt.sh"

    # Create a sed command to update the values
    sed -i '' \
        -e "s|--provider bedrock|--provider $LLM_PROVIDER|g" \
        -e "s|--profile \"Profile 2\"|--profile \"$CHROME_PROFILE\"|g" \
        -e "s|--email-to \"your-email@example.com\"|--email-to \"$EMAIL_TO\"|g" \
        "$wrapper_file" 2>/dev/null || true

    # If email is empty, remove the email-to lines
    if [[ -z "$EMAIL_TO" ]]; then
        sed -i '' \
            -e '/--email-to/d' \
            "$wrapper_file" 2>/dev/null || true
    fi

    print_success "Updated wrapper script"
}

update_makefile() {
    local makefile="$SCRIPT_DIR/Makefile"

    # Update Makefile with config values
    sed -i '' \
        -e "s|--provider bedrock|--provider $LLM_PROVIDER|g" \
        -e "s|--profile \"Profile 2\"|--profile \"$CHROME_PROFILE\"|g" \
        -e "s|--email-to \"your-email@example.com\"|--email-to \"$EMAIL_TO\"|g" \
        -e "s|PLIST_NAME := com.user.chatgpt-receipt.plist|PLIST_NAME := com.user.chatgpt-receipt.plist|g" \
        -e "s|JOB_LABEL := com.user.chatgpt-receipt|JOB_LABEL := $JOB_LABEL|g" \
        "$makefile" 2>/dev/null || true

    # If email is empty, remove email-to from makefile run targets
    if [[ -z "$EMAIL_TO" ]]; then
        sed -i '' \
            -e '/--email-to/d' \
            "$makefile" 2>/dev/null || true
    fi

    print_success "Updated Makefile"
}

update_installer() {
    local installer="$SCRIPT_DIR/install-launchd.sh"

    # Update installer with config values
    sed -i '' \
        -e "s|PLIST_NAME=\"com.user.chatgpt-receipt.plist\"|PLIST_NAME=\"com.user.chatgpt-receipt.plist\"|g" \
        -e "s|JOB_LABEL=\"com.user.chatgpt-receipt\"|JOB_LABEL=\"$JOB_LABEL\"|g" \
        -e "s|your-email@example.com|$EMAIL_TO|g" \
        "$installer" 2>/dev/null || true

    print_success "Updated installer"
}

# ══════════════════════════════════════════════════════════════════════════════
# FINAL STEPS
# ══════════════════════════════════════════════════════════════════════════════

show_dry_run_summary() {
    local username
    username=$(whoami)
    local job_label="com.${username}.chatgpt-receipt"
    local user_home="$HOME"

    print_header

    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}${BOLD}                    DRY RUN - Preview Only                          ${NC}${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BOLD}Configuration Summary:${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    printf "│ %-20s │ %-36s │\n" "Setting" "Value"
    echo "├─────────────────────────────────────────────────────────────┤"
    if [[ -n "$EMAIL_TO" ]]; then
        printf "│ %-20s │ %-36s │\n" "Email to" "$EMAIL_TO"
    else
        printf "│ %-20s │ %-36s │\n" "Email to" "(disabled)"
    fi
    printf "│ %-20s │ %-36s │\n" "Chrome profile" "$CHROME_PROFILE"
    printf "│ %-20s │ %-36s │\n" "LLM provider" "$LLM_PROVIDER"
    if [[ "$LLM_PROVIDER" == "bedrock" ]]; then
        printf "│ %-20s │ %-36s │\n" "AWS profile" "$AWS_PROFILE"
    fi
    if [[ $SCHEDULE_HOUR -lt 12 ]]; then
        printf "│ %-20s │ %-36s │\n" "Schedule" "Days 28-31 at ${SCHEDULE_HOUR}:00 AM"
    elif [[ $SCHEDULE_HOUR -eq 12 ]]; then
        printf "│ %-20s │ %-36s │\n" "Schedule" "Days 28-31 at 12:00 PM"
    else
        printf "│ %-20s │ %-36s │\n" "Schedule" "Days 28-31 at $((SCHEDULE_HOUR - 12)):00 PM"
    fi
    printf "│ %-20s │ %-36s │\n" "Job label" "$job_label"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    echo -e "${BOLD}Files that would be created/modified:${NC}"
    echo ""
    echo -e "  ${CYAN}Created:${NC}"
    echo "    $SCRIPT_DIR/config.env"
    echo "    $SCRIPT_DIR/com.user.chatgpt-receipt.plist"
    echo ""
    echo -e "  ${CYAN}Modified:${NC}"
    echo "    $SCRIPT_DIR/run-chatgpt-receipt.sh"
    echo "    $SCRIPT_DIR/Makefile"
    echo "    $SCRIPT_DIR/install-launchd.sh"
    echo ""

    echo -e "${BOLD}After running 'make install', would create:${NC}"
    echo ""
    echo "    $user_home/Scripts/download_chatgpt_receipt.py"
    echo "    $user_home/Scripts/run-chatgpt-receipt.sh"
    echo "    $user_home/Scripts/chatgpt-receipt"
    echo "    $user_home/Library/LaunchAgents/com.user.chatgpt-receipt.plist"
    echo ""

    echo -e "${BOLD}Directories that would be created:${NC}"
    echo ""
    echo "    $user_home/Scripts/"
    echo "    $user_home/Library/Logs/ChatGPTReceiptDownloader/"
    echo "    $user_home/Library/Application Support/ChatGPTReceiptDownloader/"
    echo "    $user_home/Documents/ChatGPT-Receipts/"
    echo ""

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}This was a dry run. No files were modified.${NC}"
    echo ""
    echo "To apply this configuration, run:"
    echo -e "  ${CYAN}./setup.sh${NC}"
    echo ""
}

finalize() {
    print_header

    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}${BOLD}                    Setup Complete!                                 ${NC}${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BOLD}Configuration saved to:${NC} config.env"
    echo ""

    echo -e "${BOLD}Next steps:${NC}"
    echo ""
    echo "  1. Install the scheduled job:"
    echo -e "     ${CYAN}make install${NC}"
    echo ""
    echo "  2. Or test manually first:"
    echo -e "     ${CYAN}make test${NC}    (download only, no email)"
    echo -e "     ${CYAN}make run${NC}     (full flow with email)"
    echo ""

    echo -e "${BOLD}Useful commands:${NC}"
    echo -e "  ${CYAN}make status${NC}      Check job status"
    echo -e "  ${CYAN}make schedule${NC}    View next run times"
    echo -e "  ${CYAN}make logs${NC}        View recent logs"
    echo -e "  ${CYAN}make help${NC}        Show all commands"
    echo ""

    if confirm "Would you like to install the scheduled job now?"; then
        echo ""
        make -C "$SCRIPT_DIR" install
    else
        echo ""
        echo "Run 'make install' when you're ready to enable the schedule."
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

main() {
    # Show dry-run notice in header if applicable
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY RUN MODE - No files will be modified]${NC}"
        echo ""
    fi

    # Check if already configured (skip in dry-run mode)
    if [[ -f "$CONFIG_FILE" ]] && ! $DRY_RUN; then
        print_header
        echo -e "${YELLOW}Configuration already exists!${NC}"
        echo ""
        echo "Current config:"
        echo ""
        grep -v "^#" "$CONFIG_FILE" | grep -v "^$" | sed 's/^/  /'
        echo ""

        if ! confirm "Overwrite with new configuration?"; then
            echo ""
            echo "Setup cancelled. Existing configuration preserved."
            exit 0
        fi
    fi

    # Run wizard steps
    step_welcome
    step_prerequisites
    step_email
    step_chrome_profile
    step_llm_provider
    step_schedule
    step_confirm

    # In dry-run mode, show summary and exit
    if $DRY_RUN; then
        show_dry_run_summary
        exit 0
    fi

    # Generate configuration
    echo ""
    generate_config
    generate_plist
    generate_wrapper
    update_makefile
    update_installer

    # Finalize
    finalize
}

main "$@"
